/// Tono con el que habla el agente.
///
/// Se elige en Configuración y cambia las plantillas del guion, no solo el
/// prompt: un agente «corporativo» y uno «amable» no deben decir exactamente lo
/// mismo. Los valores por defecto mantienen el guion profesional histórico para
/// no romper las pruebas existentes.
enum AgentFormality {
  professional,
  corporate,
  friendly;

  static AgentFormality parse(String? value) {
    return switch ((value ?? '').trim().toLowerCase()) {
      'corporativo' || 'corporate' => AgentFormality.corporate,
      'amable' || 'friendly' || 'cercano' => AgentFormality.friendly,
      _ => AgentFormality.professional,
    };
  }

  String get label => switch (this) {
        AgentFormality.professional => 'Profesional',
        AgentFormality.corporate => 'Corporativo',
        AgentFormality.friendly => 'Amable',
      };
}

/// Identidad y estilo del agente durante una llamada.
///
/// Antes los ajustes de perfil se guardaban pero el diálogo solo usaba nombre y
/// empresa. Esto reúne todo lo que el motor necesita —rol, personalidad, dueño,
/// formalidad— y sabe redactar el prompt de sistema que se le da a la IA
/// avanzada cuando está habilitada.
class AgentPersona {
  final String name;
  final String company;
  final String role;
  final String personality;
  final String ownerName;
  final String ownerTitle;
  final AgentFormality formality;

  const AgentPersona({
    this.name = 'SentraVox',
    this.company = '',
    this.role = '',
    this.personality = '',
    this.ownerName = '',
    this.ownerTitle = '',
    this.formality = AgentFormality.professional,
  });

  bool get hasCompany => company.trim().isNotEmpty;
  bool get hasRole => role.trim().isNotEmpty;
  bool get hasOwner => ownerName.trim().isNotEmpty;
  bool get hasOwnerTitle => ownerTitle.trim().isNotEmpty;

  String get companySuffix =>
      hasCompany ? ' de ${company.trim()}' : '';

  /// «Ana Ruiz» o «el titular» si no se configuró el dueño.
  String get owner => hasOwner ? ownerName.trim() : 'el titular';

  /// «de Ana Ruiz» / «del titular».
  String get ofOwner => hasOwner ? 'de ${ownerName.trim()}' : 'del titular';

  /// «a Ana Ruiz» / «al titular».
  String get toOwner => hasOwner ? 'a ${ownerName.trim()}' : 'al titular';

  /// «Ana Ruiz, gerente de operaciones».
  String get ownerWithTitle {
    if (!hasOwner) return 'el titular';
    if (!hasOwnerTitle) return ownerName.trim();
    return '${ownerName.trim()}, ${ownerTitle.trim()}';
  }

  bool get isFriendly => formality == AgentFormality.friendly;
  bool get isCorporate => formality == AgentFormality.corporate;

  /// Nombre visible; nunca se queda vacío aunque el ajuste lo esté.
  String get displayName => name.trim().isEmpty ? 'SentraVox' : name.trim();

  /// Prompt de sistema para el modo de IA avanzada.
  ///
  /// Es deliberadamente restrictivo: el agente filtra llamadas, no conversa
  /// libremente. Aun así, todo lo que el LLM devuelva se revisa y cae al guion
  /// local si incumple las reglas o tarda demasiado.
  String get systemPrompt {
    final ownerLine = hasOwner
        ? 'Trabajas para $ownerWithTitle.'
        : 'Trabajas para el titular de la línea.';
    final roleLine = hasRole ? 'Tu rol es ${role.trim()}.' : '';
    final personalityLine = personality.trim().isEmpty
        ? ''
        : 'Tu estilo es ${personality.trim()}.';

    return 'Eres $displayName, un asistente virtual de voz que atiende y '
        'filtra llamadas entrantes en español de Colombia. '
        '${hasCompany ? 'Representas a ${company.trim()}. ' : ''}'
        '$ownerLine $roleLine $personalityLine '
        'Objetivo: identificar a quien llama, averiguar el motivo y tomar un '
        'mensaje o número de devolución para $owner. '
        'Reglas obligatorias: nunca reveles datos personales, claves, códigos '
        'ni información del titular; nunca confirmes datos bancarios; no '
        'aceptes ofertas comerciales; no pidas ni repitas números de tarjeta; '
        'habla en frases cortas (máximo dos), con una sola pregunta por turno; '
        'no recites la conversación; no inventes datos que no te hayan dicho; '
        'mantén el tono ${formality.label.toLowerCase()}. '
        'Si el interlocutor pregunta si eres una persona o una IA, responde con '
        'honestidad que eres un asistente virtual; nunca finjas ser el titular. '
        'Si el interlocutor es ambiguo, pide una aclaración concreta. '
        'Devuelve únicamente lo que diría el agente en voz alta, sin etiquetas '
        'ni explicaciones.';
  }

  /// Resumen legible del perfil, para diagnóstico y pruebas.
  String get summary {
    final parts = <String>[
      'agente: $displayName',
      if (hasCompany) 'empresa: ${company.trim()}',
      if (hasRole) 'rol: ${role.trim()}',
      if (personality.trim().isNotEmpty) 'estilo: ${personality.trim()}',
      if (hasOwner) 'titular: $ownerWithTitle',
      'formalidad: ${formality.label}',
    ];
    return parts.join(', ');
  }
}
