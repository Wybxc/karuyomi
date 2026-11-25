import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Future<void> writeDeviceSourcePreferences(
  FlutterSecureStorage storage,
  String key,
  String? value,
) => storage.write(key: key, value: value);
