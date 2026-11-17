import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_datasource.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsDatasource datasource;

  const SettingsRepositoryImpl(this.datasource);

  @override
  Future<AppSettings> load() => datasource.load();

  @override
  Future<void> setBoolean(String key, bool value) =>
      datasource.setBoolean(key, value);

  @override
  Future<void> setDouble(String key, double value) =>
      datasource.setDouble(key, value);

  @override
  Future<void> setString(String key, String value) =>
      datasource.setString(key, value);

  @override
  Future<List<String>> blocklist() => datasource.blocklist();

  @override
  Future<void> setBlocklist(List<String> numbers) =>
      datasource.setBlocklist(numbers);
}
