import '../entities/app_settings.dart';

abstract class SettingsRepository {
  Future<AppSettings> load();
  Future<void> setBoolean(String key, bool value);
  Future<void> setDouble(String key, double value);
  Future<void> setString(String key, String value);
  Future<List<String>> blocklist();
  Future<void> setBlocklist(List<String> numbers);
}
