#!/usr/bin/env python3
"""Keep small, path/identity-free summaries of successful local browser probes."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / 'runtime/teavm'
LOCAL = RUNTIME / '.local'
manifest_path = Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text())
build = json.loads(manifest_path.with_suffix('.evidence.json').read_text())
browser = json.loads((LOCAL / 'probes/browser-init.json').read_text())
if browser['buildId'] != manifest['buildId']:
    raise ValueError('Browser did not test this product build')
events = {entry['event']: entry['value'] for entry in browser['events']}
if ('session' not in events or events.get('referenceRejection', {}).get('code') != 'source_error'
        or 'Explicit reference is required' not in events['referenceRejection']['message']):
    raise ValueError('Product initialization/reference probe did not pass')
session = events['session']
destination = RUNTIME / 'verification'
destination.mkdir(exist_ok=True)
product = {
    'schemaVersion': 1, 'date': '2026-11-03', 'manifest': manifest,
    'toolchain': build['toolchain'], 'originalJarSha256': build['originalJarSha256'],
    'frozenSourceFingerprint': build['frozenSourceFingerprint'],
    'workingSourceSha256': build['workingSourceSha256'], 'build': build['build'],
    'browser': {'userAgent': browser['userAgent'], 'initialSourceReady': events['hello']['sourceReady'],
                'sources': session['sources'], 'capabilities': session['capabilities'],
                'missingChapterReference': {'code': events['referenceRejection']['code'],
                                            'message': events['referenceRejection']['message'].split('\n')[0]}},
    'scope': 'Loopback browser verifies artifact hashes, actual IndexedDB-backed hostInit/hostLoad and Java explicit-reference rejection. No Access, live Source operations, image or native-platform equivalence claim.',
}
(destination / 'mangadraft-p0a.json').write_text(json.dumps(product, indent=2) + '\n')
baselines = sorted((LOCAL / 'baselines').glob('release9-mangadraft-baseline-*.evidence.json'))
if baselines:
    baseline = json.loads(baselines[-1].read_text())
    summary = {key: baseline[key] for key in ['schemaVersion', 'mode', 'package', 'originalJarSha256',
               'frozenSourceFingerprint', 'workingSourceSha256', 'toolchain', 'build', 'baselineBundle']}
    summary['scope'] = 'Unchanged frozen release9 build only. This host lacks the product RPC ABI and is not an installable product manifest.'
    (destination / 'mangadraft-baseline.json').write_text(json.dumps(summary, indent=2) + '\n')
for name, stem, scope in [
    ('byte-browser.json', 'byte-boundary', 'Independent TeaVM JSO explicit bounded copy/fiber/cancel oracle. Supplier is simulated; not the v2 HTTP/Okio/image bridge, not mobile or total-heap evidence.'),
    ('bridge-browser.json', 'zstd-callback', 'Actual compiled original/product Java Bridge.zstd comparison. Malformed WASM decode is real; rejected host Promise is an explicit injected fault, not a remote Source response.'),
]:
    report = json.loads((LOCAL / 'probes' / name).read_text())
    if not report.get('passed'):
        raise ValueError('Probe failed: ' + name)
    report = {'schemaVersion': 1, 'date': '2026-11-03', **report, 'scope': scope}
    report['harnessFiles'] = {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((ROOT / 'tools/teavm').glob('*.js*'))
    }
    if stem == 'zstd-callback':
        report['probeEntrySha256'] = hashlib.sha256((RUNTIME / 'probes/bridge/ProbeHost.java').read_bytes()).hexdigest()
    (destination / (stem + '.json')).write_text(json.dumps(report, indent=2) + '\n')
subprocess.run(['pnpm', 'exec', 'prettier', '--write', str(destination)], cwd=ROOT, check=True)
print('Recorded product, byte-boundary and zstd-callback evidence')
