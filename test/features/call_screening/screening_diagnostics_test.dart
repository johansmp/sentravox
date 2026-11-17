import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_screening/domain/entities/screening_diagnostics.dart';
import 'package:sentravox/features/call_screening/platform/call_control_bridge.dart';

void main() {
  group('ScreeningRoleRequest', () {
    test('traduce el estado que devuelve el nativo', () {
      expect(
        ScreeningRoleRequest.parse('requested'),
        ScreeningRoleRequest.requested,
      );
      expect(
        ScreeningRoleRequest.parse('role_unavailable'),
        ScreeningRoleRequest.roleUnavailable,
      );
      expect(
        ScreeningRoleRequest.parse('legacy_dialer_requested'),
        ScreeningRoleRequest.legacyDialer,
      );
      expect(
        ScreeningRoleRequest.parse('request_failed'),
        ScreeningRoleRequest.failed,
      );
      expect(ScreeningRoleRequest.parse(null), ScreeningRoleRequest.unsupported);
    });

    test('solo explica lo que el usuario no puede deducir', () {
      // Si el diálogo se abrió, la propia pantalla del sistema lo explica.
      expect(ScreeningRoleRequest.requested.explanation, isNull);
      expect(ScreeningRoleRequest.alreadyHeld.explanation, isNull);

      // Si no se abrió nada, hace falta decir por qué y ofrecer la salida.
      expect(
        ScreeningRoleRequest.roleUnavailable.explanation,
        contains('app de teléfono'),
      );
      expect(ScreeningRoleRequest.failed.explanation, isNotNull);
    });
  });

  group('ScreeningDiagnostics', () {
    test('lee el mapa nativo, incluida la última decisión de filtrado', () {
      final diagnostics = ScreeningDiagnostics.fromMap(const {
        'screening_role': true,
        'answer_calls': true,
        'record_audio': true,
        'read_contacts': false,
        'notifications': true,
        'full_screen_intent': false,
        'sdk_int': 34,
        'last_screening': {
          'number': '3001234567',
          'risk': 0.45,
          'outcome': 'agent',
          'timestamp': 1757000000000,
        },
      });

      expect(diagnostics.screeningRole, isTrue);
      expect(diagnostics.readContacts, isFalse);
      expect(diagnostics.sdkInt, 34);
      expect(diagnostics.lastScreening?.number, '3001234567');
      expect(diagnostics.lastScreening?.outcome, 'agent');
    });

    test('un mapa vacío no rompe nada y no da nada por concedido', () {
      final diagnostics = ScreeningDiagnostics.fromMap(const {});

      expect(diagnostics.screeningRole, isFalse);
      expect(diagnostics.lastScreening, isNull);
      expect(diagnostics.canConverse, isFalse);
    });

    test('las capacidades se acumulan en cadena', () {
      const none = ScreeningDiagnostics();
      expect(none.canScreen, isFalse);
      expect(none.canAnswer, isFalse);

      // Poder descolgar no sirve si Android no nos avisa de la llamada.
      const answerOnly = ScreeningDiagnostics(answerCalls: true);
      expect(answerOnly.canAnswer, isFalse);

      const screening = ScreeningDiagnostics(screeningRole: true);
      expect(screening.canScreen, isTrue);
      expect(screening.canAnswer, isFalse);

      const answering =
          ScreeningDiagnostics(screeningRole: true, answerCalls: true);
      expect(answering.canAnswer, isTrue);
      expect(answering.canConverse, isFalse, reason: 'falta el micrófono');

      const full = ScreeningDiagnostics(
        screeningRole: true,
        answerCalls: true,
        recordAudio: true,
      );
      expect(full.canConverse, isTrue);
    });

    test('el titular señala la primera causa a resolver, no todas', () {
      const nothing = ScreeningDiagnostics();
      expect(nothing.headline, contains('no está avisando'));

      const screening = ScreeningDiagnostics(screeningRole: true);
      expect(screening.headline, contains('no puede descolgar'));

      const answering =
          ScreeningDiagnostics(screeningRole: true, answerCalls: true);
      expect(answering.headline, contains('no puede escuchar'));

      const ready = ScreeningDiagnostics(
        screeningRole: true,
        answerCalls: true,
        recordAudio: true,
      );
      expect(ready.headline, contains('Aún no ha entrado ninguna llamada'));
    });
  });
}
