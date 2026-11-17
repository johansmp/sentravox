import 'dart:math' as math;

import 'package:sentravox/features/call_agent/domain/conversation/risk_model.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/intent_labels.dart';
import 'package:sentravox/features/call_agent/domain/entities/intent.dart';
import 'package:sentravox/features/call_agent/domain/repositories/classifier_repository.dart';
import 'package:sentravox/shared/services/nlp/nlp_service.dart';

/// Clasificador de las llamadas reales: modelo ONNX **más** reglas en español.
///
/// El modelo que se distribuye hoy usa un vocabulario de marcador de posición.
/// Confiar solo en él hacía que la llamada real clasificara casi todo como
/// `unknown` mientras la simulación —que usa [NlpService]— funcionaba bien.
///
/// Aquí se consultan ambos y se elige la mejor señal:
/// - si el modelo devuelve una intención conocida con confianza suficiente, se
///   respeta (es el camino «entrenado»);
/// - si no, se usa la intención de las reglas en español;
/// - el riesgo es el mayor de los dos, más la escalada por frases de ingeniería
///   social de [SimulatedRiskModel], para que una llamada de fraude no pase por
///   «consulta» solo porque el modelo no la reconozca.
class HybridClassifierRepositoryImpl implements ClassifierRepository {
  static const double modelConfidenceFloor = 0.55;

  final ClassifierRepository model;
  final NlpService nlp;

  HybridClassifierRepositoryImpl({
    required this.model,
    NlpService? nlp,
  }) : nlp = nlp ?? NlpService();

  @override
  Future<IntentResult> classify(String text) async {
    final localLabel = await nlp.classify(text);

    IntentResult? modelResult;
    try {
      modelResult = await model.classify(text);
    } catch (_) {
      // El modelo puede faltar o fallar: las reglas siguen siendo válidas.
      modelResult = null;
    }

    final localIntent = IntentLabels.canonical(localLabel);
    final modelIntent = IntentLabels.canonical(modelResult?.intent);
    final modelConfidence = modelResult?.confidence ?? 0.0;

    final modelUsable = modelResult != null &&
        modelIntent != CallerIntent.other &&
        modelIntent != CallerIntent.unclear &&
        modelConfidence >= modelConfidenceFloor;

    final chosen = modelUsable ? modelIntent : localIntent;

    // Se devuelve la etiqueta española: el motor de diálogo la canonicaliza y
    // el historial queda con un vocabulario consistente.
    final label = IntentLabels.spanishLabel(chosen);

    final localRisk = SimulatedRiskModel.evaluate(intent: label, text: text);
    final modelRisk = modelUsable
        ? modelResult.riskScore.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final risk = math.max(localRisk, modelRisk).clamp(0.0, 1.0);

    final confidence = modelUsable
        ? modelConfidence
        : (chosen == CallerIntent.other || chosen == CallerIntent.unclear
            ? 0.0
            : 0.75);

    return IntentResult(
      intent: label,
      confidence: confidence,
      riskScore: risk,
    );
  }
}
