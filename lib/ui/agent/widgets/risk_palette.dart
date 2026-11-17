import 'package:flutter/material.dart';

import '../../../features/call_agent/domain/conversation/conversation_summarizer.dart';

/// Colores compartidos por las vistas de la simulación, para que la burbuja de
/// un turno y el panel de contexto no discrepen sobre lo que es «riesgo alto».
class RiskPalette {
  const RiskPalette._();

  static const Color high = Color(0xFFE53935);
  static const Color medium = Color(0xFFF9A825);
  static const Color low = Color(0xFF43A047);

  static Color forRisk(BuildContext context, double risk) {
    if (risk > 0.7) return high;
    if (risk > 0.4) return medium;
    if (risk > 0) return low;
    return Theme.of(context).colorScheme.outline;
  }

  static Color forLevel(BuildContext context, RiskLevel level) {
    switch (level) {
      case RiskLevel.high:
        return high;
      case RiskLevel.medium:
        return medium;
      case RiskLevel.low:
        return low;
      case RiskLevel.none:
        return Theme.of(context).colorScheme.outline;
    }
  }

  static String label(RiskLevel level) {
    switch (level) {
      case RiskLevel.high:
        return 'Riesgo alto';
      case RiskLevel.medium:
        return 'Riesgo medio';
      case RiskLevel.low:
        return 'Riesgo bajo';
      case RiskLevel.none:
        return 'Sin datos';
    }
  }

  static String percent(double value) => '${(value * 100).toStringAsFixed(0)}%';
}
