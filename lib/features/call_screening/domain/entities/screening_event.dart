/// Una decisión de screening tomada por el servicio nativo.
///
/// Se encola en el lado nativo (puede ocurrir con la app cerrada) y Dart la
/// importa al historial en el siguiente arranque.
class ScreeningEvent {
  final String number;
  final double risk;
  final String intent;
  final String outcome;
  final String message;
  final DateTime timestamp;

  const ScreeningEvent({
    required this.number,
    required this.risk,
    required this.intent,
    required this.outcome,
    required this.message,
    required this.timestamp,
  });

  /// Tolerante con los tipos: el codec de plataforma puede entregar int o double.
  factory ScreeningEvent.fromMap(Map<Object?, Object?> map) {
    final millis = (map['timestamp'] as num?)?.toInt() ?? 0;

    return ScreeningEvent(
      number: (map['number'] as String?)?.trim().isNotEmpty == true
          ? map['number'] as String
          : 'desconocido',
      risk: ((map['risk'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      intent: (map['intent'] as String?) ?? 'desconocido',
      outcome: (map['outcome'] as String?) ?? 'allowed',
      message: (map['message'] as String?) ?? '',
      timestamp: millis > 0
          ? DateTime.fromMillisecondsSinceEpoch(millis)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
