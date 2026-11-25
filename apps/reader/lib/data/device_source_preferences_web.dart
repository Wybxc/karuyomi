import 'dart:js_interop';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web/web.dart' as web;

Future<void> writeDeviceSourcePreferences(
  FlutterSecureStorage storage,
  String key,
  String? value,
) async {
  // The plugin lazily generates one encryption key. Serialize writes across
  // tabs so two initial saves cannot encrypt with different keys.
  await web.window.navigator.locks
      .request(
        'karuyomi-source-preferences',
        ((web.Lock _) => storage
                .write(key: key, value: value)
                .then<JSAny?>((_) => null)
                .toJS)
            .toJS,
      )
      .toDart;
}
