/// Análisis de sentimiento léxico, determinista y sin dependencias externas.
///
/// No es un modelo, pero permite priorizar llamadas y leads sin red ni ML
/// adicional. Devuelve un valor en [-1, 1].
class SentimentAnalyzer {
  const SentimentAnalyzer._();

  static const List<String> _positive = [
    'gracias', 'perfecto', 'excelente', 'bien', 'bueno', 'claro', 'ok',
    'de acuerdo', 'entiendo', 'ayuda', 'solución', 'solucion',
  ];

  static const List<String> _negative = [
    'molesto', 'enojado', 'furioso', 'queja', 'reclamo', 'problema',
    'mal', 'pésimo', 'pesimo', 'amenaza', 'fraude', 'estafa', 'urgente',
    'bloqueado', 'suspendido',
  ];

  static double score(String text) {
    final t = text.toLowerCase();
    var pos = 0;
    var neg = 0;
    for (final w in _positive) {
      if (t.contains(w)) pos++;
    }
    for (final w in _negative) {
      if (t.contains(w)) neg++;
    }
    final total = pos + neg;
    if (total == 0) return 0.0;
    return ((pos - neg) / total).clamp(-1.0, 1.0);
  }

  static String label(double value) {
    if (value > 0.2) return 'positivo';
    if (value < -0.2) return 'negativo';
    return 'neutro';
  }
}
