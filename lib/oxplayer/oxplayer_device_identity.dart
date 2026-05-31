import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const _kOxDeviceIdPrefsKey = 'oxplayer_device_id';

/// Stable device id for api-v2 `POST /auth/claim-code` and `/auth/refresh` (no TDLib).
Future<({String deviceId, String? deviceName})> oxplayerResolveDeviceIdentity({
  required String defaultDeviceName,
}) async {
  final prefs = await SharedPreferences.getInstance();
  var storedId = prefs.getString(_kOxDeviceIdPrefsKey)?.trim() ?? '';
  if (storedId.isEmpty) {
    storedId = _generateDeviceId();
    await prefs.setString(_kOxDeviceIdPrefsKey, storedId);
  }
  return (deviceId: storedId, deviceName: defaultDeviceName);
}

String _generateDeviceId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'oxa-$hex';
}
