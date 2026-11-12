import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/android_image_files.dart';
import 'package:source_runtime/source_runtime.dart';

void main() {
  test(
    'platform image blocks bind transfer and sequence without copying payload',
    () {
      final storage = Uint8List(20);
      final frame = Uint8List.sublistView(storage, 3, 15);
      ByteData.sublistView(frame)
        ..setUint32(0, 42)
        ..setUint32(4, 1);
      frame.setRange(8, 12, [1, 2, 3, 4]);
      final decoded = decodeAndroidImageBlock(
        frame,
        transfer: 42,
        sequence: 1,
      )!;
      expect(decoded, [1, 2, 3, 4]);
      decoded[0] = 99;
      expect(frame[8], 99);
      expect(decodeAndroidImageBlock(frame, transfer: 43, sequence: 1), null);
      expect(
        () => decodeAndroidImageBlock(frame, transfer: 42, sequence: 2),
        throwsA(isA<RuntimeException>()),
      );
      for (final length in [0, 8, 65537]) {
        expect(
          () => decodeAndroidImageBlock(
            Uint8List(length),
            transfer: 42,
            sequence: 1,
          ),
          throwsA(isA<RuntimeException>()),
        );
      }
    },
  );

  test('persistent platform port requires matching ACK and safely starts the next transfer', () async {
    final process = await Process.start('node', ['--input-type=module']);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.write('''
import assert from 'node:assert/strict';
import {MessageChannel} from 'node:worker_threads';
const listeners=new Set();
globalThis.window=globalThis;
window.top=window;
window.addEventListener=(_,listener)=>listeners.add(listener);
window.removeEventListener=(_,listener)=>listeners.delete(listener);
globalThis.location={origin:'https://reader.example',pathname:'/runtime/host'};
const install=new (Object.getPrototypeOf(async function(){}).constructor)('token','transfer','origin','url',${jsonEncode(androidImageFileScript)});
const channel=new MessageChannel(), received=[];
let terminal;
channel.port1.on('message',data=>{received.push(data);if(typeof data==='string'&&terminal)terminal(data);});
const wait=async(predicate)=>{const until=Date.now()+2000;while(!predicate()){if(Date.now()>until)throw Error('port timed out');await new Promise(resolve=>setTimeout(resolve,5));}};
const payload=new Uint8Array(70000).fill(23),url=URL.createObjectURL(new Blob([payload]));
assert.equal(await install('slot',1,location.origin,url),true);
for(const listener of [...listeners])listener({data:'slot',ports:[channel.port2]});
await wait(()=>received.length===1);
let first=received[0];assert(first instanceof ArrayBuffer);assert.equal(first.byteLength,65536);
assert.equal(new DataView(first).getUint32(0),1);assert.equal(new DataView(first).getUint32(4),1);
channel.port1.postMessage('ack:99:1');await new Promise(resolve=>setTimeout(resolve,20));assert.equal(received.length,1);
channel.port1.postMessage('ack:1:1');await wait(()=>received.length===2);
assert.equal(new DataView(received[1]).getUint32(4),2);
channel.port1.postMessage('ack:1:2');await wait(()=>received.length===3);assert.equal(received[2],'end:1:70000:2');
received.length=0;
assert.equal(await install('slot',2,location.origin,url),true);assert.equal(listeners.size,0);
await wait(()=>received.length===1);assert.equal(new DataView(received[0]).getUint32(0),2);
channel.port1.postMessage('cancel:1');channel.port1.postMessage('ack:1:1');
await new Promise(resolve=>setTimeout(resolve,20));assert.equal(received.length,1);
channel.port1.postMessage('cancel:2');await wait(()=>received.length===2);assert.equal(received[1],'cancelled:2');
URL.revokeObjectURL(url);channel.port1.close();channel.port2.close();
console.log('persistent slot, matching ACK, stale messages, cancellation passed');
''');
    await process.stdin.close();
    expect(
      await process.exitCode.timeout(const Duration(seconds: 10)),
      0,
      reason: await stderr,
    );
    expect(await stdout, contains('cancellation passed'));
  });
}
