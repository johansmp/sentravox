class IntentResult {
  final String intent;
  final double confidence;
  final double riskScore;

  IntentResult({
    required this.intent,
    required this.confidence,
    required this.riskScore,
  });
}
