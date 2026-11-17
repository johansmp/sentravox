import 'package:flutter/foundation.dart';

import '../../../../shared/voice/voice_profiles.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

/// Estado de configuración compartido por toda la app.
///
/// Se expone con `SettingsScope` para que cualquier pantalla lea el mismo
/// interruptor. Las escrituras son optimistas: se refleja en la UI de inmediato
/// y se revierte si el guardado falla, así el toggle nunca miente.
class SettingsController extends ChangeNotifier {
  final SettingsRepository repository;

  SettingsController(this.repository);

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  List<String> _blocklist = const [];
  List<String> get blocklist => _blocklist;

  bool get securityEnabled => _settings.securityEnabled;
  bool get agentActivationEnabled => _settings.agentActivationEnabled;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      _settings = await repository.load();
      _blocklist = await repository.blocklist();
      _error = null;
    } catch (e) {
      // Sin ajustes persistidos se sigue con los valores por defecto, que son
      // los seguros (protección activada).
      _error = 'No se pudieron cargar los ajustes: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setSecurityEnabled(bool value) => _updateBool(
        value: value,
        key: AppSettings.keySecurityEnabled,
        apply: (s, v) => s.copyWith(securityEnabled: v),
        read: (s) => s.securityEnabled,
      );

  Future<void> setAutoActivateAgent(bool value) => _updateBool(
        value: value,
        key: AppSettings.keyAutoActivateAgent,
        apply: (s, v) => s.copyWith(autoActivateAgent: v),
        read: (s) => s.autoActivateAgent,
      );

  Future<void> setAgentAllCalls(bool value) => _updateBool(
        value: value,
        key: AppSettings.keyAgentAllCalls,
        apply: (s, v) => s.copyWith(agentAllCalls: v),
        read: (s) => s.agentAllCalls,
      );

  Future<void> setAutoAnswer(bool value) => _updateBool(
        value: value,
        key: AppSettings.keyAutoAnswer,
        apply: (s, v) => s.copyWith(autoAnswer: v),
        read: (s) => s.autoAnswer,
      );

  Future<void> setBlockUnknown(bool value) => _updateBool(
        value: value,
        key: AppSettings.keyBlockUnknown,
        apply: (s, v) => s.copyWith(blockUnknown: v),
        read: (s) => s.blockUnknown,
      );

  Future<void> setBlockThreshold(double value) async {
    final previous = _settings;
    _settings = _settings.copyWith(blockThreshold: value);
    _error = null;
    notifyListeners();

    try {
      await repository.setDouble(AppSettings.keyBlockThreshold, value);
    } catch (e) {
      _settings = previous;
      _error = 'No se pudo guardar el umbral: $e';
      notifyListeners();
    }
  }

  Future<void> setAgentName(String value) => _updateString(
        value: value,
        key: AppSettings.keyAgentName,
        apply: (s, v) => s.copyWith(agentName: v),
        read: (s) => s.agentName,
      );

  Future<void> setAgentCompany(String value) => _updateString(
        value: value,
        key: AppSettings.keyAgentCompany,
        apply: (s, v) => s.copyWith(agentCompany: v),
        read: (s) => s.agentCompany,
      );

  Future<void> setAgentRole(String value) => _updateString(
        value: value,
        key: AppSettings.keyAgentRole,
        apply: (s, v) => s.copyWith(agentRole: v),
        read: (s) => s.agentRole,
      );

  Future<void> setAgentPersonality(String value) => _updateString(
        value: value,
        key: AppSettings.keyAgentPersonality,
        apply: (s, v) => s.copyWith(agentPersonality: v),
        read: (s) => s.agentPersonality,
      );

  Future<void> setOwnerName(String value) => _updateString(
        value: value,
        key: AppSettings.keyOwnerName,
        apply: (s, v) => s.copyWith(ownerName: v),
        read: (s) => s.ownerName,
      );

  Future<void> setOwnerTitle(String value) => _updateString(
        value: value,
        key: AppSettings.keyOwnerTitle,
        apply: (s, v) => s.copyWith(ownerTitle: v),
        read: (s) => s.ownerTitle,
      );

  Future<void> setVoiceGender(String value) => _updateString(
        value: value,
        key: AppSettings.keyVoiceGender,
        apply: (s, v) => s.copyWith(voiceGender: v),
        read: (s) => s.voiceGender,
      );

  Future<void> setVoiceId(String value) => _updateString(
        value: value,
        key: AppSettings.keyVoiceId,
        apply: (s, v) => s.copyWith(voiceId: v),
        read: (s) => s.voiceId,
      );

  /// Cambia el perfil de voz y deja el TTS del sistema sincronizado.
  ///
  /// El perfil es la fuente de verdad: la app deriva de él la voz, la velocidad
  /// y el tono. Se guarda en una sola escritura para que la UI y Kotlin no
  /// queden en desacuerdo.
  Future<void> setVoiceProfile(String value) async {
    if (_settings.voiceProfile == value) return;

    final profile = voiceProfileFor(value);
    final previous = _settings;

    _settings = _settings.copyWith(
      voiceProfile: profile.id,
      voiceGender: profile.systemGender,
      speechRate: profile.systemRate,
      pitch: profile.systemPitch,
    );
    _error = null;
    notifyListeners();

    try {
      await repository.setString(AppSettings.keyVoiceProfile, profile.id);
    } catch (e) {
      _settings = previous;
      _error = 'No se pudo guardar el perfil de voz: $e';
      notifyListeners();
    }
  }

  Future<void> setInCallAudioMode(String value) => _updateString(
        value: value,
        key: AppSettings.keyInCallAudioMode,
        apply: (s, v) => s.copyWith(inCallAudioMode: v),
        read: (s) => s.inCallAudioMode,
      );

  Future<void> setLlmEnabled(bool value) => _updateBool(
        value: value,
        key: AppSettings.keyLlmEnabled,
        apply: (s, v) => s.copyWith(llmEnabled: v),
        read: (s) => s.llmEnabled,
      );

  Future<void> setLlmEndpoint(String value) => _updateString(
        value: value,
        key: AppSettings.keyLlmEndpoint,
        apply: (s, v) => s.copyWith(llmEndpoint: v),
        read: (s) => s.llmEndpoint,
      );

  Future<void> setLlmModel(String value) => _updateString(
        value: value,
        key: AppSettings.keyLlmModel,
        apply: (s, v) => s.copyWith(llmModel: v),
        read: (s) => s.llmModel,
      );

  Future<void> setLlmApiKey(String value) => _updateString(
        value: value,
        key: AppSettings.keyLlmApiKey,
        apply: (s, v) => s.copyWith(llmApiKey: v),
        read: (s) => s.llmApiKey,
      );

  Future<void> setFormality(String value) => _updateString(
        value: value,
        key: AppSettings.keyFormality,
        apply: (s, v) => s.copyWith(formality: v),
        read: (s) => s.formality,
      );

  Future<void> setSpeechRate(double value) => _updateDouble(
        value: value,
        key: AppSettings.keySpeechRate,
        apply: (s, v) => s.copyWith(speechRate: v),
        read: (s) => s.speechRate,
      );

  Future<void> setPitch(double value) => _updateDouble(
        value: value,
        key: AppSettings.keyPitch,
        apply: (s, v) => s.copyWith(pitch: v),
        read: (s) => s.pitch,
      );

  Future<void> _updateString({
    required String value,
    required String key,
    required AppSettings Function(AppSettings, String) apply,
    required String Function(AppSettings) read,
  }) async {
    if (read(_settings) == value) return;

    final previous = _settings;
    _settings = apply(_settings, value);
    _error = null;
    notifyListeners();

    try {
      await repository.setString(key, value);
    } catch (e) {
      _settings = previous;
      _error = 'No se pudo guardar el ajuste: $e';
      notifyListeners();
    }
  }

  Future<void> _updateDouble({
    required double value,
    required String key,
    required AppSettings Function(AppSettings, double) apply,
    required double Function(AppSettings) read,
  }) async {
    if (read(_settings) == value) return;

    final previous = _settings;
    _settings = apply(_settings, value);
    _error = null;
    notifyListeners();

    try {
      await repository.setDouble(key, value);
    } catch (e) {
      _settings = previous;
      _error = 'No se pudo guardar el ajuste: $e';
      notifyListeners();
    }
  }

  Future<void> addToBlocklist(String number) async {
    final normalized = number.replaceAll(RegExp(r'\D'), '');
    if (normalized.isEmpty || _blocklist.contains(normalized)) return;

    await _writeBlocklist([..._blocklist, normalized]);
  }

  Future<void> removeFromBlocklist(String number) async {
    if (!_blocklist.contains(number)) return;
    await _writeBlocklist(_blocklist.where((n) => n != number).toList());
  }

  Future<void> _writeBlocklist(List<String> numbers) async {
    final previous = _blocklist;
    _blocklist = numbers;
    _error = null;
    notifyListeners();

    try {
      await repository.setBlocklist(numbers);
    } catch (e) {
      _blocklist = previous;
      _error = 'No se pudo guardar la lista de bloqueo: $e';
      notifyListeners();
    }
  }

  Future<void> _updateBool({
    required bool value,
    required String key,
    required AppSettings Function(AppSettings, bool) apply,
    required bool Function(AppSettings) read,
  }) async {
    if (read(_settings) == value) return;

    final previous = _settings;
    _settings = apply(_settings, value);
    _error = null;
    notifyListeners();

    try {
      await repository.setBoolean(key, value);
    } catch (e) {
      _settings = previous;
      _error = 'No se pudo guardar el ajuste: $e';
      notifyListeners();
    }
  }
}
