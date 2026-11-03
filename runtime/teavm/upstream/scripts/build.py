#!/usr/bin/env python3
"""Compile each unchanged APK-converted extension as a separate TeaVM program."""
from pathlib import Path
import os,sys,json,re,zipfile,subprocess,shutil,urllib.request,tarfile,hashlib,time
ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT)
CACHE=Path(os.environ.get('TEAVM_BUILD_CACHE',str(ROOT/'.build')));CACHE.mkdir(parents=True,exist_ok=True)
M2=CACHE/'m2'
def run(args,**kw):subprocess.run([str(a) for a in args],check=True,**kw)
def maven():
 if os.environ.get('MAVEN'):return os.environ['MAVEN']
 if shutil.which('mvn'):return shutil.which('mvn')
 home=CACHE/'apache-maven-3.9.11'
 if not home.exists():
  url='https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.11/apache-maven-3.9.11-bin.tar.gz'
  data=urllib.request.urlopen(url).read();checksum=urllib.request.urlopen(url+'.sha512').read().decode().split()[0]
  assert hashlib.sha512(data).hexdigest()==checksum
  archive=CACHE/'maven.tar.gz';archive.write_bytes(data)
  with tarfile.open(archive) as tar:tar.extractall(CACHE,filter='data')
 return home/'bin/mvn'
MVN=maven()
def mvn(*args):run([MVN,'-q','-f','java/pom.xml','-Dmaven.repo.local='+str(M2),*args])
inputs=json.loads(Path('inputs.json').read_text());chosen=sys.argv[1:] or ['webtoons','comicfury','mangadex']
for plugin in chosen:
 entry=next(e for e in inputs if e['packageName'].endswith('.'+plugin))
 started=time.monotonic();jar=Path('public/extensions')/entry['jar']
 assert hashlib.sha256(jar.read_bytes()).hexdigest()==entry['convertedSha256']
 # Exact original input is the extension dependency. Only host/dependency JARs are adapted.
 source=Path('java/src/main/java');classes=[str(f.relative_to(source))[:-5] for f in source.rglob('*.java')]
 Path('java/libs').mkdir(exist_ok=True)
 for f in Path('public/runtime').glob('*.jar'):
  with zipfile.ZipFile(f) as z,zipfile.ZipFile(Path('java/libs')/f.name,'w',zipfile.ZIP_DEFLATED) as out:
   for name in z.namelist():
    if not any(name==c+'.class' or name.startswith(c+'$') for c in classes):out.writestr(name,z.read(name))
 types=[]
 for f in [*Path('public/runtime').glob('*.jar'),jar]:
  with zipfile.ZipFile(f) as z:
   for n in z.namelist():
    if n.endswith('.class'):
     match=re.search(rb'Luy/kohesive/injekt/api/FullTypeReference<L([^;]+);>;',z.read(n))
     if match:types.append((n[:-6].replace('/','.'),match[1].decode().replace('/','.')))
 (source/'prototype/TypeMap.java').write_text('package prototype;public class TypeMap{public static java.lang.reflect.Type resolve(String n){switch(n){'+''.join('case "'+n+'":return '+t.replace('$','.')+'.class;' for n,t in types)+'default:throw new IllegalArgumentException("Unregistered AOT type "+n);}}}')
 with zipfile.ZipFile(jar) as z:
  resources=[n for n in z.namelist() if n.startswith('assets/') and not n.endswith('/')]
 # ICU data lookups use dynamic resource names. Include the original ICU data only
 # when the extension references the ICU API; other programs keep their small bundle.
 with zipfile.ZipFile(jar) as z:
  uses_icu=any(b'android/icu/' in z.read(n) or b'com/ibm/icu/' in z.read(n) for n in z.namelist() if n.endswith('.class'))
 if uses_icu:
  with zipfile.ZipFile('public/runtime/icu4j-79.1.jar') as z:
   resources.extend(n for n in z.namelist() if n.startswith('com/ibm/icu/') and not n.endswith(('.class','/')))
 (source/'prototype/ResourceConfig.java').write_text('package prototype;public class ResourceConfig implements org.teavm.extension.spi.resources.ResourcesPolicy{public String[] supplyResources(java.util.Collection<? extends String> names){return new String[]{'+','.join(json.dumps(n) for n in resources)+'};}}')
 outputKey='compat-probe' if os.environ.get('TEAVM_PROBE') else plugin
 props=['-Dextension='+entry['jar'],'-Dplugin='+outputKey]+(['-DmainClass=prototype.ProbeHost'] if os.environ.get('TEAVM_PROBE') else [])+(['-Dminify=false','-Ddebug=true'] if os.environ.get('TEAVM_DEBUG') else [])
 cpfile=CACHE/'classpath.txt'
 mvn(*props,'dependency:build-classpath','-Dmdep.outputFile='+str(cpfile))
 cp=cpfile.read_text().strip();toolsdir=CACHE/'tools';toolsdir.mkdir(exist_ok=True)
 run(['javac','-cp',cp,'-d',toolsdir,'scripts/PatchLibraries.java'])
 run(['java','-cp',str(toolsdir)+os.pathsep+cp,'PatchLibraries',*Path('java/libs').glob('*.jar')])
 Path('java/target/classes').mkdir(parents=True,exist_ok=True)
 # The java.base adapters call Bridge before Maven compiles application sources.
 # Compile its callback codec together so fresh snapshots do not depend on stale classes.
 run(['javac','-cp',cp,'-d','java/target/classes',*[source/('prototype/'+name+'.java') for name in ['Bridge','Callbacks','JsonValues']]])
 cp='java/target/classes'+os.pathsep+cp
 run(['javac','--patch-module','java.base=java/compat','--add-reads','java.base=ALL-UNNAMED','-cp',cp,'-d','java/target/classes',*Path('java/compat').rglob('*.java')])
 mvn(*props,'package')
 output=Path('public/teavm')/outputKey/'app.js'
 if not os.environ.get('TEAVM_DEBUG'):output.with_suffix('.js.map').unlink(missing_ok=True)
 result={'plugin':plugin,'bundleKey':outputKey,'entryPoint':'prototype.ProbeHost' if os.environ.get('TEAVM_PROBE') else 'prototype.TeaHost','outputSha256':hashlib.sha256(output.read_bytes()).hexdigest(), 'debug':bool(os.environ.get('TEAVM_DEBUG')),'extensionSha256':entry['convertedSha256'],'seconds':time.monotonic()-started,'bytes':(Path('public/teavm')/outputKey/'app.js').stat().st_size,'teavm':'0.16.0'}
 Path('results').mkdir(exist_ok=True);Path('results/build-'+outputKey+'.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
