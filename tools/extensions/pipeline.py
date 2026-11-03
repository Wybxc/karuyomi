#!/usr/bin/env python3
"""Resumable local bootstrap and bounded incremental private-release pipeline."""

from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import importlib.util
from functools import lru_cache
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

from catalog import (
    ROOT,
    HOST_PATHS,
    canonical,
    digest,
    extension_tag,
    git,
    host_fingerprint,
    host_submodules,
    scan,
    tree_hash,
)
from releases import (
    GitHub,
    download_release,
    encode_artifact,
    capture_files,
    publish_locator,
    release_pointer,
    restore_artifacts,
)


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
        "bootstrap": {"complete": False},
        "attempts": {},
        "active": {},
        "remoteIndexTag": None,
    }


def load_state(path):
    state = read_json(path) if Path(path).exists() else empty_state()
    if (
        state.get("schemaVersion") != 1
        or not isinstance(state.get("attempts"), dict)
        or not isinstance(state.get("active"), dict)
    ):
        raise ValueError("Invalid extension checkpoint")
    return state


def ci_environment():
    return os.environ.get("GITHUB_ACTIONS") == "true" or os.environ.get("CI") == "true"


def make_plan(catalog, state, limit=12, ci=False, retry_failed=False):
    if ci and state.get("bootstrap", {}).get("complete") is not True:
        raise ValueError(
            "CI bootstrap guard: finish and publish the initial local baseline first"
        )
    if ci and retry_failed:
        raise ValueError("CI cannot retry an unchanged full failure baseline")
    if not 1 <= limit <= (24 if ci else 10000):
        raise ValueError("Invalid batch limit")
    repository_commit = git(ROOT, "rev-parse", "HEAD")
    pinned_submodules = host_submodules()
    entries = [
        {
            **entry,
            "hostRepositoryCommit": repository_commit,
            "hostSubmodules": pinned_submodules,
        }
        for entry in catalog["entries"]
    ]
    pending = []
    for entry in entries:
        previous = state["attempts"].get(entry["inputFingerprint"])
        if previous is None or (
            previous["status"] == "failed"
            and (
                retry_failed
                or previous.get("retryable")
                and previous.get("attempts", 0) < 3
            )
        ):
            pending.append(entry)
    return {
        **catalog,
        "entries": entries,
        "repositoryCommit": repository_commit,
        "selected": pending[:limit],
        "pendingCount": len(pending),
        "remainingCount": max(0, len(pending) - limit),
        "ci": ci,
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


def resume_plan(plan, state, limit=10000, retry_failed=False):
    if ci_environment():
        raise ValueError("CI cannot resume an initial frozen baseline")
    if not 1 <= limit <= 10000:
        raise ValueError("Invalid batch limit")
    if not isinstance(plan.get("entries"), list) or not plan["entries"]:
        raise ValueError("Frozen plan must contain its complete catalog")
    entries = plan["entries"]
    first = entries[0]
    if any(
        any(
            entry.get(key) != first.get(key)
            for key in [
                "hostRepositoryCommit",
                "hostFingerprint",
                "hostInputs",
                "hostSubmodules",
                "upstreamCommit",
            ]
        )
        for entry in entries
    ):
        raise ValueError("Frozen plan mixes host or source identities")
    pending = []
    for entry in entries:
        previous = state["attempts"].get(entry["inputFingerprint"])
        if (
            previous is None
            or previous.get("status") == "built"
            or (
                previous.get("status") == "failed"
                and (
                    retry_failed
                    or previous.get("retryable")
                    and previous.get("attempts", 0) < 3
                )
            )
        ):
            pending.append(entry)
    return {
        **plan,
        "selected": pending[:limit],
        "pendingCount": len(pending),
        "remainingCount": max(0, len(pending) - limit),
        "ci": False,
    }


@lru_cache(maxsize=4)
def checkout_material_catalog(checkout):
    root = Path(checkout)
    script = root / "packages/runtime-host/prepare-materials.ts"
    if not script.is_file():
        script = script.with_suffix(".mjs")
    return json.loads(
        subprocess.check_output(["node", str(script), "--print"], cwd=root, text=True)
    )


def verify_output(
    directory, descriptor=None, *, verify_hashes=True, build_checkout=None
):
    directory = Path(directory)
    if directory.is_symlink() or any(
        file.is_symlink() for file in directory.rglob("*")
    ):
        raise ValueError("Build output must not contain symlinks")
    for name in ["manifest.json", "validation.json", "provenance.json"]:
        if (directory / name).exists() and (
            directory / name
        ).stat().st_size > 2 * 1024 * 1024:
            raise ValueError("Oversized build metadata")
    manifest = read_json(directory / "manifest.json")
    spec = importlib.util.spec_from_file_location(
        "registered_build", ROOT / "scripts/register-build.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    artifacts = module.verify(
        manifest,
        directory / "artifacts",
        verify_hashes=verify_hashes,
        material_catalog_override=checkout_material_catalog(str(build_checkout))
        if build_checkout
        else None,
    )
    if descriptor and (
        manifest["packageName"] != descriptor["packageName"]
        or manifest["buildId"] != descriptor["buildId"]
        or manifest["version"] != descriptor["versionName"]
    ):
        raise ValueError("Build output differs from its pinned descriptor")
    validation_path = directory / "validation.json"
    validation = (
        read_json(validation_path)
        if validation_path.exists()
        else {
            "schemaVersion": 1,
            "valid": False,
            "buildId": manifest["buildId"],
            "manifestSha256": digest((directory / "manifest.json").read_bytes()),
            "stages": {
                "artifactIntegrity": "passed",
                "workerInit": "not_run",
                "browserLoad": "not_run",
            },
            "failure": {
                "code": "browser_not_run",
                "message": "Compilation is not browser compatibility evidence",
            },
        }
    )
    stages = validation.get("stages", {})
    verified = (
        validation.get("valid") is True
        and stages.get("artifactIntegrity") == "passed"
        and stages.get("workerInit") == "passed"
        and stages.get("browserLoad") == "passed"
        and validation.get("buildId") == manifest["buildId"]
        and validation.get("manifestSha256")
        == digest((directory / "manifest.json").read_bytes())
    )
    validation["runtimeReady"] = verified
    return manifest, artifacts, validation


def release_files(directory, descriptor, encoding="gzip", build_checkout=None):
    directory = Path(directory)
    manifest, artifacts, validation = verify_output(
        directory, descriptor, verify_hashes=False, build_checkout=build_checkout
    )
    known = {}
    provenance = {
        "schemaVersion": 1,
        "kind": "source-aot",
        "descriptor": descriptor,
        "manifestSha256": digest((directory / "manifest.json").read_bytes()),
        "validationStatus": "browser_verified"
        if validation["runtimeReady"]
        else "compiled_unverified",
    }
    files = {sha: directory / "artifacts" / sha for sha in artifacts}
    if encoding != "gzip":
        raise ValueError("Unknown release artifact encoding")
    if encoding == "gzip":
        bundle_sha = manifest["bundle"]["sha256"]
        transport = directory / "release-transport"
        if (transport / "artifact-encodings.json").is_file():
            # Reuse exact transport bytes on an upload retry, even if a different
            # zlib version would encode the same canonical bundle differently.
            with tempfile.TemporaryDirectory(
                prefix="karuyomi-check-encoding-"
            ) as temporary:
                restore_artifacts(
                    transport,
                    temporary,
                    {bundle_sha: artifacts[bundle_sha]},
                    bundle_sha,
                )
            encoded = (transport / (bundle_sha + ".gz")).read_bytes()
            table = (transport / "artifact-encodings.json").read_bytes()
            entry = json.loads(table)["artifacts"][0]
        else:
            encoded, entry = encode_artifact(bundle_sha, files[bundle_sha])
            table = canonical({"schemaVersion": 1, "artifacts": [entry]}) + b"\n"
        del files[bundle_sha]
        files[bundle_sha + ".gz"] = encoded
        known[bundle_sha + ".gz"] = {
            "sha256": entry["encodedSha256"],
            "size": entry["encodedSize"],
        }
        files["artifact-encodings.json"] = table
    files["manifest.json"] = directory / "manifest.json"
    files["provenance.json"] = canonical(provenance) + b"\n"
    files["validation.json"] = canonical(validation) + b"\n"
    if (directory / "provenance.json").exists():
        files["build-provenance.json"] = directory / "provenance.json"
    return capture_files(files, known), provenance, validation


class DownloadedBuildResult(dict):
    """A successful download receipt, owned only by this publisher process."""

    def __init__(self, result, reference):
        super().__init__(result)
        self.release_reference = reference


def restore_build(api, descriptor, output, build_checkout=None):
    output = Path(output)
    with tempfile.TemporaryDirectory(prefix="karuyomi-release-") as folder:
        locator = extension_tag(descriptor["packageName"], descriptor["versionCode"])
        transfer = download_release(
            api, locator, folder, generation=descriptor["inputFingerprint"]
        )
        if not transfer:
            return False
        folder = Path(folder)
        provenance = read_json(folder / "provenance.json")
        previous = provenance.get("descriptor", {})
        if provenance.get("kind") != "source-aot" or any(
            previous.get(key) != descriptor.get(key)
            for key in [
                "packageName",
                "versionCode",
                "inputFingerprint",
                "sourceFingerprint",
                "hostFingerprint",
            ]
        ):
            raise ValueError("Existing release has different source provenance")
        staged = folder / "restored"
        staged.mkdir()
        manifest = read_json(folder / "manifest.json")
        references = [
            manifest["bundle"],
            *manifest.get("hostScripts", []),
            *manifest.get("resources", []),
        ]
        artifacts = {
            item["sha256"]: item
            for item in references
            if item.get("path")
            == "/api/extensions/artifacts/" + str(item.get("sha256"))
        }
        encoding = restore_artifacts(
            folder,
            staged / "artifacts",
            artifacts,
            manifest["bundle"]["sha256"],
            transfer=transfer,
        )
        for file in folder.iterdir():
            if file.name in {"manifest.json", "validation.json"}:
                shutil.copyfile(file, staged / file.name)
            elif file.name == "build-provenance.json":
                shutil.copyfile(file, staged / "provenance.json")
        _manifest, _artifacts, validation = verify_output(
            staged, descriptor, verify_hashes=False, build_checkout=build_checkout
        )
        if encoding == "gzip":
            transport = staged / "release-transport"
            transport.mkdir()
            for name in [
                "artifact-encodings.json",
                manifest["bundle"]["sha256"] + ".gz",
            ]:
                shutil.copyfile(folder / name, transport / name)
        output.mkdir(parents=True, exist_ok=True)
        shutil.copytree(staged, output, dirs_exist_ok=True)
        result = DownloadedBuildResult(
            {
                "status": "built",
                "restored": True,
                "descriptor": descriptor,
                "releaseDescriptor": previous,
                "releaseEncoding": encoding,
                "runtimeReady": validation["runtimeReady"],
            },
            transfer.reference,
        )
        write_json(output / "pipeline-result.json", result)
        return result


def build_one(descriptor, output, repository=None, build_checkout=None, processes=None):
    processes = processes or BuilderProcesses()
    processes.check()
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    result = {"schemaVersion": 1, "descriptor": descriptor, "status": "failed"}
    try:
        checkout = Path(build_checkout or ROOT).resolve()
        if build_checkout:
            validate_build_checkout(checkout, descriptor)
        if repository:
            downloaded = restore_build(
                GitHub(repository), descriptor, output, build_checkout
            )
            if downloaded:
                return downloaded
        saved = output / "pipeline-result.json"
        if saved.is_file():
            cached = read_json(saved)
            if (
                cached.get("descriptor") == descriptor
                and cached.get("status") == "built"
            ):
                verify_output(
                    output,
                    descriptor,
                    verify_hashes=False,
                    build_checkout=build_checkout,
                )
                # A disk checkpoint proves local build reuse, never that the
                # locator still exposes this generation in the current run.
                cached.pop("restored", None)
                cached.pop("releaseReference", None)
                write_json(saved, cached)
                return cached
        current, _inputs = (
            host_fingerprint()
            if not build_checkout
            else (descriptor["hostFingerprint"], None)
        )
        if current != descriptor["hostFingerprint"]:
            raise ValueError("Host inputs changed since planning")
        source = checkout / "vendor/extensions-source"
        if git(source, "rev-parse", "HEAD") != descriptor["upstreamCommit"]:
            raise ValueError("Source checkout differs from the planned commit")
        descriptor_path = output / "descriptor.json"
        write_json(descriptor_path, descriptor)
        with (output / "build.log").open("w") as log:
            build_environment = {
                key: value
                for key, value in os.environ.items()
                if key not in {"GH_TOKEN", "GITHUB_TOKEN"}
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
                env=build_environment,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        _manifest, _artifacts, validation = verify_output(
            output, descriptor, verify_hashes=False, build_checkout=build_checkout
        )
        write_json(output / "validation.json", validation)
        result.update(
            status="built",
            validationStatus="browser_verified"
            if validation["runtimeReady"]
            else "compiled_unverified",
        )
    except Exception as error:
        # Do not publish build logs, arbitrary upstream stderr or environment.
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
                    "message": str(failure.get("message", "Build failed"))[:500],
                }
        result["retryable"] = isinstance(error, RuntimeError) and str(error).startswith(
            "GitHub"
        )
    write_json(output / "pipeline-result.json", result)
    return result


def record_result(
    state, descriptor, result, directory, api=None, target=None, build_checkout=None
):
    key = descriptor["inputFingerprint"]
    attempts = state["attempts"].get(key, {}).get("attempts", 0) + 1
    record = {
        "descriptor": descriptor,
        "status": "failed",
        "attempts": attempts,
        "retryable": False,
    }
    if result.get("descriptor") != descriptor or result.get("status") != "built":
        record["failure"] = result.get(
            "failure",
            {
                "stage": "build",
                "code": "missing_result",
                "message": "No matching successful build output",
            },
        )
        record["retryable"] = result.get("retryable") is True
    elif api is None:
        record["status"] = "built"
    else:
        try:
            release_descriptor = result.get("releaseDescriptor", descriptor)
            if any(
                release_descriptor.get(key) != descriptor.get(key)
                for key in [
                    "packageName",
                    "versionCode",
                    "versionName",
                    "inputFingerprint",
                    "sourceFingerprint",
                    "hostFingerprint",
                    "buildId",
                ]
            ):
                raise ValueError("Restored release does not match planned identity")
            record["descriptor"] = release_descriptor
            if isinstance(result, DownloadedBuildResult):
                reference = result.release_reference
                if (
                    reference.get("tag")
                    != extension_tag(
                        descriptor["packageName"], descriptor["versionCode"]
                    )
                    or reference.get("snapshot", {}).get("generation")
                    != descriptor["inputFingerprint"]
                ):
                    raise ValueError("Restored locator does not match planned identity")
                _manifest, _artifacts, validation = verify_output(
                    directory,
                    release_descriptor,
                    verify_hashes=False,
                    build_checkout=build_checkout,
                )
                record["release"] = reference
                validation_status = (
                    "browser_verified"
                    if validation["runtimeReady"]
                    else "compiled_unverified"
                )
            else:
                files, provenance, validation = release_files(
                    directory,
                    release_descriptor,
                    result.get("releaseEncoding", "gzip"),
                    build_checkout,
                )
                record["release"] = publish_locator(
                    api,
                    extension_tag(descriptor["packageName"], descriptor["versionCode"]),
                    descriptor["inputFingerprint"],
                    files,
                    target,
                )
                validation_status = provenance["validationStatus"]
            record.update(
                status="published",
                validationStatus=validation_status,
                runtimeReady=validation["runtimeReady"],
            )
            state["active"][descriptor["packageName"]] = key
        except Exception as error:
            record.update(
                retryable=isinstance(error, RuntimeError),
                failure={
                    "stage": "publish",
                    "code": type(error).__name__,
                    "message": str(error)[:500],
                },
            )
    state["attempts"][key] = record
    return record


def cleanup_published_work(state_path, descriptor, record, build_checkout=None):
    """Remove only local disposable work after its published checkpoint exists."""
    if ci_environment() or record.get("status") != "published":
        return []
    build_id = descriptor.get("buildId")
    key = descriptor.get("inputFingerprint")
    if not isinstance(build_id, str) or not re.fullmatch(
        r"[A-Za-z0-9][A-Za-z0-9._-]{0,199}", build_id
    ):
        raise ValueError("Unsafe build ID for cache cleanup")
    persisted = load_state(state_path)
    if (
        persisted["attempts"].get(key) != record
        or persisted["active"].get(descriptor.get("packageName")) != key
        or record.get("descriptor", {}).get("buildId") != build_id
    ):
        raise ValueError("Published checkpoint must be saved before cache cleanup")
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


def checkpoint_bootstrap_result(
    state_path, state, descriptor, record, build_checkout=None
):
    write_json(state_path, state)
    try:
        cleanup_published_work(state_path, descriptor, record, build_checkout)
    except (OSError, ValueError, RuntimeError) as error:
        # Publication and its saved state stay successful. Keep remaining work
        # for inspection rather than turning a cleanup problem into a republish.
        print(
            "extensions: retained build cache for "
            + descriptor["buildId"]
            + ": "
            + str(error),
            file=sys.stderr,
            flush=True,
        )


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
        raise ValueError(
            "Initial baseline still has unattempted or unpublished packages"
        )
    state["bootstrap"] = {
        "complete": True,
        "upstreamCommit": catalog["upstreamCommit"],
        "catalogFingerprint": catalog["catalogFingerprint"],
        "published": sum(r["status"] == "published" for r in records),
        "failed": sum(r["status"] == "failed" for r in records),
        "discoveryFailed": len(catalog["discoveryFailures"]),
    }


def index_payload(state, catalog):
    current = {entry["packageName"]: entry for entry in catalog["entries"]}
    packages, failures, pending = [], list(catalog["discoveryFailures"]), 0
    for package, descriptor in sorted(current.items()):
        record = state["attempts"].get(descriptor["inputFingerprint"])
        if record is None or record["status"] == "built":
            pending += 1
        elif record["status"] == "failed":
            failures.append(
                {
                    "packageName": package,
                    "inputFingerprint": descriptor["inputFingerprint"],
                    "failure": record["failure"],
                }
            )
        active = state["attempts"].get(state["active"].get(package))
        if (
            active
            and active["status"] == "published"
            and (
                active["release"].get("tag")
                == extension_tag(
                    active["descriptor"]["packageName"],
                    active["descriptor"]["versionCode"],
                )
                and active["release"].get("snapshot", {}).get("generation")
                == active["descriptor"]["inputFingerprint"]
            )
        ):
            packages.append(
                {
                    "packageName": package,
                    "buildId": active["descriptor"]["buildId"],
                    "versionName": active["descriptor"]["versionName"],
                    "release": active["release"],
                    "runtimeReady": active["runtimeReady"],
                    "validationStatus": active["validationStatus"],
                    "inputFingerprint": active["descriptor"]["inputFingerprint"],
                    "stale": active["descriptor"]["inputFingerprint"]
                    != descriptor["inputFingerprint"],
                }
            )
    return {
        "schemaVersion": 1,
        "upstreamCommit": catalog["upstreamCommit"],
        "catalogFingerprint": catalog["catalogFingerprint"],
        "bootstrap": state["bootstrap"],
        "packages": packages,
        "failures": failures,
        "pending": pending,
    }


def publish_index(api, state, catalog, target):
    latest = api.find_release("extensions-index") or api.find_draft("extensions-index")
    actual = release_pointer(latest) if latest else None
    if state.get("remoteIndexSnapshot") != actual:
        raise ValueError(
            "Remote index advanced; pull and merge its checkpoint before publishing"
        )
    current = {
        entry["packageName"]: entry["inputFingerprint"] for entry in catalog["entries"]
    }
    state["active"] = {
        package: key for package, key in state["active"].items() if package in current
    }
    retained = set(current.values()) | set(state["active"].values())
    state["attempts"] = {
        key: value for key, value in state["attempts"].items() if key in retained
    }
    index = index_payload(state, catalog)
    index_bytes = canonical(index) + b"\n"
    snapshot = {
        key: value
        for key, value in state.items()
        if key not in {"remoteIndexTag", "remoteIndexSnapshot"}
    }
    state_bytes = canonical(snapshot) + b"\n"
    files = capture_files({"index.json": index_bytes, "state.json": state_bytes})
    generation = digest(canonical(files.metadata))
    tag = "extensions-index"
    reference = publish_locator(
        api,
        tag,
        generation,
        files,
        target,
        latest=True,
        expected=actual,
    )
    state["remoteIndexTag"] = tag
    state["remoteIndexSnapshot"] = reference["snapshot"]
    return tag


def pull_state(api, path):
    latest = api.find_release("extensions-index") or api.find_draft("extensions-index")
    if latest and latest.get("draft"):
        raise RuntimeError("GitHub index replacement is incomplete; retry later")
    if not latest:
        write_json(path, empty_state())
        return
    with tempfile.TemporaryDirectory(prefix="karuyomi-index-") as folder:
        transfer = download_release(api, latest["tag_name"], folder)
        if not transfer:
            raise ValueError("Index release is not published")
        state = load_state(Path(folder) / "state.json")
        state["remoteIndexTag"] = latest["tag_name"]
        if transfer.reference.get("snapshot"):
            state["remoteIndexSnapshot"] = transfer.reference["snapshot"]
        write_json(path, state)


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
            command.add_argument("--repository", default="Wybxc/karuyomi")
            command.add_argument("--jobs", type=int, default=1)
            command.add_argument("--finalize", action="store_true")
            command.add_argument(
                "--plan",
                type=Path,
                help="Resume an existing complete frozen plan without replanning",
            )
            command.add_argument(
                "--build-checkout",
                type=Path,
                help="Run the builder from this unchanged pinned checkout",
            )
    command = commands.add_parser("build")
    command.add_argument("--plan", type=Path, required=True)
    command.add_argument("--key", required=True)
    command.add_argument("--output", type=Path, required=True)
    command.add_argument("--repository")
    command = commands.add_parser("publish-plan")
    command.add_argument("--plan", type=Path, required=True)
    command.add_argument("--state", type=Path, required=True)
    command.add_argument("--results", type=Path, required=True)
    command.add_argument("--repository", default="Wybxc/karuyomi")
    command = commands.add_parser("pull-state")
    command.add_argument("--state", type=Path, required=True)
    command.add_argument("--repository", default="Wybxc/karuyomi")
    args = parser.parse_args()
    state_lock = None
    if hasattr(args, "state"):
        import fcntl

        args.state.parent.mkdir(parents=True, exist_ok=True)
        state_lock = args.state.with_suffix(".lock").open("a")
        processes.state_lock = state_lock
        try:
            fcntl.flock(state_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error("Another process owns this extension checkpoint")
    if args.command == "pull-state":
        processes.check()
        pull_state(GitHub(args.repository), args.state)
        return
    if args.command in {"plan", "bootstrap"}:
        if args.command == "bootstrap" and (args.ci or ci_environment()):
            parser.error("Initial full bootstrap is local-only")
        frozen = args.command == "bootstrap" and args.plan is not None
        if (
            args.command == "bootstrap"
            and not frozen
            and git(ROOT, "status", "--porcelain", "--", *HOST_PATHS)
        ):
            parser.error(
                "Commit the reviewed host/toolchain inputs before publishing the initial source baseline"
            )
        state = load_state(args.state)
        if frozen:
            if args.build_checkout is None:
                parser.error("--plan requires --build-checkout")
            catalog = read_json(args.plan)
            plan = resume_plan(catalog, state, args.limit, args.retry_failed)
            args.build_checkout = validate_build_checkout(
                args.build_checkout, plan["entries"][0]
            )
        else:
            if args.command == "bootstrap" and args.build_checkout is not None:
                parser.error("--build-checkout requires --plan")
            host, inputs = host_fingerprint()
            catalog = scan(args.source, host, inputs)
            plan = make_plan(
                catalog,
                state,
                args.limit,
                args.ci or ci_environment(),
                args.retry_failed,
            )
        write_json(args.output, plan)
        print(
            json.dumps(
                {
                    "discovered": len(catalog["entries"]),
                    "discoveryFailures": len(catalog["discoveryFailures"]),
                    "selected": len(plan["selected"]),
                    "remaining": plan["remainingCount"],
                }
            ),
            flush=True,
        )
        if args.command == "plan":
            return
        if not 1 <= args.jobs <= 4:
            parser.error("--jobs must be between 1 and 4")
        api = GitHub(args.repository)
        builds = args.output.parent / "builds"
        pool = ThreadPoolExecutor(max_workers=args.jobs)
        try:
            futures = {
                pool.submit(
                    build_one,
                    entry,
                    builds / entry["inputFingerprint"],
                    args.repository,
                    args.build_checkout,
                    processes,
                ): entry
                for entry in plan["selected"]
            }
            for future in as_completed(futures):
                processes.check()
                descriptor = futures[future]
                record = record_result(
                    state,
                    descriptor,
                    future.result(),
                    builds / descriptor["inputFingerprint"],
                    api,
                    plan["repositoryCommit"],
                    args.build_checkout,
                )
                checkpoint_bootstrap_result(
                    args.state, state, descriptor, record, args.build_checkout
                )
                print(descriptor["packageName"] + ": " + record["status"], flush=True)
        finally:
            if processes.cancelled.is_set():
                for future in futures:
                    future.cancel()
                processes.stop()
            pool.shutdown(wait=True, cancel_futures=True)
        processes.check()
        if args.finalize:
            finalize_baseline(state, catalog)
        publish_index(api, state, catalog, plan["repositoryCommit"])
        write_json(args.state, state)
    elif args.command == "build":
        plan = read_json(args.plan)
        descriptor = next(
            e for e in plan["selected"] if e["inputFingerprint"] == args.key
        )
        result = build_one(
            descriptor, args.output, args.repository, processes=processes
        )
        print(
            json.dumps(
                {"packageName": descriptor["packageName"], "status": result["status"]}
            )
        )
        if result["status"] != "built":
            sys.exit(1)
    elif args.command == "publish-plan":
        plan, state, api = (
            read_json(args.plan),
            load_state(args.state),
            GitHub(args.repository),
        )
        for descriptor in plan["selected"]:
            processes.check()
            matches = list(args.results.rglob("pipeline-result.json"))
            directory = next(
                (
                    p.parent
                    for p in matches
                    if read_json(p).get("descriptor") == descriptor
                ),
                None,
            )
            result = (
                read_json(directory / "pipeline-result.json")
                if directory
                else {
                    "status": "failed",
                    "retryable": True,
                    "failure": {
                        "stage": "build",
                        "code": "missing_result",
                        "message": "No matrix output was produced",
                    },
                }
            )
            record_result(
                state, descriptor, result, directory, api, plan["repositoryCommit"]
            )
            write_json(args.state, state)
        publish_index(api, state, plan, plan["repositoryCommit"])
        write_json(args.state, state)


def main():
    with BuilderProcesses() as processes:
        try:
            run_pipeline(processes)
            processes.check()
        except BuildCancelled:
            print(
                "extensions: cancelled; waiting for builder process groups",
                file=sys.stderr,
            )
            raise SystemExit(128 + (processes.signal_number or signal.SIGINT)) from None


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError) as error:
        print("extensions: " + str(error), file=sys.stderr)
        sys.exit(2)
