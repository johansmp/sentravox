import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_logs/domain/entities/call_log.dart';
import 'package:sentravox/features/call_logs/domain/entities/call_log_stats.dart';

final _now = DateTime(2026, 3, 10, 14, 0);

CallLogEntry _log({
  required String outcome,
  double risk = 0.2,
  DateTime? at,
}) {
  return CallLogEntry(
    number: '3001234567',
    transcript: '',
    intent: 'consulta',
    risk: risk,
    summary: '',
    timestamp: at ?? _now,
    outcome: outcome,
  );
}

void main() {
  group('CallOutcome', () {
    test('reconoce los resultados bloqueados', () {
      expect(CallOutcome.isBlocked(CallOutcome.blockedSilent), isTrue);
      expect(CallOutcome.isBlocked(CallOutcome.blockedNotified), isTrue);
      expect(CallOutcome.isBlocked(CallOutcome.blockedByAgent), isTrue);

      expect(CallOutcome.isBlocked(CallOutcome.agent), isFalse);
      expect(CallOutcome.isBlocked(CallOutcome.allowed), isFalse);
      // Riesgo alto detectado pero sin poder colgar: no cuenta como bloqueada.
      expect(CallOutcome.isBlocked(CallOutcome.flaggedHighRisk), isFalse);
    });

    test('etiqueta valores desconocidos sin romperse', () {
      expect(CallOutcome.label('algo_nuevo'), 'algo_nuevo');
    });
  });

  group('CallLogStats', () {
    test('una lista vacía deja todo en cero', () {
      final stats = CallLogStats.from(const [], now: _now);

      expect(stats.total, 0);
      expect(stats.blocked, 0);
      expect(stats.analyzedToday, 0);
      expect(stats.maxRisk, 0);
      expect(stats.todayLabel, 'Sin llamadas analizadas hoy');
      expect(stats.blockedLabel, 'Ningún intento bloqueado');
    });

    test('cuenta bloqueadas, atendidas y riesgo máximo', () {
      final stats = CallLogStats.from([
        _log(outcome: CallOutcome.blockedSilent, risk: 0.95),
        _log(outcome: CallOutcome.agent, risk: 0.3),
        _log(outcome: CallOutcome.agent, risk: 0.5),
        _log(outcome: CallOutcome.allowed, risk: 0.1),
      ], now: _now);

      expect(stats.total, 4);
      expect(stats.blocked, 1);
      expect(stats.handledByAgent, 2);
      expect(stats.maxRisk, 0.95);
    });

    test('«hoy» se calcula por día local, no por 24 horas', () {
      final stats = CallLogStats.from([
        _log(outcome: CallOutcome.agent, at: DateTime(2026, 3, 10, 0, 5)),
        _log(outcome: CallOutcome.blockedNotified, at: DateTime(2026, 3, 10, 23, 55)),
        // Ayer: no cuenta para hoy, sí para el total.
        _log(outcome: CallOutcome.blockedSilent, at: DateTime(2026, 3, 9, 23, 59)),
      ], now: _now);

      expect(stats.total, 3);
      expect(stats.analyzedToday, 2);
      expect(stats.blockedToday, 1);
      expect(stats.blocked, 2);
    });

    test('las etiquetas se singularizan', () {
      final one = CallLogStats.from([
        _log(outcome: CallOutcome.blockedSilent),
      ], now: _now);

      expect(one.todayLabel, '1 llamada analizada hoy');
      expect(one.blockedLabel, '1 intento bloqueado');

      final many = CallLogStats.from([
        _log(outcome: CallOutcome.blockedSilent),
        _log(outcome: CallOutcome.blockedNotified),
      ], now: _now);

      expect(many.todayLabel, '2 llamadas analizadas hoy');
      expect(many.blockedLabel, '2 intentos bloqueados');
    });
  });
}
