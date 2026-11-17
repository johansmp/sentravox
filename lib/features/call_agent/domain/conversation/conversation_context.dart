import 'conversation_turn.dart';

enum RiskTrend { unknown, stable, rising, falling }

/// Estado acumulado de una llamada: los turnos más todo lo que se deriva de
/// ellos. Inmutable — cada operación devuelve un contexto nuevo, así que la UI
/// puede reconstruirse sin sorpresas por aliasing.
class ConversationContext {
  final String number;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<ConversationTurn> turns;

  const ConversationContext({
    this.number = 'simulación',
    this.startedAt,
    this.endedAt,
    this.turns = const [],
  });

  ConversationContext addTurn(ConversationTurn turn) {
    return ConversationContext(
      number: number,
      startedAt: startedAt,
      endedAt: endedAt,
      turns: [...turns, turn],
    );
  }

  ConversationContext ended(DateTime at) {
    return ConversationContext(
      number: number,
      startedAt: startedAt,
      endedAt: at,
      turns: turns,
    );
  }

  bool get isEmpty => turns.isEmpty;
  bool get isNotEmpty => turns.isNotEmpty;
  bool get isFinished => endedAt != null;

  List<ConversationTurn> get callerTurns =>
      turns.where((t) => t.speaker == Speaker.caller).toList(growable: false);

  List<ConversationTurn> get agentTurns =>
      turns.where((t) => t.speaker == Speaker.agent).toList(growable: false);

  int get callerTurnCount => callerTurns.length;
  int get agentTurnCount => agentTurns.length;

  /// Todas las puntuaciones de riesgo en orden cronológico.
  List<double> get riskSeries => callerTurns
      .map((t) => t.risk)
      .whereType<double>()
      .toList(growable: false);

  double get maxRisk =>
      riskSeries.isEmpty ? 0 : riskSeries.reduce((a, b) => a > b ? a : b);

  double get averageRisk => riskSeries.isEmpty
      ? 0
      : riskSeries.reduce((a, b) => a + b) / riskSeries.length;

  double? get latestRisk => riskSeries.isEmpty ? null : riskSeries.last;

  /// Intenciones detectadas, sin repetir, en orden de aparición.
  List<String> get detectedIntents {
    final seen = <String>{};
    final ordered = <String>[];
    for (final turn in callerTurns) {
      final intent = turn.intent;
      if (intent != null && seen.add(intent)) ordered.add(intent);
    }
    return List.unmodifiable(ordered);
  }

  Map<String, int> get intentCounts {
    final counts = <String, int>{};
    for (final turn in callerTurns) {
      final intent = turn.intent;
      if (intent != null) counts[intent] = (counts[intent] ?? 0) + 1;
    }
    return counts;
  }

  /// Intención más frecuente; ante empate gana la más reciente.
  String? get dominantIntent {
    final counts = intentCounts;
    if (counts.isEmpty) return null;

    String? best;
    var bestCount = 0;
    for (final turn in callerTurns.reversed) {
      final intent = turn.intent;
      if (intent == null) continue;
      final count = counts[intent] ?? 0;
      if (count > bestCount) {
        best = intent;
        bestCount = count;
      }
    }
    return best;
  }

  /// Los turnos de mayor riesgo, de más a menos.
  List<ConversationTurn> keyMoments({int limit = 3}) {
    final scored = callerTurns.where((t) => (t.risk ?? 0) > 0).toList()
      ..sort((a, b) => (b.risk ?? 0).compareTo(a.risk ?? 0));
    return scored.take(limit).toList(growable: false);
  }

  /// Comparación entre las dos últimas puntuaciones.
  RiskTrend get riskTrend {
    final series = riskSeries;
    if (series.length < 2) return RiskTrend.unknown;

    final delta = series.last - series[series.length - 2];
    if (delta.abs() < 0.05) return RiskTrend.stable;
    return delta > 0 ? RiskTrend.rising : RiskTrend.falling;
  }

  Duration durationAt(DateTime now) {
    final start = startedAt;
    if (start == null) return Duration.zero;
    return (endedAt ?? now).difference(start);
  }

  /// Todo lo dicho por el interlocutor, para resumir o analizar el sentimiento.
  String get callerTranscript =>
      callerTurns.map((t) => t.text).join(' ');

  /// Conversación completa con etiquetas, para guardar en el historial.
  ///
  /// Incluye los turnos del agente: si el interlocutor no llegó a hablar (por
  /// ejemplo, una llamada de prueba sin audio), el historial muestra al menos
  /// el saludo en lugar de una transcripción vacía.
  String get fullTranscript => turns
      .map((t) => '${t.isCaller ? 'Interlocutor' : 'Agente'}: ${t.text}')
      .join('\n');
}
