import 'dart:math' as math;

import 'package:sentravox/features/call_agent/domain/conversation/risk_model.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/intent_labels.dart';
import 'package:sentravox/features/call_agent/domain/entities/intent.dart';
import 'package:sentravox/features/call_agent/domain/repositories/classifier_repository.dart';
import 'package:sentravox/shared/services/nlp/nlp_service.dart';

/// Clasificador de las llamadas reales sin modelo nativo.
///
/// El ONNX que se distribuía era un marcador de posición (modelo de 0 bytes y
/// vocabulario de 5 palabras). Se retiró para no arrastrar ONNX Runtime ni
/// conflictos nativos. La inteligencia de screening vive en las reglas en
/// español + [SimulatedRiskModel], que sí están probadas y funcionan sin red.
class RulesClassifierRepositoryImpl implements ClassifierRepository {
  final NlpService nlp;

  RulesClassifierRepositoryImpl({NlpService? nlp}) : nlp = nlp ?? NlpService();

  @override
  Future<IntentResult> classify(String text) async {
    final label = await nlp.classify(text);
    final intent = IntentLabels.canonical(label);
    final spanish = IntentLabels.spanishLabel(intent);

    final risk = SimulatedRiskModel.evaluate(intent: spanish, text: text);
    final confidence = intent == CallerIntent.other ||
            intent == CallerIntent.unclear
        ? 0.0
        : 0.75;

    return IntentResult(
      intent: spanish,
      confidence: confidence,
      riskScore: math.min(risk, 1.0),
    );
  }
}
