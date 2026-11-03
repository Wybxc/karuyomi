#!/usr/bin/env python3
"""Build/run the isolated iOS Blob download probe and remove its test device.

Only serves checked-in development fixtures on host loopback HTTP/HTTPS. This is not
the production HTTPS/Access or physical-device acceptance test.
"""
import argparse
import hashlib
import http.server
import json
import pathlib
import ssl
import subprocess
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent
BUNDLE = "dev.karuyomi.resourceprobe"


def run(*args, capture=False, log=None):
    result = subprocess.run(
        args,
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else log,
        stderr=subprocess.STDOUT if log else None,
    )
    return result.stdout.strip() if capture else None


def expected_digest(length):
    hasher = hashlib.sha256()
    # Independent reference implementation; no whole-body conversion or JSON.
    for start in range(0, length, 65536):
        hasher.update(bytes((index * 31 + (index >> 8)) & 255
                            for index in range(start, min(start + 65536, length))))
    return hasher.hexdigest()


def validate(report):
    assert report.get("complete") is True, report
    assert report.get("passed") is True, report
    assert report.get("environment") == "simulator", report
    assert report.get("productionHTTPSVerified") is False, report
    assert report.get("physicalDeviceVerified") is False, report
    assert report.get("memoryPeakMeasured") is False, report
    assert report.get("remainingFiles") == [], report
    results = report.get("results", [])
    assert len(results) == 5, results
    for item in results:
        assert item.get("passed") is True, item
        assert item.get("fileReleased") is True, item
        assert item.get("blobReleased") is True, item
        if item.get("status") == "downloaded":
            assert item["sha256"] == item["workerSha256"], item
            assert item["workerBufferDetached"] is True, item
        if item["id"].startswith("binary-"):
            assert item["sha256"] == expected_digest(item["byteLength"]), item
            assert item["workerBufferDetached"] is True, item
        if item["id"] == "processed-png":
            assert (item["imageWidth"], item["imageHeight"]) == (128, 256), item
        if item["id"].startswith("cancel-"):
            assert item["status"] == "cancelled", item
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", default="com.apple.CoreSimulator.SimRuntime.iOS-26-4")
    parser.add_argument("--device-type", default="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro")
    parser.add_argument("--device", help="Use an existing dedicated test UDID (not removed)")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--https", action="store_true",
                        help="Trust a temporary localhost certificate in this test simulator only")
    args = parser.parse_args()
    build = ROOT / ".build"
    build.mkdir(exist_ok=True)
    if not args.skip_build:
        print("Generating and building the isolated iOS probe", flush=True)
        run("xcodegen", "generate", "--spec", "project.yml", "--project", ".build")
        with (build / "xcodebuild.log").open("w") as log:
            run("xcodebuild", "-project", ".build/ResourceBridgeProbe.xcodeproj",
                "-scheme", "ResourceBridgeProbe", "-sdk", "iphonesimulator",
                "-configuration", "Debug", "-derivedDataPath", ".build/DerivedData",
                "CODE_SIGNING_ALLOWED=NO", "build", log=log)
    app = build / "DerivedData/Build/Products/Debug-iphonesimulator/ResourceBridgeProbe.app"
    assert app.exists(), app
    device = args.device
    server = None
    try:
        if not device:
            device = run("xcrun", "simctl", "create", "Karuyomi Resource Probe",
                         args.device_type, args.runtime, capture=True)
            print(f"Created dedicated test simulator {device}", flush=True)
        state = json.loads(run("xcrun", "simctl", "list", "devices", "-j", capture=True))
        existing = next(d for devices in state["devices"].values()
                        for d in devices if d["udid"] == device)
        runtime = next(key for key, devices in state["devices"].items()
                       if any(d["udid"] == device for d in devices))
        if existing["state"] != "Booted":
            run("xcrun", "simctl", "boot", device)
        print("Waiting for test simulator boot", flush=True)
        run("xcrun", "simctl", "bootstatus", device, "-b")
        handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
            *a, directory=str(ROOT / "web"), **kw)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        if args.https:
            certificate = build / "localhost.crt"
            private_key = build / "localhost.key"
            config = build / "openssl.cnf"
            config.write_text("""[req]
distinguished_name = dn
x509_extensions = extensions
prompt = no
[dn]
CN = Karuyomi local probe
[extensions]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, keyEncipherment, keyCertSign
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost, IP:127.0.0.1
""")
            with (build / "certificate.log").open("w") as log:
                run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-days", "1", "-config", str(config), "-keyout", str(private_key),
                    "-out", str(certificate), log=log)
            run("xcrun", "simctl", "keychain", device, "add-root-cert", str(certificate))
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(certificate, private_key)
            server.socket = context.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        scheme = "https" if args.https else "http"
        url = f"{scheme}://127.0.0.1:{server.server_port}/index.html"
        print(f"Serving development fixtures at {url}", flush=True)
        run("xcrun", "simctl", "install", device, str(app))
        container = pathlib.Path(run("xcrun", "simctl", "get_app_container", device, BUNDLE, "data", capture=True))
        report_file = container / "Documents/resource-probe-report.json"
        report_file.unlink(missing_ok=True)
        run("xcrun", "simctl", "launch", "--terminate-running-process", device, BUNDLE, "-probeURL", url)
        deadline = time.monotonic() + 120
        report = None
        while time.monotonic() < deadline:
            if report_file.exists():
                report = json.loads(report_file.read_text())
                if report.get("complete"):
                    break
            time.sleep(0.5)
        if not report or not report.get("complete"):
            raise RuntimeError("Probe did not produce a terminal report")
        results = ROOT / "results"
        results.mkdir(exist_ok=True)
        # Preserve both successful and failed native evidence before validation.
        report["xcodeVersion"] = run("xcodebuild", "-version", capture=True)
        report["runtimeIdentifier"] = runtime
        report["deviceTypeIdentifier"] = existing["deviceTypeIdentifier"]
        report["sdkVersion"] = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version", capture=True)
        report["localHTTPSVerified"] = args.https and report.get("passed") is True
        report["transportSecurity"] = "local-trusted-certificate" if args.https else "loopback-http"
        report["sourceSha256"] = {
            str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(ROOT.rglob("*"))
            if p.is_file() and (p.parent.name in {"Sources", "web"}
                                or p.parent == ROOT and p.name in {"project.yml", "Info.plist", "run-simulator.py"})
        }
        (results / "last-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        validate(report)
        report["independentBinaryDigestVerified"] = True
        (results / "last-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(json.dumps(report, indent=2, sort_keys=True), flush=True)
    finally:
        if server:
            server.shutdown()
            server.server_close()
        if device and not args.device:
            subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
            subprocess.run(["xcrun", "simctl", "delete", device], check=False)
            print("Removed dedicated probe simulator", flush=True)


if __name__ == "__main__":
    main()
