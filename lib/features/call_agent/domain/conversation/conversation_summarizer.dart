import 'conversation_context.dart';
import 'conversation_turn.dart';

enum RiskLevel { none, low, medium, high }

class SummaryDetail {
  final String label;
  final String value;

  const SummaryDetail(this.label, this.value);
}

/// Resumen legible del estado de la llamada en un instante dado.
class ConversationSummary {
  final String headline;
  final List<SummaryDetail> details;
  final String recommendation;
  final RiskLevel level;
  final List<ConversationTurn> keyMoments;

  const ConversationSummary({
    required this.headline,
    required this.details,
    required this.recommendation,
    required this.level,
    required this.keyMoments,
  });
}

/// Construye el resumen en vivo de la conversación. Puro: mismo contexto y
/// mismo `now` producen el mismo resumen.
class ConversationSummarizer {
  const ConversationSummarizer();

  ConversationSummary summarize(
    ConversationContext context, {
    required DateTime now,
  }) {
    if (context.isEmpty) {
      return const ConversationSummary(
        headline: 'Sin actividad todavía.',
        details: [],
        recommendation: 'Pulsa «Iniciar llamada» para comenzar la simulación.',
        level: RiskLevel.none,
        keyMoments: [],
      );
    }

    final level = _levelFor(context.maxRisk);

    return ConversationSummary(
      headline: _headline(context),
      details: _details(context, now),
      recommendation: _recommendation(level, context),
      level: level,
      keyMoments: context.keyMoments(),
    );
  }

  String _headline(ConversationContext context) {
    final callerTurns = context.callerTurnCount;

    if (callerTurns == 0) {
      return context.isFinished
          ? 'La llamada terminó sin intervenciones del interlocutor.'
          : 'El agente se presentó; esperando al interlocutor.';
    }

    final intent = context.dominantIntent;
    final subject = callerTurns == 1
        ? '1 intervención del interlocutor'
        : '$callerTurns intervenciones del interlocutor';

    final prefix = context.isFinished ? 'Llamada finalizada' : 'Llamada en curso';

    if (intent == null) return '$prefix · $subject.';
    return '$prefix · $subject, predomina «$intent».';
  }

  List<SummaryDetail> _details(ConversationContext context, DateTime now) {
    final details = <SummaryDetail>[
      SummaryDetail('Duración', _formatDuration(context.durationAt(now))),
      SummaryDetail(
        'Turnos',
        '${context.callerTurnCount} interlocutor · ${context.agentTurnCount} agente',
      ),
    ];

    final intents = context.detectedIntents;
    if (intents.isNotEmpty) {
      details.add(SummaryDetail('Intenciones', intents.join(', ')));
    }

    final latest = context.latestRisk;
    if (latest != null) {
      details.add(
        SummaryDetail('Riesgo actual', '${_percent(latest)} ${_trendArrow(context.riskTrend)}'),
      );
      details.add(SummaryDetail('Riesgo máximo', _percent(context.maxRisk)));
      details.add(SummaryDetail('Riesgo promedio', _percent(context.averageRisk)));
    }

    return details;
  }

  String _recommendation(RiskLevel level, ConversationContext context) {
    switch (level) {
      case RiskLevel.high:
        return 'Riesgo alto: se recomienda bloquear y reportar el número.';
      case RiskLevel.medium:
        return 'Riesgo medio: continuar con precaución y no compartir datos.';
      case RiskLevel.low:
        return 'Riesgo bajo: la conversación parece legítima.';
      case RiskLevel.none:
        return context.callerTurnCount == 0
            ? 'Aún no hay nada que evaluar.'
            : 'Sin señales de riesgo detectadas.';
    }
  }

  RiskLevel _levelFor(double risk) {
    if (risk > 0.7) return RiskLevel.high;
    if (risk > 0.4) return RiskLevel.medium;
    if (risk > 0) return RiskLevel.low;
    return RiskLevel.none;
  }

  String _trendArrow(RiskTrend trend) {
    switch (trend) {
      case RiskTrend.rising:
        return '↑';
      case RiskTrend.falling:
        return '↓';
      case RiskTrend.stable:
        return '=';
      case RiskTrend.unknown:
        return '';
    }
  }

  String _percent(double value) => '${(value * 100).toStringAsFixed(0)}%';

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
