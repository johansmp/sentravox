/// Detección de leads / oportunidades comerciales a partir del contexto de la
/// llamada. Determinista, sin ML adicional.
class LeadDetector {
  const LeadDetector._();

  /// Puntuación 0..1 de probabilidad de que la llamada sea un lead u oportunidad.
  static double score({
    required String dominantIntent,
    required bool hasName,
    required bool hasCompany,
    required bool hasCallback,
    required bool hasPurpose,
    required double sentiment,
    required double risk,
  }) {
    var s = 0.0;

    // Intención comercial o de soporte con contacto = lead claro.
    if (dominantIntent == 'venta' || dominantIntent == 'soporte') s += 0.35;
    if (dominantIntent == 'facturacion') s += 0.25;
    if (dominantIntent == 'mensajeria') s += 0.20;
    if (hasPurpose) s += 0.15;
    if (hasName) s += 0.10;
    if (hasCompany) s += 0.10;
    if (hasCallback) s += 0.15;
    if (sentiment > 0) s += 0.10;
    if (risk > 0.6) s -= 0.30; // llamada riesgosa no es lead

    return s.clamp(0.0, 1.0);
  }

  static bool isLead(double score) => score >= 0.5;
}
