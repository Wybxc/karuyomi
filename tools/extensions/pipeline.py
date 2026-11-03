#!/usr/bin/env python3
"""Resumable local AOT bootstrap and bounded Static Assets incremental builds."""

from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import copy
from functools import lru_cache
import importlib.util
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import urllib.error
import uuid

from catalog import (
    ROOT,
    HOST_PATHS,
    canonical,
    git,
    host_fingerprint,
    host_submodules,
    scan,
    tree_hash,
    digest,
)
from assets import decode_bundle, fetch_bytes, fetch_json, MAX_ENCODED

MAX_STATE_BYTES = 16 * 1024 * 1024

DEFAULT_ASSETS = ROOT / ".local/extensions-assets"
DEFAULT_ORIGIN = "https://karuyomi.wybxc.cc"
STATE_PATH = "/extensions/build-state.json"
INDEX_PATH = "/extensions/index.json"


class BuildCancelled(KeyboardInterrupt):
    pass


class BuilderProcesses:
    """Own builder process groups until shutdown has stopped all their writers."""

    def __init__(self):
        self.cancelled = threading.Event()
        self.signal_number = None
        self.processes = {}
        self.guard = threading.Lock()
        self.state_lock = None
        self.previous_handlers = {}

    def __enter__(self):
        for number in [signal.SIGINT, signal.SIGTERM]:
            self.previous_handlers[number] = signal.signal(number, self.interrupt)
        return self

    def interrupt(self, number, _frame):
        self.signal_number = self.signal_number or number
        self.cancelled.set()

    def check(self):
        if self.cancelled.is_set():
            raise BuildCancelled()

    @staticmethod
    def terminate_group(process):
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            pass
        # The leader can exit before a grandchild that ignores TERM. Kill the
        # whole group even when wait() has already reaped the builder itself.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()

    def run(self, command, **kwargs):
        with self.guard:
            self.check()
            process = subprocess.Popen(command, start_new_session=True, **kwargs)
            self.processes[process.pid] = process
        try:
            while True:
                self.check()
                try:
                    status = process.wait(timeout=0.2)
                    break
                except subprocess.TimeoutExpired:
                    continue
            self.check()
            if status:
                raise subprocess.CalledProcessError(status, command)
        finally:
            self.terminate_group(process)
            with self.guard:
                self.processes.pop(process.pid, None)

    def stop(self):
        self.cancelled.set()
        with self.guard:
            processes = list(self.processes.values())
        for process in processes:
            self.terminate_group(process)

    def __exit__(self, *_error):
        try:
            self.stop()
        finally:
            for number, handler in self.previous_handlers.items():
                signal.signal(number, handler)
            if self.state_lock is not None:
                self.state_lock.close()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(canonical(value) + b"\n")
    os.replace(temporary, path)


def empty_state():
    return {
        "schemaVersion": 1,
        "kind": "static-extension-build-state",
        "revision": None,
        "bootstrap": {"complete": False},
        "attempts": {},
        "active": {},
    }


def validate_state(state):
    if (
        not isinstance(state, dict)
        or state.get("schemaVersion") != 1
        or state.get("kind") != "static-extension-build-state"
        or not isinstance(state.get("attempts"), dict)
        or not isinstance(state.get("active"), dict)
        or not isinstance(state.get("bootstrap"), dict)
    ):
        raise ValueError("Invalid static extension build state")
    revision = state.get("revision")
    if revision is not None and (
        not isinstance(revision, str) or not re.fullmatch("[a-f0-9]{32}", revision)
    ):
        raise ValueError("Invalid snapshot revision")
    for key, record in state["attempts"].items():
        descriptor = record.get("descriptor", {})
        if key != descriptor.get("inputFingerprint") or record.get("status") not in {
            "published",
            "failed",
        }:
            raise ValueError("Invalid build result record")
    for package, key in state["active"].items():
        record = state["attempts"].get(key, {})
        if (
            record.get("status") != "published"
            or record.get("descriptor", {}).get("packageName") != package
        ):
            raise ValueError("Invalid successful build pointer")
    return state


def load_state(path):
    return validate_state(read_json(path)) if Path(path).exists() else empty_state()


def ci_environment():
    return os.environ.get("GITHUB_ACTIONS") == "true" or os.environ.get("CI") == "true"


def make_plan(catalog, state, limit=12, ci=False, retry_failed=False):
    if ci and state.get("bootstrap", {}).get("complete") is not True:
        raise ValueError("CI bootstrap guard: deploy the initial local baseline first")
    if ci and retry_failed:
        raise ValueError("CI cannot retry unchanged failures")
    if not 1 <= limit <= (24 if ci else 10000):
        raise ValueError("Invalid batch limit")
    commit = git(ROOT, "rev-parse", "HEAD")
    pins = host_submodules()
    entries = [
        {**entry, "hostRepositoryCommit": commit, "hostSubmodules": pins}
        for entry in catalog["entries"]
    ]
    pending = [
        entry
        for entry in entries
        if entry["inputFingerprint"] not in state["attempts"]
        or (
            state["attempts"][entry["inputFingerprint"]]["status"] == "published"
            and state["attempts"][entry["inputFingerprint"]].get("available") is False
            and not state["attempts"][entry["inputFingerprint"]].get("rebuildFailure")
        )
        or (
            retry_failed
            and (
                state["attempts"][entry["inputFingerprint"]]["status"] == "failed"
                or state["attempts"][entry["inputFingerprint"]].get("rebuildFailure")
            )
        )
    ]
    return {
        **catalog,
        "entries": entries,
        "repositoryCommit": commit,
        "selected": pending[:limit],
        "pendingCount": len(pending),
        "remainingCount": max(0, len(pending) - limit),
        "ci": ci,
        "baseRevision": state["revision"],
        "snapshotNeeded": bool(
            pending[:limit]
            or state.get("catalogFingerprint") != catalog["catalogFingerprint"]
        ),
    }


def resume_plan(plan, state, limit=10000, retry_failed=False):
    if ci_environment():
        raise ValueError("CI cannot resume an initial frozen baseline")
    if not 1 <= limit <= 10000:
        raise ValueError("Invalid batch limit")
    if not isinstance(plan.get("entries"), list) or not plan["entries"]:
        raise ValueError("Frozen plan must contain its complete catalog")
    first = plan["entries"][0]
    for entry in plan["entries"]:
        if any(
            entry.get(key) != first.get(key)
            for key in [
                "hostRepositoryCommit",
                "hostFingerprint",
                "hostInputs",
                "hostSubmodules",
                "upstreamCommit",
            ]
        ):
            raise ValueError("Frozen plan mixes host or source identities")
    pending = [
        entry
        for entry in plan["entries"]
        if entry["inputFingerprint"] not in state["attempts"]
        or (
            state["attempts"][entry["inputFingerprint"]]["status"] == "published"
            and state["attempts"][entry["inputFingerprint"]].get("available") is False
            and not state["attempts"][entry["inputFingerprint"]].get("rebuildFailure")
        )
        or (
            retry_failed
            and (
                state["attempts"][entry["inputFingerprint"]]["status"] == "failed"
                or state["attempts"][entry["inputFingerprint"]].get("rebuildFailure")
            )
        )
    ]
    return {
        **plan,
        "selected": pending[:limit],
        "pendingCount": len(pending),
        "remainingCount": max(0, len(pending) - limit),
        "ci": False,
        "baseRevision": state["revision"],
    }


def validate_build_checkout(checkout, descriptor):
    checkout = Path(checkout).resolve()
    if git(checkout, "rev-parse", "HEAD") != descriptor.get("hostRepositoryCommit"):
        raise ValueError("Build checkout differs from the frozen host commit")
    names = descriptor.get("hostInputs", {})
    if not names or git(checkout, "status", "--porcelain", "--", *names):
        raise ValueError("Frozen host inputs must be present and clean")
    pins = host_submodules(checkout)
    if pins != descriptor.get("hostSubmodules"):
        raise ValueError("Frozen host submodules changed")
    inputs = {name: tree_hash(checkout, name) for name in names}
    actual = digest(
        canonical({"schemaVersion": 1, "inputs": inputs, "pinnedSubmodules": pins})
    )
    if inputs != names or actual != descriptor["hostFingerprint"]:
        raise ValueError("Frozen host fingerprint mismatch")
    source = checkout / "vendor/extensions-source"
    if git(source, "rev-parse", "HEAD") != descriptor["upstreamCommit"]:
        raise ValueError("Frozen source checkout changed")
    return checkout


@lru_cache(maxsize=4)
def checkout_material_catalog(checkout):
    root = Path(checkout)
    script = root / "packages/runtime-host/prepare-materials.ts"
    return json.loads(
        subprocess.check_output(["node", str(script), "--print"], cwd=root, text=True)
    )


@lru_cache(maxsize=1)
def verifier():
    spec = importlib.util.spec_from_file_location(
        "extension_verifier", ROOT / "scripts/register-build.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class VerifiedBuild(dict):
    """One process owns these verified transfer bytes; later stages reuse them."""

    def __init__(self, result, manifest, directory, validation):
        super().__init__(result)
        self.manifest, self.validation = manifest, validation
        self.file = (
            Path(directory) / "artifacts" / (manifest["bundle"]["sha256"] + ".gz")
        )
        self.signature = self.identity()

    def identity(self):
        info = self.file.stat()
        return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns

    def payload(self):
        if self.identity() != self.signature:
            raise ValueError("Verified output changed before snapshot assembly")
        return self.file.read_bytes()


def verify_output(directory, descriptor=None, *, build_checkout=None):
    directory = Path(directory)
    if directory.is_symlink() or any(
        file.is_symlink() for file in directory.rglob("*")
    ):
        raise ValueError("Build output must not contain symlinks")
    for name in ["manifest.json", "validation.json", "provenance.json"]:
        file = directory / name
        if file.exists() and file.stat().st_size > 2 * 1024 * 1024:
            raise ValueError("Oversized build metadata")
    manifest = read_json(directory / "manifest.json")
    verifier().verify(
        manifest,
        directory / "artifacts",
        verify_hashes=False,
        material_catalog_override=checkout_material_catalog(str(build_checkout))
        if build_checkout
        else None,
    )
    if descriptor and any(
        manifest[field] != descriptor[name]
        for field, name in [
            ("packageName", "packageName"),
            ("buildId", "buildId"),
            ("version", "versionName"),
        ]
    ):
        raise ValueError("Build output differs from its pinned descriptor")
    reference = manifest["bundle"]
    file = directory / "artifacts" / (reference["sha256"] + ".gz")
    if file.stat().st_size != reference["encodedSize"]:
        raise ValueError("Encoded bundle size mismatch")
    encoded = file.read_bytes()
    decode_bundle(encoded, reference)
    validation_path = directory / "validation.json"
    validation = (
        read_json(validation_path)
        if validation_path.exists()
        else {
            "schemaVersion": 1,
            "valid": False,
            "stages": {
                "artifactIntegrity": "passed",
                "workerInit": "not_run",
                "browserLoad": "not_run",
            },
        }
    )
    stages = validation.get("stages", {})
    validation["runtimeReady"] = (
        validation.get("valid") is True
        and all(
            stages.get(key) == "passed"
            for key in ["artifactIntegrity", "workerInit", "browserLoad"]
        )
        and validation.get("buildId") == manifest["buildId"]
        and validation.get("manifestSha256")
        == digest((directory / "manifest.json").read_bytes())
    )
    return manifest, encoded, validation


def build_one(
    descriptor, output, build_checkout=None, processes=None, retry_failed=False
):
    processes = processes or BuilderProcesses()
    processes.check()
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    result = {"schemaVersion": 1, "descriptor": descriptor, "status": "failed"}
    try:
        checkout = Path(build_checkout or ROOT).resolve()
        if build_checkout:
            validate_build_checkout(checkout, descriptor)
        saved = output / "pipeline-result.json"
        if saved.is_file():
            cached = read_json(saved)
            if cached.get("descriptor") == descriptor:
                if cached.get("status") == "built":
                    manifest, encoded, validation = verify_output(
                        output, descriptor, build_checkout=build_checkout
                    )
                    cleanup_built_work(output, descriptor, build_checkout)
                    return VerifiedBuild(cached, manifest, output, validation)
                if cached.get("status") == "failed" and not retry_failed:
                    return cached
        current = (
            host_fingerprint()[0]
            if not build_checkout
            else descriptor["hostFingerprint"]
        )
        if current != descriptor["hostFingerprint"]:
            raise ValueError("Host inputs changed since planning")
        if (
            git(checkout / "vendor/extensions-source", "rev-parse", "HEAD")
            != descriptor["upstreamCommit"]
        ):
            raise ValueError("Source checkout differs from the planned commit")
        # Explicitly retried failed attempts cannot inherit a partial old output.
        for name in ["manifest.json", "validation.json", "provenance.json"]:
            (output / name).unlink(missing_ok=True)
        if (output / "artifacts").exists():
            shutil.rmtree(output / "artifacts")
        descriptor_path = output / "descriptor.json"
        write_json(descriptor_path, descriptor)
        with (output / "build.log").open("w") as log:
            environment = {
                key: value
                for key, value in os.environ.items()
                if key not in {"GH_TOKEN", "GITHUB_TOKEN", "CLOUDFLARE_API_TOKEN"}
            }
            processes.run(
                [
                    sys.executable,
                    str(checkout / "scripts/build-extension.py"),
                    "--descriptor",
                    str(descriptor_path),
                    "--output",
                    str(output),
                ],
                cwd=checkout,
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        manifest, encoded, validation = verify_output(
            output, descriptor, build_checkout=build_checkout
        )
        write_json(output / "validation.json", validation)
        result.update(
            status="built",
            validationStatus="browser_verified"
            if validation["runtimeReady"]
            else "compiled_unverified",
        )
        write_json(saved, result)
        cleanup_built_work(output, descriptor, build_checkout)
        return VerifiedBuild(result, manifest, output, validation)
    except Exception as error:
        result["failure"] = {
            "stage": "build",
            "code": type(error).__name__,
            "message": str(error)[:500],
        }
        failure_path = output / "build-result.json"
        if isinstance(error, subprocess.CalledProcessError) and failure_path.is_file():
            failure = read_json(failure_path).get("failure", {})
            if failure.get("stage") in {"upstream", "host", "aot", "complete"}:
                result["failure"] = {
                    "stage": failure["stage"],
                    "code": str(failure.get("code", "build_failed"))[:100],
                    "message": "Official extension build failed; see local build log",
                }
    write_json(output / "pipeline-result.json", result)
    return result


def record_result(state, descriptor, result, directory, build_checkout=None):
    key = descriptor["inputFingerprint"]
    record = {
        "descriptor": descriptor,
        "status": "failed",
        "attempts": state["attempts"].get(key, {}).get("attempts", 0) + 1,
    }
    verified = None
    if result.get("descriptor") != descriptor or result.get("status") != "built":
        record["failure"] = result.get(
            "failure",
            {
                "stage": "build",
                "code": "missing_result",
                "message": "No matching successful build output",
            },
        )
    else:
        try:
            if isinstance(result, VerifiedBuild):
                manifest, validation = result.manifest, result.validation
            else:
                manifest, encoded, validation = verify_output(
                    directory, descriptor, build_checkout=build_checkout
                )
            record.update(
                status="published",
                available=True,
                runtimeIdentity=runtime_identity(manifest),
                runtimeReady=validation["runtimeReady"],
                validationStatus="browser_verified"
                if validation["runtimeReady"]
                else "compiled_unverified",
            )
            verified = (
                result
                if isinstance(result, VerifiedBuild)
                else VerifiedBuild(result, manifest, directory, validation)
            )
            state["active"][descriptor["packageName"]] = key
        except Exception as error:
            record["status"] = "failed"
            record["failure"] = {
                "stage": "integrity",
                "code": type(error).__name__,
                "message": str(error)[:500],
            }
    if (
        record["status"] == "failed"
        and state["active"].get(descriptor["packageName"]) == key
    ):
        previous = state["attempts"][key]
        record = {
            **previous,
            "attempts": record["attempts"],
            "available": False,
            "rebuildFailure": record["failure"],
        }
    state["attempts"][key] = record
    return record, verified


def finalize_baseline(state, catalog, local=True):
    if not local or ci_environment():
        raise ValueError("CI cannot create or finalize the initial baseline")
    records = [
        state["attempts"].get(entry["inputFingerprint"]) for entry in catalog["entries"]
    ]
    if any(
        record is None or record["status"] not in {"published", "failed"}
        for record in records
    ):
        raise ValueError("Initial baseline still has unattempted packages")
    state["bootstrap"] = {
        "complete": True,
        "upstreamCommit": catalog["upstreamCommit"],
        "catalogFingerprint": catalog["catalogFingerprint"],
        "published": sum(record["status"] == "published" for record in records),
        "failed": sum(record["status"] == "failed" for record in records),
        "discoveryFailed": len(catalog["discoveryFailures"]),
    }


def runtime_identity(manifest):
    return {
        key: manifest[key]
        for key in [
            "protocolVersion",
            "hostAbi",
            "runtimeBaseline",
            "bridgeVersion",
            "hostScripts",
            "resources",
        ]
    }


def current_runtime(build_checkout=None):
    catalog = checkout_material_catalog(str(build_checkout or ROOT))
    return {
        **{
            key: catalog[key]
            for key in [
                "protocolVersion",
                "hostAbi",
                "runtimeBaseline",
                "hostScripts",
                "resources",
            ]
        },
        "bridgeVersion": 2,
    }


def static_index(manifests):
    return {
        "schemaVersion": 1,
        "builds": [
            {
                **{
                    key: manifest[key]
                    for key in [
                        "buildId",
                        "packageName",
                        "repoId",
                        "version",
                        "sourceIds",
                    ]
                },
                "manifestPath": "/extensions/builds/"
                + manifest["buildId"]
                + "/manifest.json",
            }
            for manifest in sorted(manifests, key=lambda item: item["packageName"])
        ],
        "nextCursor": None,
    }


def replace_directory(staged, destination):
    """Keep the previous complete directory if swapping the candidate fails."""
    destination = Path(destination)
    backup = destination.with_name(destination.name + ".previous")
    if backup.exists():
        raise ValueError("Interrupted snapshot swap: inspect the previous directory")
    had_previous = destination.exists()
    if had_previous:
        os.replace(destination, backup)
    try:
        os.replace(staged, destination)
    except BaseException:
        if had_previous:
            os.replace(backup, destination)
        raise
    if had_previous:
        shutil.rmtree(backup)


def prepare_snapshot(
    plan,
    state,
    results,
    assets_dir=DEFAULT_ASSETS,
    origin=DEFAULT_ORIGIN,
    finalize=False,
    build_checkout=None,
    processes=None,
    verified_results=None,
):
    """Prepare a complete candidate; never mark its state as deployed here."""
    processes = processes or BuilderProcesses()
    processes.check()
    if plan.get("baseRevision") != state["revision"]:
        raise ValueError("Plan was based on a different deployed snapshot")
    candidate = copy.deepcopy(state)
    current = {entry["packageName"]: entry for entry in plan["entries"]}
    discovery_paths = {failure["sourcePath"] for failure in plan["discoveryFailures"]}
    retained_discovery = set()
    for package, key in state["active"].items():
        descriptor = state["attempts"][key]["descriptor"]
        if package not in current and descriptor.get("sourcePath") in discovery_paths:
            current[package] = descriptor
            retained_discovery.add(package)
    verified = {}
    result_paths = list(Path(results).rglob("pipeline-result.json"))
    result_by_key = {}
    for file in result_paths:
        result = read_json(file)
        descriptor = result.get("descriptor", {})
        key = descriptor.get("inputFingerprint")
        if key in result_by_key:
            raise ValueError("Ambiguous duplicate build results")
        result_by_key[key] = (file.parent, result)
    result_by_key.update(verified_results or {})
    for descriptor in plan["selected"]:
        processes.check()
        key = descriptor["inputFingerprint"]
        if key not in result_by_key:
            raise ValueError(
                "Missing matrix result; keep the previous snapshot and retry the interrupted build"
            )
        directory, result = result_by_key[key]
        record, content = record_result(
            candidate, descriptor, result, directory, build_checkout
        )
        if content is not None:
            verified[descriptor["packageName"]] = content
    candidate["active"] = {
        package: key
        for package, key in candidate["active"].items()
        if package in current
    }
    retained = {entry["inputFingerprint"] for entry in current.values()} | set(
        candidate["active"].values()
    )
    candidate["attempts"] = {
        key: record for key, record in candidate["attempts"].items() if key in retained
    }
    candidate.update(
        discoveryFailures=plan["discoveryFailures"],
        upstreamCommit=plan["upstreamCommit"],
        hostFingerprint=plan["hostFingerprint"],
        catalogFingerprint=plan["catalogFingerprint"],
        parentRevision=state["revision"],
        revision=uuid.uuid4().hex,
    )
    if finalize:
        finalize_baseline(candidate, plan)
    assets_dir = Path(assets_dir).resolve()
    assets_dir.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=assets_dir.name + ".stage-", dir=assets_dir.parent
    ) as temporary:
        staged = Path(temporary) / "snapshot"
        extension = staged / "extensions"
        (extension / "artifacts").mkdir(parents=True)
        manifests = []
        identity = current_runtime(build_checkout)
        for package, key in sorted(candidate["active"].items()):
            processes.check()
            record = candidate["attempts"][key]
            descriptor = record["descriptor"]
            record["stale"] = (
                key != current[package]["inputFingerprint"]
                or package in retained_discovery
            )
            if record.get("runtimeIdentity") != identity:
                record.update(available=False, availability="stale_host")
                continue
            if package not in verified and record.get("available") is False:
                # A previous snapshot intentionally did not publish this old ABI.
                # Its state alone is not a recoverable artifact cache.
                record["availability"] = "rebuild_required"
                continue
            record.update(
                available=True,
                availability="discovery_failed"
                if package in retained_discovery
                else "available",
            )
            if package in verified:
                receipt = verified.pop(package)
                manifest, encoded = receipt.manifest, receipt.payload()
            else:
                manifest_path = (
                    "/extensions/builds/" + descriptor["buildId"] + "/manifest.json"
                )
                manifest = fetch_json(origin, manifest_path)
                if any(
                    manifest.get(field) != descriptor[name]
                    for field, name in [
                        ("buildId", "buildId"),
                        ("packageName", "packageName"),
                        ("version", "versionName"),
                    ]
                ):
                    raise ValueError("Static successful build identity mismatch")
                encoded = fetch_bytes(origin, manifest["bundle"]["path"], MAX_ENCODED)
                decode_bundle(encoded, manifest["bundle"])
            bundle = manifest["bundle"]
            (extension / "artifacts" / (bundle["sha256"] + ".gz")).write_bytes(encoded)
            manifest_folder = extension / "builds" / descriptor["buildId"]
            write_json(manifest_folder / "manifest.json", manifest)
            # Schema, size, and shared material checks reuse the verified bytes.
            verifier().verify(
                manifest,
                extension / "artifacts",
                verify_hashes=False,
                material_catalog_override=checkout_material_catalog(str(build_checkout))
                if build_checkout
                else None,
            )
            manifests.append(manifest)
        candidate["summary"] = {
            "available": len(manifests),
            "unavailable": sum(
                not candidate["attempts"][key].get("available", False)
                for key in candidate["active"].values()
            ),
            "failed": sum(
                record["status"] == "failed"
                for record in candidate["attempts"].values()
            ),
            "pending": sum(
                entry["inputFingerprint"] not in candidate["attempts"]
                for entry in current.values()
            ),
        }
        index_bytes = canonical(static_index(manifests)) + b"\n"
        if len(index_bytes) > 2 * 1024 * 1024:
            raise ValueError("Static extension index exceeds 2 MiB")
        (extension / "index.json").write_bytes(index_bytes)
        candidate["indexSha256"] = digest(index_bytes)
        state_bytes = canonical(validate_state(candidate)) + b"\n"
        if len(state_bytes) > MAX_STATE_BYTES:
            raise ValueError("Static build state exceeds 16 MiB")
        (extension / "build-state.json").write_bytes(state_bytes)
        processes.check()
        replace_directory(staged, assets_dir)
    return candidate


def remote_state(origin, allow_missing=False):
    try:
        return validate_state(fetch_json(origin, STATE_PATH))
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        if status == 404 and allow_missing:
            return empty_state()
        raise ValueError(
            "Static build state unavailable; cannot infer a baseline"
        ) from error


def pull_state(origin, path):
    try:
        state = remote_state(origin)
    except json.JSONDecodeError:
        raise ValueError(
            "Static baseline is not JSON; CI cannot initialize or infer a missing baseline"
        ) from None
    index = fetch_bytes(origin, INDEX_PATH)
    if digest(index) != state.get("indexSha256"):
        raise ValueError("Static index and build state are from different snapshots")
    if state["bootstrap"].get("complete") is not True or state["revision"] is None:
        raise ValueError("CI bootstrap guard: deploy the initial local baseline first")
    write_json(path, state)
    return state


def check_base(assets_dir, origin, initialize=False):
    candidate = validate_state(
        read_json(Path(assets_dir) / "extensions/build-state.json")
    )
    if initialize and (ci_environment() or candidate.get("parentRevision") is not None):
        raise ValueError(
            "Explicit initialization is local-only and requires no previous baseline"
        )
    try:
        remote = remote_state(
            origin, allow_missing=candidate.get("parentRevision") is None
        )
    except json.JSONDecodeError:
        if not initialize:
            raise ValueError(
                "Static build state is not JSON; use explicit local initialization only for the known pre-baseline SPA"
            ) from None
        body = fetch_bytes(origin, STATE_PATH)
        if not body.lstrip().lower().startswith((b"<!doctype html", b"<html")):
            raise ValueError(
                "Initialization cannot replace an arbitrary invalid response"
            ) from None
        remote = empty_state()
    if remote["revision"] != candidate.get("parentRevision"):
        raise ValueError(
            "Remote static snapshot advanced; pull and replan before deploying"
        )


def commit_snapshot(state_path, assets_dir, origin):
    assets_dir = Path(assets_dir)
    candidate = validate_state(read_json(assets_dir / "extensions/build-state.json"))
    index_bytes = (assets_dir / "extensions/index.json").read_bytes()
    if (
        digest(index_bytes) != candidate.get("indexSha256")
        or remote_state(origin) != candidate
        or fetch_bytes(origin, INDEX_PATH) != index_bytes
    ):
        raise ValueError("Static deployment is not confirmed; checkpoint unchanged")
    persisted = load_state(state_path)
    if persisted["revision"] not in {
        candidate.get("parentRevision"),
        candidate["revision"],
    }:
        raise ValueError("Local checkpoint advanced; refusing to overwrite it")
    write_json(state_path, candidate)
    return candidate


def cleanup_built_work(directory, descriptor, build_checkout=None):
    """Valid output persisted locally is enough to discard only compiler work."""
    saved = read_json(Path(directory) / "pipeline-result.json")
    if saved.get("status") != "built" or saved.get("descriptor") != descriptor:
        raise ValueError(
            "Successful build checkpoint must be saved before cache cleanup"
        )
    build_id = descriptor.get("buildId")
    if not isinstance(build_id, str) or not re.fullmatch(
        r"[A-Za-z0-9][A-Za-z0-9._-]{0,199}", build_id
    ):
        raise ValueError("Unsafe build ID for cache cleanup")
    try:
        return remove_build_work(build_id, build_checkout)
    except (OSError, RuntimeError) as error:
        print(
            "extensions: retained compiler work: " + str(error),
            file=sys.stderr,
            flush=True,
        )
        return []


def remove_build_work(build_id, build_checkout=None):
    local = Path(build_checkout or ROOT) / "runtime/teavm/.local"
    if local.resolve() != local or local.is_symlink():
        raise ValueError("Cache cleanup root must not contain symbolic links")
    if not local.exists():
        return []
    if not shutil.rmtree.avoids_symlink_attacks:
        raise RuntimeError("This platform does not support safe directory cleanup")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    removed = []
    local_fd = os.open(local, flags)
    try:
        for name in ["extension-work", "extension-cache", "gradle-launcher"]:
            try:
                parent_fd = os.open(name, flags, dir_fd=local_fd)
            except FileNotFoundError:
                continue
            try:
                try:
                    info = os.stat(build_id, dir_fd=parent_fd, follow_symlinks=False)
                except FileNotFoundError:
                    continue
                if stat.S_ISLNK(info.st_mode):
                    os.unlink(build_id, dir_fd=parent_fd)
                elif stat.S_ISDIR(info.st_mode):
                    # fd-based rmtree unlinks m2/nested symlinks without entering
                    # their targets, and checks directory swaps while descending.
                    shutil.rmtree(build_id, dir_fd=parent_fd)
                else:
                    raise ValueError("Expected a disposable build directory: " + name)
                removed.append(name + "/" + build_id)
            finally:
                os.close(parent_fd)
    finally:
        os.close(local_fd)
    return removed


def run_pipeline(processes):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ["plan", "bootstrap"]:
        command = commands.add_parser(name)
        command.add_argument(
            "--source", type=Path, default=ROOT / "vendor/extensions-source"
        )
        command.add_argument("--state", type=Path, required=True)
        command.add_argument("--output", type=Path, required=True)
        command.add_argument(
            "--limit", type=int, default=12 if name == "plan" else 10000
        )
        command.add_argument("--retry-failed", action="store_true")
        command.add_argument("--ci", action="store_true")
        if name == "bootstrap":
            command.add_argument("--jobs", type=int, default=1)
            command.add_argument("--finalize", action="store_true")
            command.add_argument("--plan", type=Path)
            command.add_argument("--build-checkout", type=Path)
            command.add_argument("--assets-dir", type=Path, default=DEFAULT_ASSETS)
            command.add_argument("--origin", default=DEFAULT_ORIGIN)
    command = commands.add_parser("build")
    command.add_argument("--plan", type=Path, required=True)
    command.add_argument("--key", required=True)
    command.add_argument("--output", type=Path, required=True)
    command = commands.add_parser("prepare-snapshot")
    command.add_argument("--plan", type=Path, required=True)
    command.add_argument("--state", type=Path, required=True)
    command.add_argument("--results", type=Path, required=True)
    command.add_argument("--assets-dir", type=Path, default=DEFAULT_ASSETS)
    command.add_argument("--origin", default=DEFAULT_ORIGIN)
    for name in ["pull-state", "check-base", "commit-snapshot"]:
        command = commands.add_parser(name)
        command.add_argument("--origin", default=DEFAULT_ORIGIN)
        if name == "check-base":
            command.add_argument("--initialize", action="store_true")
        if name != "check-base":
            command.add_argument("--state", type=Path, required=True)
        if name != "pull-state":
            command.add_argument("--assets-dir", type=Path, default=DEFAULT_ASSETS)
    args = parser.parse_args()
    if hasattr(args, "state"):
        import fcntl

        args.state.parent.mkdir(parents=True, exist_ok=True)
        processes.state_lock = args.state.with_suffix(".lock").open("a")
        try:
            fcntl.flock(processes.state_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error("Another process owns this extension checkpoint")
    if args.command == "pull-state":
        pull_state(args.origin, args.state)
    elif args.command == "check-base":
        check_base(args.assets_dir, args.origin, args.initialize)
    elif args.command == "commit-snapshot":
        commit_snapshot(args.state, args.assets_dir, args.origin)
    elif args.command == "prepare-snapshot":
        prepare_snapshot(
            read_json(args.plan),
            load_state(args.state),
            args.results,
            args.assets_dir,
            args.origin,
            processes=processes,
        )
    elif args.command == "build":
        plan = read_json(args.plan)
        descriptor = next(
            entry for entry in plan["selected"] if entry["inputFingerprint"] == args.key
        )
        result = build_one(descriptor, args.output, processes=processes)
        print(
            json.dumps(
                {"packageName": descriptor["packageName"], "status": result["status"]}
            )
        )
        if result["status"] != "built":
            raise SystemExit(1)
    else:
        bootstrap = args.command == "bootstrap"
        if bootstrap and (args.ci or ci_environment()):
            parser.error("Initial full bootstrap is local-only")
        state = load_state(args.state)
        if bootstrap and args.plan:
            if args.build_checkout is None:
                parser.error("--plan requires --build-checkout")
            plan = resume_plan(
                read_json(args.plan), state, args.limit, args.retry_failed
            )
            args.build_checkout = validate_build_checkout(
                args.build_checkout, plan["entries"][0]
            )
        else:
            if bootstrap and args.build_checkout:
                parser.error("--build-checkout requires --plan")
            if bootstrap and git(ROOT, "status", "--porcelain", "--", *HOST_PATHS):
                parser.error(
                    "Commit the reviewed host inputs before the initial baseline"
                )
            host, inputs = host_fingerprint()
            plan = make_plan(
                scan(args.source, host, inputs),
                state,
                args.limit,
                args.ci or ci_environment(),
                args.retry_failed,
            )
        write_json(args.output, plan)
        print(
            json.dumps(
                {
                    "discovered": len(plan["entries"]),
                    "selected": len(plan["selected"]),
                    "remaining": plan["remainingCount"],
                }
            ),
            flush=True,
        )
        if not bootstrap:
            return
        if not 1 <= args.jobs <= 4:
            parser.error("--jobs must be between 1 and 4")
        builds = args.output.parent / "builds"
        pool = ThreadPoolExecutor(max_workers=args.jobs)
        futures = {}
        completed = {}
        try:
            futures = {
                pool.submit(
                    build_one,
                    entry,
                    builds / entry["inputFingerprint"],
                    args.build_checkout,
                    processes,
                    args.retry_failed,
                ): entry
                for entry in plan["selected"]
            }
            for future in as_completed(futures):
                processes.check()
                result = future.result()
                entry = futures.pop(future)
                completed[entry["inputFingerprint"]] = (
                    builds / entry["inputFingerprint"],
                    result,
                )
                print(entry["packageName"] + ": " + result["status"], flush=True)
        finally:
            if processes.cancelled.is_set():
                for future in futures:
                    future.cancel()
                processes.stop()
            pool.shutdown(wait=True, cancel_futures=True)
        processes.check()
        prepare_snapshot(
            plan,
            state,
            builds,
            args.assets_dir,
            args.origin,
            args.finalize,
            args.build_checkout,
            processes,
            completed,
        )


def main():
    with BuilderProcesses() as processes:
        try:
            run_pipeline(processes)
            processes.check()
        except BuildCancelled:
            print(
                "extensions: cancelled; prior snapshot and completed build results retained",
                file=sys.stderr,
                flush=True,
            )
            raise SystemExit(128 + (processes.signal_number or signal.SIGINT))


if __name__ == "__main__":
    main()
