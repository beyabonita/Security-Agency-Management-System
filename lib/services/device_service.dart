import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceService {
  static const _key = 'samanion_device_id';

  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.isEmpty) {
      id =
          '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(0xFFFFFF).toRadixString(16)}';
      await prefs.setString(_key, id);
    }
    return id;
  }
}
