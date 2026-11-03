#!/usr/bin/env python3
"""Compile the independent JSO probe without editing frozen or product builds."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / 'runtime/teavm/.local'
source = ROOT / 'runtime/teavm/probes/bytes'
work = LOCAL / 'probes/bytes-work'
work.parent.mkdir(parents=True, exist_ok=True)
if work.exists():
    shutil.rmtree(work)
shutil.copytree(source, work)
maven = LOCAL / 'build-cache/apache-maven-3.9.11/bin/mvn'
if not maven.exists():
    raise SystemExit('First build a frozen package to bootstrap verified Maven 3.9.11')
started = time.monotonic()
subprocess.run([str(maven), '-q', '-f', str(work / 'pom.xml'),
                '-Dmaven.repo.local=' + str(LOCAL / 'build-cache/m2'), 'package'], check=True)
bundle = (work / 'dist/byte-probe.js').read_bytes()
destination = LOCAL / 'probes/byte-probe.js'
destination.write_bytes(bundle)
evidence = {'teavm': '0.16.0', 'backend': 'JAVASCRIPT', 'maven': '3.9.11',
            'seconds': time.monotonic() - started, 'bytes': len(bundle),
            'bundleSha256': hashlib.sha256(bundle).hexdigest(),
            'sourceFiles': {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest()
                            for path in sorted(source.rglob('*')) if path.is_file()}}
(LOCAL / 'probes/byte-build.json').write_text(json.dumps(evidence, indent=2) + '\n')
print(json.dumps(evidence, indent=2))
