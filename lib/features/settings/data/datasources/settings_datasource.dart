import 'package:flutter/services.dart';

import '../../domain/entities/app_settings.dart';

/// Acceso a los ajustes guardados nativamente (SharedPreferences).
class SettingsDatasource {
  static const MethodChannel _channel = MethodChannel('sentravox/settings');

  const SettingsDatasource();

  Future<AppSettings> load() async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('getAll');
    if (map == null) return const AppSettings();
    return AppSettings.fromMap(map);
  }

  Future<void> setBoolean(String key, bool value) async {
    await _channel.invokeMethod('setBoolean', {'key': key, 'value': value});
  }

  Future<void> setDouble(String key, double value) async {
    await _channel.invokeMethod('setDouble', {'key': key, 'value': value});
  }

  Future<void> setString(String key, String value) async {
    await _channel.invokeMethod('setString', {'key': key, 'value': value});
  }

  Future<List<String>> blocklist() async {
    final numbers =
        await _channel.invokeMethod<List<Object?>>('getBlocklist') ?? const [];
    return numbers.whereType<String>().toList();
  }

  Future<void> setBlocklist(List<String> numbers) async {
    await _channel.invokeMethod('setBlocklist', {'numbers': numbers});
  }
}
