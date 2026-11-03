#!/usr/bin/env python3
"""Build baseline and fixed zstd callback oracles from isolated package copies."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / 'runtime/teavm'
LOCAL = RUNTIME / '.local'
package = LOCAL / 'work/mangadraft-product'
if not package.exists():
    raise SystemExit('Build mangadraft first')
records = []
for mode in ['baseline', 'fixed']:
    work = LOCAL / ('probes/bridge-' + mode)
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(package, work, ignore=shutil.ignore_patterns('target', 'results'))
    shutil.rmtree(work / 'public/teavm', ignore_errors=True)
    origin = RUNTIME / ('upstream' if mode == 'baseline' else '') / 'java/src/main/java/prototype/Bridge.java'
    shutil.copyfile(origin, work / 'java/src/main/java/prototype/Bridge.java')
    shutil.copyfile(RUNTIME / 'probes/bridge/ProbeHost.java', work / 'java/src/main/java/prototype/ProbeHost.java')
    env = {**os.environ, 'TEAVM_PROBE': '1', 'TEAVM_BUILD_CACHE': str(LOCAL / 'build-cache'),
           'MAVEN': str(LOCAL / 'build-cache/apache-maven-3.9.11/bin/mvn')}
    subprocess.run(['python3', 'scripts/build.py', 'mangadraft'], cwd=work, env=env, check=True)
    bundle = work / 'public/teavm/compat-probe/app.js'
    shutil.copyfile(bundle, LOCAL / ('probes/bridge-' + mode + '.js'))
    record = json.loads((work / 'results/build-compat-probe.json').read_text())
    record.update({'mode': mode, 'bridgeSha256': hashlib.sha256(origin.read_bytes()).hexdigest()})
    records.append(record)
(LOCAL / 'probes/bridge-build.json').write_text(json.dumps(records, indent=2) + '\n')
print(json.dumps(records, indent=2))
