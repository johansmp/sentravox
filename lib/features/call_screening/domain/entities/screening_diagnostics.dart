/// Estado de cada requisito que necesita una llamada para llegar al agente.
///
/// Existe porque «no contesta» tiene media docena de causas posibles —permiso
/// de filtrado, permiso para descolgar, notificaciones, aviso a pantalla
/// completa— y desde fuera todas se ven igual. Esto las separa.
class ScreeningDiagnostics {
  /// Android nos invoca al entrar una llamada. Sin esto no ocurre nada más.
  final bool screeningRole;

  /// El dispositivo ofrece el rol (Android 10+).
  final bool roleAvailable;

  final bool defaultDialer;

  /// Permite `acceptRingingCall()` y `endCall()`.
  final bool answerCalls;

  final bool recordAudio;
  final bool readPhoneState;
  final bool readContacts;
  final bool notifications;

  /// Android 14+ solo lo concede de oficio a apps de llamadas.
  final bool fullScreenIntent;

  final int sdkInt;

  /// Última decisión del servicio de filtrado, si alguna vez se ejecutó.
  final LastScreening? lastScreening;

  const ScreeningDiagnostics({
    this.screeningRole = false,
    this.roleAvailable = false,
    this.defaultDialer = false,
    this.answerCalls = false,
    this.recordAudio = false,
    this.readPhoneState = false,
    this.readContacts = false,
    this.notifications = false,
    this.fullScreenIntent = false,
    this.sdkInt = 0,
    this.lastScreening,
  });

  factory ScreeningDiagnostics.fromMap(Map<Object?, Object?> map) {
    bool flag(String key) => (map[key] as bool?) ?? false;

    final last = map['last_screening'];

    return ScreeningDiagnostics(
      screeningRole: flag('screening_role'),
      roleAvailable: flag('role_available'),
      defaultDialer: flag('default_dialer'),
      answerCalls: flag('answer_calls'),
      recordAudio: flag('record_audio'),
      readPhoneState: flag('read_phone_state'),
      readContacts: flag('read_contacts'),
      notifications: flag('notifications'),
      fullScreenIntent: flag('full_screen_intent'),
      sdkInt: (map['sdk_int'] as num?)?.toInt() ?? 0,
      lastScreening:
          last is Map<Object?, Object?> ? LastScreening.fromMap(last) : null,
    );
  }

  /// Lo mínimo para que una llamada desconocida se conteste sola.
  bool get canScreen => screeningRole;
  bool get canAnswer => screeningRole && answerCalls;
  bool get canConverse => canAnswer && recordAudio;

  /// El diagnóstico en una frase, priorizando la causa que hay que resolver
  /// primero: sin la anterior, arreglar la siguiente no cambia nada.
  String get headline {
    if (!screeningRole) {
      return 'Android no está avisando a SentraVox de las llamadas.';
    }
    if (!answerCalls) {
      return 'SentraVox ve las llamadas pero no puede descolgar.';
    }
    if (!recordAudio) {
      return 'El agente contesta, pero no puede escuchar al interlocutor.';
    }
    if (lastScreening == null) {
      return 'Todo listo. Aún no ha entrado ninguna llamada para filtrar.';
    }
    return 'Todo listo.';
  }
}

class LastScreening {
  final String number;
  final double risk;
  final String outcome;
  final DateTime at;

  const LastScreening({
    required this.number,
    required this.risk,
    required this.outcome,
    required this.at,
  });

  factory LastScreening.fromMap(Map<Object?, Object?> map) {
    return LastScreening(
      number: (map['number'] as String?) ?? 'desconocido',
      risk: (map['risk'] as num?)?.toDouble() ?? 0,
      outcome: (map['outcome'] as String?) ?? '',
      at: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
