/// Heurística de riesgo para la simulación.
///
/// El clasificador ONNX ya devuelve su propio `riskScore`; esto cubre el camino
/// de simulación, que usa el clasificador de reglas en Dart ([NlpService]) y
/// solo produce una etiqueta de intención. Es puro y determinista a propósito.
class SimulatedRiskModel {
  const SimulatedRiskModel._();

  /// Riesgo base por intención (etiquetas en español de NlpService).
  static const Map<String, double> _intentRisk = {
    'fraude': 0.90,
    'amenaza': 0.85,
    'bancario': 0.70,
    'venta': 0.35,
    'buscar_persona': 0.20,
    'consulta': 0.15,
    'soporte': 0.15,
    'facturacion': 0.15,
    'mensajeria': 0.12,
    'identidad': 0.10,
    'sin_intencion': 0.10,
    'empresa': 0.08,
    'saludo': 0.05,
    'despedida': 0.05,
    'presentacion': 0.05,
  };

  /// Señales típicas de ingeniería social; cada una suma riesgo.
  static const List<String> _riskyPhrases = [
    'clave',
    'contraseña',
    'pin',
    'tarjeta',
    'código de verificación',
    'codigo de verificacion',
    'transferencia',
    'consignar',
    'urgente',
    'premio',
    'lotería',
    'loteria',
    'sorteo',
    'bloqueada',
    'bloqueado',
    'suspendida',
    'datos personales',
    'cédula',
    'cedula',
  ];

  static const double _phraseWeight = 0.08;

  /// Riesgo combinado en el rango 0..1.
  static double evaluate({required String intent, required String text}) {
    final base = _intentRisk[intent] ?? 0.15;
    final lower = text.toLowerCase();

    final hits = _riskyPhrases.where((phrase) => lower.contains(phrase)).length;

    return (base + hits * _phraseWeight).clamp(0.0, 1.0);
  }

  /// Frases de riesgo presentes en el texto, para explicar la puntuación.
  static List<String> signalsIn(String text) {
    final lower = text.toLowerCase();
    return _riskyPhrases.where((phrase) => lower.contains(phrase)).toList();
  }
}
