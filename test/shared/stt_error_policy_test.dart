import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/shared/services/stt/stt_error_policy.dart';

PlatformException _recognitionError(int code) => PlatformException(
      code: SttErrorPolicy.recognitionCode,
      message: 'fallo',
      details: code,
    );

void main() {
  group('SttErrorPolicy', () {
    test('ERROR_CLIENT no es fatal: lo dispara nuestro propio stopListening', () {
      // Esta era la causa de que la llamada muriera tras un solo turno.
      expect(SttErrorPolicy.isFatal(_recognitionError(5)), isFalse);
    });

    test('los silencios no son fatales', () {
      expect(SttErrorPolicy.isFatal(_recognitionError(6)), isFalse); // timeout
      expect(SttErrorPolicy.isFatal(_recognitionError(7)), isFalse); // no match
      expect(SttErrorPolicy.isFatal(_recognitionError(8)), isFalse); // busy
    });

    test('los fallos de audio y permisos sí son fatales', () {
      expect(SttErrorPolicy.isFatal(_recognitionError(1)), isTrue); // audio
      expect(SttErrorPolicy.isFatal(_recognitionError(9)), isTrue); // permisos
    });

    test('red y servidor se reintentan, no cortan la llamada al primer fallo', () {
      expect(SttErrorPolicy.isFatal(_recognitionError(2)), isFalse); // network
      expect(SttErrorPolicy.isFatal(_recognitionError(3)), isFalse); // timeout
      expect(SttErrorPolicy.isFatal(_recognitionError(4)), isFalse); // server
    });

    test('stt_unavailable siempre es fatal', () {
      final error = PlatformException(
        code: SttErrorPolicy.unavailableCode,
        message: 'Falta el permiso de micrófono (RECORD_AUDIO).',
      );
      expect(SttErrorPolicy.isFatal(error), isTrue);
    });

    test('un error sin código numérico se trata como fatal', () {
      final error = PlatformException(
        code: SttErrorPolicy.recognitionCode,
        details: 'algo raro',
      );
      expect(SttErrorPolicy.isFatal(error), isTrue);
    });

    test('cualquier excepción no-plataforma es fatal', () {
      expect(SttErrorPolicy.isFatal(StateError('boom')), isTrue);
    });

    test('describe usa el mensaje nativo cuando existe', () {
      expect(
        SttErrorPolicy.describe(_recognitionError(7)),
        'fallo',
      );
      expect(
        SttErrorPolicy.describe(
          PlatformException(code: SttErrorPolicy.recognitionCode),
        ),
        contains('stt_error'),
      );
    });
  });
}
