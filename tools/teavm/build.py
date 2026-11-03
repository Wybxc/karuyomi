#!/usr/bin/env python3
"""Compile explicit, unchanged extension inputs inside an isolated build directory.

The orchestrator copies this file to work/scripts/build.py, prepares project and
upstream patch sources in work/java, and supplies verified materials/inputs.json.
Generated type/resource registries and adapted dependency JARs stay in that work
copy. The extension JAR is never rewritten.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tarfile
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path(os.environ.get('TEAVM_BUILD_CACHE', str(ROOT / '.build')))
M2 = CACHE / 'm2'


def run(args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def maven():
    if os.environ.get('MAVEN'):
        return os.environ['MAVEN']
    home = CACHE / 'apache-maven-3.9.11'
    if not home.exists():
        url = 'https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.11/apache-maven-3.9.11-bin.tar.gz'
        with urllib.request.urlopen(url) as response:
            data = response.read()
        with urllib.request.urlopen(url + '.sha512') as response:
            checksum = response.read().decode().split()[0]
        if hashlib.sha512(data).hexdigest() != checksum:
            raise ValueError('Maven archive checksum mismatch')
        archive = CACHE / 'maven.tar.gz'
        archive.write_bytes(data)
        with tarfile.open(archive) as tar:
            tar.extractall(CACHE, filter='data')
    return home / 'bin/mvn'


def generate_registries(source, jar):
    types = set()
    for dependency in [*sorted(Path('public/runtime').glob('*.jar')), jar]:
        with zipfile.ZipFile(dependency) as archive:
            for name in archive.namelist():
                if name.endswith('.class'):
                    match = re.search(rb'Luy/kohesive/injekt/api/FullTypeReference<L([^;]+);>;', archive.read(name))
                    if match:
                        types.add((name[:-6].replace('/', '.'), match[1].decode().replace('/', '.')))
    cases = ''.join('case ' + json.dumps(name) + ':return ' + target.replace('$', '.') + '.class;' for name, target in sorted(types))
    (source / 'prototype/TypeMap.java').write_text(
        'package prototype;public class TypeMap{public static java.lang.reflect.Type resolve(String n){switch(n){'
        + cases + 'default:throw new IllegalArgumentException("Unregistered AOT type "+n);}}}')
    with zipfile.ZipFile(jar) as archive:
        resources = [name for name in archive.namelist() if name.startswith('assets/') and not name.endswith('/')]
        uses_icu = any(b'android/icu/' in archive.read(name) or b'com/ibm/icu/' in archive.read(name)
                       for name in archive.namelist() if name.endswith('.class'))
    if uses_icu:
        with zipfile.ZipFile('public/runtime/icu4j-79.1.jar') as archive:
            resources.extend(name for name in archive.namelist()
                             if name.startswith('com/ibm/icu/') and not name.endswith(('.class', '/')))
    (source / 'prototype/ResourceConfig.java').write_text(
        'package prototype;public class ResourceConfig implements org.teavm.extension.spi.resources.ResourcesPolicy{'
        'public String[] supplyResources(java.util.Collection<? extends String> names){return new String[]{'
        + ','.join(json.dumps(name) for name in sorted(set(resources))) + '};}}')


def prepare_libraries(source):
    classes = [str(path.relative_to(source))[:-5] for path in source.rglob('*.java')]
    Path('java/libs').mkdir(exist_ok=True)
    for dependency in sorted(Path('public/runtime').glob('*.jar')):
        with zipfile.ZipFile(dependency) as archive, zipfile.ZipFile(Path('java/libs') / dependency.name, 'w', zipfile.ZIP_DEFLATED) as output:
            for name in archive.namelist():
                if not any(name == item + '.class' or name.startswith(item + '$') for item in classes):
                    output.writestr(name, archive.read(name))


def compile_extension(entry, mvn):
    plugin = entry['key']
    started = time.monotonic()
    jar = Path('public/extensions') / entry['jar']
    expected = entry['convertedSha256']
    if hashlib.sha256(jar.read_bytes()).hexdigest() != expected:
        raise ValueError('Extension input checksum mismatch: ' + plugin)
    source = Path('java/src/main/java')
    generate_registries(source, jar)
    prepare_libraries(source)
    props = ['-Dextension=' + entry['jar'], '-Dplugin=' + plugin]
    if os.environ.get('TEAVM_DEBUG'):
        props += ['-Dminify=false', '-Ddebug=true']
    cpfile = CACHE / 'classpath.txt'
    mvn(*props, 'dependency:build-classpath', '-Dmdep.outputFile=' + str(cpfile))
    cp = cpfile.read_text().strip()
    tools = CACHE / 'tools'
    tools.mkdir(exist_ok=True)
    run(['javac', '-cp', cp, '-d', tools, 'scripts/PatchLibraries.java'])
    run(['java', '-cp', str(tools) + os.pathsep + cp, 'PatchLibraries', *sorted(Path('java/libs').glob('*.jar'))])
    Path('java/target/classes').mkdir(parents=True, exist_ok=True)
    run(['javac', '-cp', cp, '-d', 'java/target/classes',
         *[source / ('prototype/' + name + '.java') for name in ['Bridge', 'Callbacks', 'JsonValues']]])
    cp = 'java/target/classes' + os.pathsep + cp
    run(['javac', '--patch-module', 'java.base=java/compat', '--add-reads', 'java.base=ALL-UNNAMED',
         '-cp', cp, '-d', 'java/target/classes', *sorted(Path('java/compat').rglob('*.java'))])
    mvn(*props, 'package')
    if hashlib.sha256(jar.read_bytes()).hexdigest() != expected:
        raise ValueError('Build changed extension input: ' + plugin)
    output = Path('public/teavm') / plugin / 'app.js'
    if not os.environ.get('TEAVM_DEBUG'):
        output.with_suffix('.js.map').unlink(missing_ok=True)
    result = {'plugin': plugin, 'bundleKey': plugin, 'entryPoint': 'prototype.TeaHost',
              'outputSha256': hashlib.sha256(output.read_bytes()).hexdigest(),
              'debug': bool(os.environ.get('TEAVM_DEBUG')), 'extensionSha256': expected,
              'seconds': time.monotonic() - started, 'bytes': output.stat().st_size, 'teavm': '0.16.0'}
    Path('results').mkdir(exist_ok=True)
    Path('results/build-' + plugin + '.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packages', nargs='+', help='Explicit package keys from work/inputs.json')
    args = parser.parse_args()
    os.chdir(ROOT)
    CACHE.mkdir(parents=True, exist_ok=True)
    executable = maven()
    entries = json.loads(Path('inputs.json').read_text())

    def mvn(*options):
        run([executable, '-q', '-f', 'java/pom.xml', '-Dmaven.repo.local=' + str(M2), *options])

    for key in args.packages:
        matches = [entry for entry in entries if entry['key'] == key]
        if len(matches) != 1:
            parser.error('Expected exactly one input for package key: ' + key)
        compile_extension(matches[0], mvn)


if __name__ == '__main__':
    main()
