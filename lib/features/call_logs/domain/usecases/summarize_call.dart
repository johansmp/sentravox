class SummarizeCall {
  String call(String transcript, String intent, double risk) {
    final riskLabel = risk > 0.7 ? "riesgo alto" : risk > 0.4 ? "riesgo medio" : "riesgo bajo";

    return """
Resumen automático:
- Intención detectada: $intent
- Nivel de riesgo: $riskLabel
- Extracto: ${_extractKeySentence(transcript)}
""";
  }

  String _extractKeySentence(String text) {
    final sentences = text.split('.');
    return sentences.isNotEmpty ? sentences.first.trim() : text;
  }
}
