import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_agent/data/repositories_impl/hybrid_classifier_repository_impl.dart';
import 'package:sentravox/features/call_agent/domain/entities/intent.dart';
import 'package:sentravox/features/call_agent/domain/repositories/classifier_repository.dart';

class _FakeModel implements ClassifierRepository {
  final IntentResult? result;
  final bool throws;

  _FakeModel({this.result, this.throws = false});

  @override
  Future<IntentResult> classify(String text) async {
    if (throws) throw StateError('modelo caído');
    return result!;
  }
}

void main() {
  group('HybridClassifierRepositoryImpl', () {
    test('si el modelo no reconoce, usan las reglas en español', () async {
      final classifier = HybridClassifierRepositoryImpl(
        model: _FakeModel(
          result: IntentResult(intent: 'unknown', confidence: 0.1, riskScore: 0),
        ),
      );

      final result = await classifier.classify('es por la factura de marzo');

      expect(result.intent, 'facturacion');
      expect(result.confidence, greaterThan(0.5));
    });

    test('si el modelo reconoce con confianza, manda el modelo', () async {
      final classifier = HybridClassifierRepositoryImpl(
        model: _FakeModel(
          result: IntentResult(
            intent: 'billing',
            confidence: 0.9,
            riskScore: 0.15,
          ),
        ),
      );

      final result = await classifier.classify('es por la factura de marzo');

      expect(result.intent, 'facturacion');
    });

    test('un modelo caído no rompe la clasificación', () async {
      final classifier = HybridClassifierRepositoryImpl(
        model: _FakeModel(throws: true),
      );

      final result = await classifier.classify('el internet no funciona');

      expect(result.intent, 'soporte');
    });

    test('el riesgo combina modelo y frases de ingeniería social', () async {
      final classifier = HybridClassifierRepositoryImpl(
        model: _FakeModel(
          result: IntentResult(intent: 'unknown', confidence: 0.1, riskScore: 0),
        ),
      );

      final result = await classifier.classify(
        'debe confirmar el código de verificación de su cuenta',
      );

      expect(result.intent, 'fraude');
      expect(result.riskScore, greaterThan(0.7));
    });
  });
}
