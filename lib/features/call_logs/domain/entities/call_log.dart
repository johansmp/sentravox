/// Cómo terminó una llamada. Los cuatro primeros valores los produce el
/// servicio nativo de screening; el resto, el agente en Dart.
class CallOutcome {
  const CallOutcome._();

  /// Bloqueada en silencio antes de sonar (riesgo muy alto o lista de bloqueo).
  static const String blockedSilent = 'blocked_silent';

  /// Bloqueada avisando al usuario.
  static const String blockedNotified = 'blocked_notified';

  /// Permitida y derivada al agente.
  static const String agent = 'agent';

  /// Permitida sin intervención (contacto conocido).
  static const String allowed = 'allowed';

  /// La protección estaba desactivada: no se analizó.
  static const String skippedDisabled = 'skipped_disabled';

  /// El agente detectó riesgo alto y logró colgar.
  static const String blockedByAgent = 'blocked_by_agent';

  /// Riesgo alto detectado, pero no se pudo cortar la llamada.
  static const String flaggedHighRisk = 'flagged_high_risk';

  static const Set<String> blockedOutcomes = {
    blockedSilent,
    blockedNotified,
    blockedByAgent,
  };

  static bool isBlocked(String outcome) => blockedOutcomes.contains(outcome);

  static String label(String outcome) {
    switch (outcome) {
      case blockedSilent:
        return 'Bloqueada en silencio';
      case blockedNotified:
        return 'Bloqueada';
      case blockedByAgent:
        return 'Colgada por el agente';
      case flaggedHighRisk:
        return 'Riesgo alto detectado';
      case agent:
        return 'Atendida por el agente';
      case allowed:
        return 'Permitida';
      case skippedDisabled:
        return 'Sin analizar';
      default:
        return outcome;
    }
  }
}

class CallLogEntry {
  final int? id;
  final String number;
  final String transcript;
  final String intent;
  final double risk;
  final String summary;
  final DateTime timestamp;
  final String outcome;
  final String sentiment;
  final double leadScore;

  CallLogEntry({
    this.id,
    required this.number,
    required this.transcript,
    required this.intent,
    required this.risk,
    required this.summary,
    required this.timestamp,
    this.outcome = CallOutcome.agent,
    this.sentiment = 'neutro',
    this.leadScore = 0.0,
  });

  bool get wasBlocked => CallOutcome.isBlocked(outcome);
}
