import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_logs/domain/entities/call_log.dart';
import 'package:sentravox/features/call_screening/domain/entities/screening_event.dart';

void main() {
  group('ScreeningEvent.fromMap', () {
    test('convierte el payload nativo completo', () {
      final event = ScreeningEvent.fromMap({
        'number': '8001234567',
        'risk': 0.9,
        'intent': 'spam',
        'outcome': CallOutcome.blockedSilent,
        'message': 'Bloqueada por seguridad.',
        'timestamp': 1780000000000,
      });

      expect(event.number, '8001234567');
      expect(event.risk, 0.9);
      expect(event.intent, 'spam');
      expect(event.outcome, CallOutcome.blockedSilent);
      expect(event.message, 'Bloqueada por seguridad.');
      expect(
        event.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1780000000000),
      );
    });

    test('acepta risk entero: el codec puede entregar int', () {
      final event = ScreeningEvent.fromMap({'risk': 1});
      expect(event.risk, 1.0);
    });

    test('acota el riesgo al rango 0..1', () {
      expect(ScreeningEvent.fromMap({'risk': 2.5}).risk, 1.0);
      expect(ScreeningEvent.fromMap({'risk': -1}).risk, 0.0);
    });

    test('rellena los huecos con valores por defecto', () {
      final event = ScreeningEvent.fromMap(const {});

      expect(event.number, 'desconocido');
      expect(event.risk, 0);
      expect(event.intent, 'desconocido');
      expect(event.outcome, CallOutcome.allowed);
      expect(event.message, '');
      expect(event.timestamp.millisecondsSinceEpoch, 0);
    });

    test('un número vacío se marca como desconocido', () {
      expect(ScreeningEvent.fromMap({'number': '   '}).number, 'desconocido');
      expect(ScreeningEvent.fromMap({'number': ''}).number, 'desconocido');
    });
  });
}
