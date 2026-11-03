#!/usr/bin/env python3
"""Compile a pinned, unchanged official extension JVM JAR to one TeaVM program.

Descriptor contract is produced by tools/extensions/catalog.py. Compilation does
not establish browser initialization, network compatibility, or image support.
"""

from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "runtime/teavm"
LOCAL = RUNTIME / ".local"
sys.path.insert(0, str(ROOT / "tools/extensions"))
import catalog


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def run(command, cwd, env, log):
    with log.open("w") as output:
        process = subprocess.run(
            [str(arg) for arg in command],
            cwd=cwd,
            env=env,
            stdout=output,
            stderr=subprocess.STDOUT,
        )
    if process.returncode:
        tail = "\n".join(log.read_text(errors="replace").splitlines()[-45:])
        raise RuntimeError(
            "Command exited "
            + str(process.returncode)
            + ": "
            + " ".join(map(str, command))
            + "\n"
            + tail
        )


def validate_descriptor(descriptor, upstream):
    required = [
        "packageName",
        "sourcePath",
        "versionName",
        "versionCode",
        "upstreamCommit",
        "sourceFingerprint",
        "hostFingerprint",
        "inputFingerprint",
        "buildId",
        "sourceInputs",
        "sharedInputs",
    ]
    if descriptor.get("schemaVersion") != 1 or any(
        name not in descriptor for name in required
    ):
        raise ValueError("Invalid descriptor schema/missing required provenance")
    if not re.fullmatch(r"src/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+", descriptor["sourcePath"]):
        raise ValueError("Invalid sourcePath")
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9._-]{0,159}", descriptor["buildId"]):
        raise ValueError("Invalid buildId")
    if catalog.git(upstream, "rev-parse", "HEAD") != descriptor["upstreamCommit"]:
        raise ValueError("Descriptor upstream commit differs from checkout")
    if catalog.git(upstream, "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Upstream tracked files are dirty")
    host, _ = catalog.host_fingerprint()
    if descriptor["hostFingerprint"] != host:
        raise ValueError("Descriptor hostFingerprint differs; regenerate the plan")
    tracked = set(
        catalog.git(upstream, "ls-tree", "-r", "--name-only", "HEAD").splitlines()
    )
    for field in ["sourceInputs", "sharedInputs"]:
        for name, expected in descriptor[field].items():
            if name.startswith("/") or ".." in Path(name).parts:
                raise ValueError("Invalid fingerprint path")
            if catalog.tree_hash(upstream, name, tracked) != expected:
                raise ValueError("Source input differs: " + name)
    required_source_paths = set(
        catalog.dependencies(upstream, descriptor["sourcePath"])
    )
    if set(descriptor["sourceInputs"]) != required_source_paths or set(
        descriptor["sharedInputs"]
    ) != set(catalog.SHARED_PATHS):
        raise ValueError("Incomplete descriptor fingerprint input set")
    source_hash = sha(
        catalog.canonical(
            {
                "modules": descriptor["sourceInputs"],
                "shared": descriptor["sharedInputs"],
            }
        )
    )
    if source_hash != descriptor["sourceFingerprint"]:
        raise ValueError("Descriptor source fingerprint mismatch")
    identity = {
        name: descriptor[name]
        for name in [
            "packageName",
            "versionCode",
            "sourceFingerprint",
            "hostFingerprint",
        ]
    }
    if sha(catalog.canonical(identity)) != descriptor["inputFingerprint"]:
        raise ValueError("Descriptor input fingerprint mismatch")
    slug = re.sub(
        r"[^a-zA-Z0-9._-]",
        "-",
        descriptor["packageName"].removeprefix("eu.kanade.tachiyomi.extension."),
    )[:80]
    if (
        descriptor["buildId"]
        != "ext-" + slug + "-" + descriptor["inputFingerprint"][:32]
    ):
        raise ValueError("Descriptor buildId does not bind the input fingerprint")


def put(output, file, content_type):
    data = file.read_bytes()
    digest = sha(data)
    target = output / "artifacts" / digest
    target.parent.mkdir(exist_ok=True)
    target.write_bytes(data)
    return {
        "path": "/api/extensions/artifacts/" + digest,
        "sha256": digest,
        "size": len(data),
        "contentType": content_type,
    }


def material_catalog():
    process = subprocess.run(
        ["node", str(ROOT / "packages/runtime-host/prepare-materials.ts"), "--print"],
        cwd=ROOT,
        capture_output=True,
        check=True,
    )
    if len(process.stdout) > 1024 * 1024:
        raise ValueError("Oversized shared material catalog")
    materials = json.loads(process.stdout)
    protocol = json.loads((ROOT / "packages/contracts/protocol.json").read_text())
    if (
        not isinstance(materials, dict)
        or type(materials.get("schemaVersion")) is not int
        or materials["schemaVersion"] != 1
        or any(
            type(materials.get(key)) is not type(value) or materials.get(key) != value
            for key, value in protocol.items()
        )
    ):
        raise ValueError("Shared material protocol ABI mismatch")
    if not isinstance(materials.get("materialVersion"), str) or not re.fullmatch(
        "[a-f0-9]{64}", materials["materialVersion"]
    ):
        raise ValueError("Invalid shared material version")
    for group in ["hostScripts", "resources"]:
        values = materials.get(group)
        if not isinstance(values, list) or not 1 <= len(values) <= 16:
            raise ValueError("Invalid shared material list: " + group)
        for item in values:
            if (
                not isinstance(item, dict)
                or not isinstance(item.get("sha256"), str)
                or not re.fullmatch("[a-f0-9]{64}", item["sha256"])
            ):
                raise ValueError("Invalid shared material hash")
            if (
                item.get("path") != "/runtime/materials/" + item["sha256"]
                or type(item.get("size")) is not int
                or not 0 < item["size"] <= 64 * 1024 * 1024
            ):
                raise ValueError("Invalid shared material reference")
            if (
                not isinstance(item.get("logicalName"), str)
                or not 1 <= len(item["logicalName"]) <= 100
            ):
                raise ValueError("Invalid shared material logical name")
            expected_type = (
                "application/javascript"
                if group == "hostScripts"
                else "application/wasm"
            )
            if item.get("contentType") != expected_type:
                raise ValueError("Invalid shared material MIME")
    return materials, sha(process.stdout)


def build(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output / "manifest.json").exists():
        raise ValueError(
            "Output already has an immutable manifest; choose a fresh directory"
        )
    started = time.monotonic()
    descriptor = {}
    result = {
        "schemaVersion": 1,
        "status": "failed",
        "packageName": descriptor.get("packageName"),
        "buildId": descriptor.get("buildId"),
        "stage": "upstream",
        "artifacts": [],
    }
    stage = "upstream"
    logs = output / "logs"
    logs.mkdir(exist_ok=True)
    active_log = None
    try:
        descriptor = json.loads(args.descriptor.read_text())
        if not isinstance(descriptor, dict):
            raise ValueError("Descriptor must be a JSON object")
        result.update(
            packageName=descriptor.get("packageName"), buildId=descriptor.get("buildId")
        )
        upstream = args.upstream.resolve()
        validate_descriptor(descriptor, upstream)
        materials, materials_hash = material_catalog()
        runtime = load_module(
            "prepare_runtime", ROOT / "scripts/prepare-runtime.py"
        ).prepare(args.seed, args.android)
        java_home = Path(runtime["javaHome"])
        java_version = subprocess.run(
            [str(java_home / "bin/java"), "-version"],
            text=True,
            capture_output=True,
            check=True,
        ).stderr.strip()
        match = re.search(r'version "(\d+)', java_version)
        if not match or int(match.group(1)) != 25:
            raise ValueError(
                "JDK 25 required; select JAVA_HOME/PATH (reference 25.0.4)"
            )
        env = dict(os.environ)
        env["JAVA_HOME"] = str(java_home)
        env["PATH"] = str(java_home / "bin") + os.pathsep + env.get("PATH", "")
        env["GRADLE_USER_HOME"] = str(LOCAL / "gradle")
        env["ANDROID_HOME"] = str(args.android_sdk.resolve())
        env["ANDROID_SDK_ROOT"] = env["ANDROID_HOME"]
        env["ANDROID_USER_HOME"] = str(LOCAL / "android-home")
        module = ":" + descriptor["sourcePath"].replace("/", ":")
        # Lock wrapper bytes before execution; upstream owns all extension/KSP/R8 logic.
        wrapper = (upstream / "gradle/wrapper/gradle-wrapper.properties").read_text()
        if "gradle-9.8.2-bin.zip" not in wrapper:
            raise ValueError(
                "Unsupported upstream Gradle wrapper; update the toolchain lock explicitly"
            )
        launcher = LOCAL / "gradle-launcher" / descriptor["buildId"]
        launcher.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(
            upstream / "gradle/wrapper/gradle-wrapper.jar",
            launcher / "gradle-wrapper.jar",
        )
        locked_wrapper = (
            wrapper
            + "\ndistributionSha256Sum="
            + json.loads((RUNTIME / "toolchain-lock.json").read_text())["gradle"][
                "sha256"
            ]
            + "\n"
        )
        (launcher / "gradle-wrapper.properties").write_text(locked_wrapper)
        active_log = logs / "upstream.log"
        print(
            json.dumps({"stage": stage, "module": module, "logPath": str(active_log)}),
            flush=True,
        )
        run(
            [
                "java",
                "-classpath",
                launcher / "gradle-wrapper.jar",
                "org.gradle.wrapper.GradleWrapperMain",
                "-p",
                upstream,
                module + ":assembleRelease",
                "--no-configuration-cache",
                "--no-watch-fs",
                "--max-workers=" + str(args.workers),
                "-Dorg.gradle.daemon=false",
                "-Dorg.gradle.parallel=false",
            ],
            upstream,
            env,
            active_log,
        )
        if catalog.git(upstream, "status", "--porcelain", "--untracked-files=no"):
            raise ValueError(
                "Official Gradle changed tracked inputs; refusing changed business source"
            )
        metadata_path = (
            upstream / descriptor["sourcePath"] / "build/keiyoushi-source-info.json"
        )
        metadata = json.loads(metadata_path.read_text())
        for expected, actual in [
            ("packageName", "packageName"),
            ("versionName", "versionName"),
            ("versionCode", "versionCode"),
        ]:
            if descriptor[expected] != metadata[actual]:
                raise ValueError(
                    "Official metadata disagrees with descriptor: " + expected
                )
        jars = sorted(
            (upstream / descriptor["sourcePath"] / "build/outputs/jar/release").glob(
                "*.jar"
            )
        )
        if len(jars) != 1:
            raise ValueError("Expected exactly one official release JVM JAR")
        original = jars[0]
        original_hash = sha(original.read_bytes())
        stage = "host"
        if catalog.host_fingerprint()[0] != descriptor["hostFingerprint"]:
            raise ValueError(
                "Host changed during upstream compilation; regenerate descriptor and retry"
            )
        work = LOCAL / "extension-work" / descriptor["buildId"]
        if work.exists():
            shutil.rmtree(work)
        work.mkdir(parents=True)
        shutil.copytree(RUNTIME / "java", work / "java")
        sys.path.insert(0, str(ROOT / "tools/teavm"))
        import upstream_sources

        generated_adapters = upstream_sources.prepare_sources(
            work / "java/src/main/java"
        )
        (work / "scripts").mkdir()
        for name in ["build.py", "PatchLibraries.java"]:
            shutil.copyfile(ROOT / "tools/teavm" / name, work / "scripts" / name)
        shutil.copytree(
            Path(runtime["materials"]) / "public/runtime", work / "public/runtime"
        )
        (work / "public/extensions").mkdir()
        shutil.copyfile(original, work / "public/extensions" / original.name)
        key = descriptor["packageName"].rsplit(".", 1)[1]
        entry = {
            "key": key,
            "packageName": descriptor["packageName"],
            "jar": original.name,
            "convertedSha256": original_hash,
            "expectedSources": [
                {"id": str(item["id"]), "name": item["name"], "lang": item["lang"]}
                for item in metadata["sources"]
            ],
        }
        save(work / "inputs.json", [entry])
        # Per-package cache protects upstream's mutable classpath.txt/tools from
        # parallel builds. Maven's repository can safely be shared by Maven itself.
        package_cache = LOCAL / "extension-cache" / descriptor["buildId"]
        package_cache.mkdir(parents=True, exist_ok=True)
        shared_m2 = LOCAL / "build-cache/m2"
        shared_m2.mkdir(parents=True, exist_ok=True)
        if not (package_cache / "m2").exists():
            (package_cache / "m2").symlink_to(shared_m2, target_is_directory=True)
        env["TEAVM_BUILD_CACHE"] = str(package_cache)
        env["MAVEN"] = runtime["maven"]
        env.pop("TEAVM_PROBE", None)
        env.pop("TEAVM_DEBUG", None)
        stage = "aot"
        active_log = logs / "aot.log"
        print(
            json.dumps(
                {"stage": stage, "jarSha256": original_hash, "logPath": str(active_log)}
            ),
            flush=True,
        )
        run([sys.executable, "scripts/build.py", key], work, env, active_log)
        if (
            sha(original.read_bytes()) != original_hash
            or sha((work / "public/extensions" / original.name).read_bytes())
            != original_hash
        ):
            raise ValueError("Build changed the official extension input JAR")
        if catalog.host_fingerprint()[0] != descriptor["hostFingerprint"]:
            raise ValueError(
                "Host changed during AOT compilation; regenerate descriptor and retry"
            )
        bundle = put(output, work / "public/teavm" / key / "app.js", "text/javascript")
        manifest = {
            "buildId": descriptor["buildId"],
            "repoId": "keiyoushi",
            "packageName": descriptor["packageName"],
            "version": metadata["versionName"],
            "sourceIds": sorted(str(item["id"]) for item in metadata["sources"]),
            **{
                key: materials[key]
                for key in ["protocolVersion", "hostAbi", "runtimeBaseline"]
            },
            "bridgeVersion": 1,
            "storageSchema": "release9-v1",
            "bundle": bundle,
            "hostScripts": materials["hostScripts"],
            "resources": materials["resources"],
        }
        record = json.loads((work / "results" / ("build-" + key + ".json")).read_text())
        provenance = {
            "schemaVersion": 1,
            "descriptor": descriptor,
            "upstream": {
                "commit": descriptor["upstreamCommit"],
                "metadata": metadata,
                "jar": original.name,
                "jarSha256": original_hash,
            },
            "toolchain": {
                "androidHome": env["ANDROID_HOME"],
                "java": java_version,
                "maven": "3.9.11",
                "teavm": "0.16.0",
                "runtime": runtime,
            },
            "sharedMaterials": {
                "materialVersion": materials["materialVersion"],
                "catalogSha256": materials_hash,
                "protocolABI": {
                    key: materials[key]
                    for key in ["protocolVersion", "hostAbi", "runtimeBaseline"]
                },
            },
            "aot": record,
            "generatedUpstreamAdapters": [
                {
                    "path": path.relative_to(work).as_posix(),
                    "sha256": sha(path.read_bytes()),
                }
                for path in generated_adapters
            ],
            "manifestSha256": sha(
                (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode()
            ),
            "compatibility": {
                "browserInitialized": False,
                "onlineMetadata": False,
                "productImages": False,
            },
            "boundary": "Compilation and immutable input/hash provenance only. Verify actual Worker initialization separately.",
        }
        save(output / "provenance.json", provenance)
        save(output / "manifest.json", manifest)
        artifacts = [manifest["bundle"]]
        result.update(
            status="built",
            stage="complete",
            manifestPath="manifest.json",
            artifacts=[
                {
                    "sha256": item["sha256"],
                    "size": item["size"],
                    "path": "artifacts/" + item["sha256"],
                }
                for item in artifacts
            ],
            seconds=round(time.monotonic() - started, 3),
            provenancePath="provenance.json",
        )
        save(output / "build-result.json", result)
        print(json.dumps(result, indent=2))
        return 0
    except Exception as error:
        (output / "manifest.json").unlink(missing_ok=True)
        result.update(
            stage=stage,
            seconds=round(time.monotonic() - started, 3),
            failure={
                "stage": stage,
                "code": type(error).__name__,
                "message": str(error),
                "logPath": str(active_log.relative_to(output)) if active_log else None,
            },
        )
        save(output / "build-result.json", result)
        print(json.dumps(result, indent=2), file=sys.stderr)
        return 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--descriptor", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--upstream", type=Path, default=ROOT / "vendor/extensions-source"
    )
    parser.add_argument("--seed", type=Path)
    parser.add_argument(
        "--android",
        action="store_true",
        help="Install locked SDK platform/build-tools before building",
    )
    parser.add_argument("--android-sdk", type=Path, default=LOCAL / "android-sdk")
    parser.add_argument("--workers", type=int, default=3)
    args = parser.parse_args()
    sys.exit(build(args))
