/// Ajustes de protección.
///
/// Las claves son las mismas que usa `SentraVoxPrefs` en Kotlin: los ajustes
/// viven en SharedPreferences porque el servicio de screening tiene que leerlos
/// sin que exista un FlutterEngine.
class AppSettings {
  static const String keySecurityEnabled = 'security_enabled';
  static const String keyAutoActivateAgent = 'auto_activate_agent';
  static const String keyAgentAllCalls = 'agent_all_calls';
  static const String keyAutoAnswer = 'auto_answer';
  static const String keyBlockUnknown = 'block_unknown';
  static const String keyBlockThreshold = 'block_threshold';

  // Perfil del agente (prompt engine)
  static const String keyAgentName = 'agent_name';
  static const String keyAgentCompany = 'agent_company';
  static const String keyAgentRole = 'agent_role';
  static const String keyAgentPersonality = 'agent_personality';

  // Perfil del propietario
  static const String keyOwnerName = 'owner_name';
  static const String keyOwnerTitle = 'owner_title';

  // Gestor de voces
  static const String keyVoiceGender = 'voice_gender';
  static const String keyVoiceId = 'voice_id';
  static const String keyVoiceProfile = 'voice_profile';
  static const String keySpeechRate = 'speech_rate';
  static const String keyPitch = 'voice_pitch';
  static const String keyFormality = 'voice_formality';

  // Ruta de audio durante la llamada
  static const String keyInCallAudioMode = 'in_call_audio_mode';

  // IA avanzada opcional (LLM compatible con OpenAI)
  static const String keyLlmEnabled = 'llm_enabled';
  static const String keyLlmEndpoint = 'llm_endpoint';
  static const String keyLlmModel = 'llm_model';
  static const String keyLlmApiKey = 'llm_api_key';

  /// Interruptor maestro: en false no se filtra ni se activa el agente.
  final bool securityEnabled;

  /// Derivar al agente las llamadas de números desconocidos.
  final bool autoActivateAgent;

  /// Atender también las llamadas de contactos conocidos.
  ///
  /// Por defecto el agente solo filtra desconocidos. Con esto activado, el
  /// usuario no tiene que hablar con nadie: el agente atiende toda llamada que
  /// pase el filtro de riesgo.
  final bool agentAllCalls;

  /// Descolgar la llamada automáticamente cuando la atiende el agente.
  ///
  /// Sin esto el agente se abre pero el teléfono sigue sonando: filtrar una
  /// llamada (`CallScreeningService`) y contestarla (`TelecomManager`) son dos
  /// cosas distintas.
  final bool autoAnswer;

  /// Bloquear cualquier desconocido, sin analizar riesgo.
  final bool blockUnknown;

  /// Riesgo a partir del cual se bloquea antes de contestar.
  final double blockThreshold;

  // --- Perfil del agente (prompt engine) ---
  final String agentName;
  final String agentCompany;
  final String agentRole;
  final String agentPersonality;

  // --- Perfil del propietario ---
  final String ownerName;
  final String ownerTitle;

  // --- Gestor de voces ---
  final String voiceGender;

  /// Nombre exacto de la voz del motor TTS; vacío = elegir automáticamente.
  final String voiceId;

  /// Perfil cerrado de voz (5 opciones) que combina voz neuronal y velocidad.
  final String voiceProfile;
  final double speechRate;
  final double pitch;
  final String formality;

  /// Cómo se intenta que la voz llegue al interlocutor durante la llamada:
  /// `acoustic` (altavoz + micrófono, la más compatible), `direct`
  /// (AudioTrack experimental) o `auto`.
  final String inCallAudioMode;

  // --- IA avanzada opcional ---
  final bool llmEnabled;
  final String llmEndpoint;
  final String llmModel;
  final String llmApiKey;

  const AppSettings({
    this.securityEnabled = true,
    this.autoActivateAgent = true,
    this.agentAllCalls = false,
    this.autoAnswer = true,
    this.blockUnknown = false,
    this.blockThreshold = 0.6,
    this.agentName = 'SentraVox',
    this.agentCompany = '',
    this.agentRole = 'recepcionista',
    this.agentPersonality = 'profesional, amable y eficiente',
    this.ownerName = '',
    this.ownerTitle = '',
    this.voiceGender = 'femenina',
    this.voiceId = '',
    this.voiceProfile = 'femenina_natural',
    this.speechRate = 0.88,
    this.pitch = 1.05,
    this.formality = 'profesional',
    this.inCallAudioMode = 'acoustic',
    this.llmEnabled = true,
    this.llmEndpoint = 'https://api.openai.com/v1/chat/completions',
    this.llmModel = 'gpt-4o-mini',
    this.llmApiKey = '',
  });

  /// El agente solo se activa si la protección está encendida.
  bool get agentActivationEnabled => securityEnabled && autoActivateAgent;

  /// Contestar automáticamente solo tiene sentido si el agente va a atender.
  bool get autoAnswerEnabled => agentActivationEnabled && autoAnswer;

  /// La inyección directa es experimental: si falla, el nativo cae al altavoz.
  bool get directAudioInjection =>
      inCallAudioMode == 'direct' || inCallAudioMode == 'auto';

  /// El LLM solo se usa si está activado y tiene una clave configurada.
  bool get llmUsable =>
      llmEnabled && llmApiKey.trim().isNotEmpty && llmEndpoint.trim().isNotEmpty;

  AppSettings copyWith({
    bool? securityEnabled,
    bool? autoActivateAgent,
    bool? agentAllCalls,
    bool? autoAnswer,
    bool? blockUnknown,
    double? blockThreshold,
    String? agentName,
    String? agentCompany,
    String? agentRole,
    String? agentPersonality,
    String? ownerName,
    String? ownerTitle,
    String? voiceGender,
    String? voiceId,
    String? voiceProfile,
    double? speechRate,
    double? pitch,
    String? formality,
    String? inCallAudioMode,
    bool? llmEnabled,
    String? llmEndpoint,
    String? llmModel,
    String? llmApiKey,
  }) {
    return AppSettings(
      securityEnabled: securityEnabled ?? this.securityEnabled,
      autoActivateAgent: autoActivateAgent ?? this.autoActivateAgent,
      agentAllCalls: agentAllCalls ?? this.agentAllCalls,
      autoAnswer: autoAnswer ?? this.autoAnswer,
      blockUnknown: blockUnknown ?? this.blockUnknown,
      blockThreshold: blockThreshold ?? this.blockThreshold,
      agentName: agentName ?? this.agentName,
      agentCompany: agentCompany ?? this.agentCompany,
      agentRole: agentRole ?? this.agentRole,
      agentPersonality: agentPersonality ?? this.agentPersonality,
      ownerName: ownerName ?? this.ownerName,
      ownerTitle: ownerTitle ?? this.ownerTitle,
      voiceGender: voiceGender ?? this.voiceGender,
      voiceId: voiceId ?? this.voiceId,
      voiceProfile: voiceProfile ?? this.voiceProfile,
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      formality: formality ?? this.formality,
      inCallAudioMode: inCallAudioMode ?? this.inCallAudioMode,
      llmEnabled: llmEnabled ?? this.llmEnabled,
      llmEndpoint: llmEndpoint ?? this.llmEndpoint,
      llmModel: llmModel ?? this.llmModel,
      llmApiKey: llmApiKey ?? this.llmApiKey,
    );
  }

  factory AppSettings.fromMap(Map<Object?, Object?> map) {
    const defaults = AppSettings();

    return AppSettings(
      securityEnabled:
          (map[keySecurityEnabled] as bool?) ?? defaults.securityEnabled,
      autoActivateAgent:
          (map[keyAutoActivateAgent] as bool?) ?? defaults.autoActivateAgent,
      agentAllCalls:
          (map[keyAgentAllCalls] as bool?) ?? defaults.agentAllCalls,
      autoAnswer: (map[keyAutoAnswer] as bool?) ?? defaults.autoAnswer,
      blockUnknown: (map[keyBlockUnknown] as bool?) ?? defaults.blockUnknown,
      blockThreshold: ((map[keyBlockThreshold] as num?)?.toDouble() ??
              defaults.blockThreshold)
          .clamp(0.1, 1.0),
      agentName: (map[keyAgentName] as String?) ?? defaults.agentName,
      agentCompany: (map[keyAgentCompany] as String?) ?? defaults.agentCompany,
      agentRole: (map[keyAgentRole] as String?) ?? defaults.agentRole,
      agentPersonality:
          (map[keyAgentPersonality] as String?) ?? defaults.agentPersonality,
      ownerName: (map[keyOwnerName] as String?) ?? defaults.ownerName,
      ownerTitle: (map[keyOwnerTitle] as String?) ?? defaults.ownerTitle,
      voiceGender: (map[keyVoiceGender] as String?) ?? defaults.voiceGender,
      voiceId: (map[keyVoiceId] as String?) ?? defaults.voiceId,
      voiceProfile:
          (map[keyVoiceProfile] as String?) ?? defaults.voiceProfile,
      speechRate: ((map[keySpeechRate] as num?)?.toDouble() ??
              defaults.speechRate)
          .clamp(0.5, 2.0),
      pitch: ((map[keyPitch] as num?)?.toDouble() ?? defaults.pitch)
          .clamp(0.5, 2.0),
      formality: (map[keyFormality] as String?) ?? defaults.formality,
      inCallAudioMode:
          (map[keyInCallAudioMode] as String?) ?? defaults.inCallAudioMode,
      llmEnabled: (map[keyLlmEnabled] as bool?) ?? defaults.llmEnabled,
      llmEndpoint: (map[keyLlmEndpoint] as String?) ?? defaults.llmEndpoint,
      llmModel: (map[keyLlmModel] as String?) ?? defaults.llmModel,
      llmApiKey: (map[keyLlmApiKey] as String?) ?? defaults.llmApiKey,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.securityEnabled == securityEnabled &&
        other.autoActivateAgent == autoActivateAgent &&
        other.agentAllCalls == agentAllCalls &&
        other.autoAnswer == autoAnswer &&
        other.blockUnknown == blockUnknown &&
        other.blockThreshold == blockThreshold &&
        other.agentName == agentName &&
        other.agentCompany == agentCompany &&
        other.agentRole == agentRole &&
        other.agentPersonality == agentPersonality &&
        other.ownerName == ownerName &&
        other.ownerTitle == ownerTitle &&
        other.voiceGender == voiceGender &&
        other.voiceId == voiceId &&
        other.voiceProfile == voiceProfile &&
        other.speechRate == speechRate &&
        other.pitch == pitch &&
        other.formality == formality &&
        other.inCallAudioMode == inCallAudioMode &&
        other.llmEnabled == llmEnabled &&
        other.llmEndpoint == llmEndpoint &&
        other.llmModel == llmModel &&
        other.llmApiKey == llmApiKey;
  }

  @override
  int get hashCode => Object.hashAll([
        securityEnabled,
        autoActivateAgent,
        agentAllCalls,
        autoAnswer,
        blockUnknown,
        blockThreshold,
        agentName,
        agentCompany,
        agentRole,
        agentPersonality,
        ownerName,
        ownerTitle,
        voiceGender,
        voiceId,
        voiceProfile,
        speechRate,
        pitch,
        formality,
        inCallAudioMode,
        llmEnabled,
        llmEndpoint,
        llmModel,
        llmApiKey,
      ]);
}
