import 'call_log.dart';

/// Agregados del historial para las tarjetas de la pantalla principal. Puro:
/// se calcula sobre la lista ya cargada, sin consultas extra.
class CallLogStats {
  final int total;
  final int blocked;
  final int analyzedToday;
  final int blockedToday;
  final int handledByAgent;
  final double maxRisk;

  const CallLogStats({
    this.total = 0,
    this.blocked = 0,
    this.analyzedToday = 0,
    this.blockedToday = 0,
    this.handledByAgent = 0,
    this.maxRisk = 0,
  });

  factory CallLogStats.from(
    List<CallLogEntry> logs, {
    required DateTime now,
  }) {
    var blocked = 0;
    var analyzedToday = 0;
    var blockedToday = 0;
    var handledByAgent = 0;
    var maxRisk = 0.0;

    for (final log in logs) {
      final isBlocked = log.wasBlocked;
      final isToday = _sameDay(log.timestamp, now);

      if (isBlocked) blocked++;
      if (isToday) analyzedToday++;
      if (isToday && isBlocked) blockedToday++;
      if (log.outcome == CallOutcome.agent) handledByAgent++;
      if (log.risk > maxRisk) maxRisk = log.risk;
    }

    return CallLogStats(
      total: logs.length,
      blocked: blocked,
      analyzedToday: analyzedToday,
      blockedToday: blockedToday,
      handledByAgent: handledByAgent,
      maxRisk: maxRisk,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  String get todayLabel {
    if (analyzedToday == 0) return 'Sin llamadas analizadas hoy';
    if (analyzedToday == 1) return '1 llamada analizada hoy';
    return '$analyzedToday llamadas analizadas hoy';
  }

  String get blockedLabel {
    if (blocked == 0) return 'Ningún intento bloqueado';
    if (blocked == 1) return '1 intento bloqueado';
    return '$blocked intentos bloqueados';
  }
}
