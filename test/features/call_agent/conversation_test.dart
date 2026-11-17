import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_agent/domain/conversation/conversation_context.dart';
import 'package:sentravox/features/call_agent/domain/conversation/conversation_summarizer.dart';
import 'package:sentravox/features/call_agent/domain/conversation/conversation_turn.dart';
import 'package:sentravox/features/call_agent/domain/conversation/risk_model.dart';

final _t0 = DateTime(2026, 1, 1, 10, 0, 0);

DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

ConversationContext _contextWith(List<ConversationTurn> turns) {
  var context = ConversationContext(startedAt: _t0);
  for (final turn in turns) {
    context = context.addTurn(turn);
  }
  return context;
}

ConversationTurn _caller(
  String text, {
  required String intent,
  required double risk,
  int at = 0,
}) {
  return ConversationTurn.caller(text, intent: intent, risk: risk, at: _at(at));
}

void main() {
  group('SimulatedRiskModel', () {
    test('usa el riesgo base de la intención', () {
      expect(
        SimulatedRiskModel.evaluate(intent: 'saludo', text: 'hola'),
        closeTo(0.05, 0.0001),
      );
      expect(
        SimulatedRiskModel.evaluate(intent: 'fraude', text: 'algo'),
        closeTo(0.90, 0.0001),
      );
    });

    test('cae a un riesgo neutro con intenciones desconocidas', () {
      expect(
        SimulatedRiskModel.evaluate(intent: 'no_existe', text: 'algo'),
        closeTo(0.15, 0.0001),
      );
    });

    test('escala con cada frase de riesgo detectada', () {
      // base 0.15 + 2 señales ("clave", "urgente") * 0.08
      final risk = SimulatedRiskModel.evaluate(
        intent: 'consulta',
        text: 'Necesito tu CLAVE, es urgente',
      );
      expect(risk, closeTo(0.31, 0.0001));
    });

    test('nunca pasa de 1.0', () {
      final risk = SimulatedRiskModel.evaluate(
        intent: 'fraude',
        text: 'clave pin tarjeta transferencia urgente premio sorteo bloqueada',
      );
      expect(risk, 1.0);
    });

    test('signalsIn reporta las señales encontradas', () {
      expect(
        SimulatedRiskModel.signalsIn('Dame tu PIN y la tarjeta'),
        containsAll(<String>['pin', 'tarjeta']),
      );
      expect(SimulatedRiskModel.signalsIn('buenos días'), isEmpty);
    });
  });

  group('ConversationContext', () {
    test('separa los turnos por interlocutor', () {
      final context = _contextWith([
        ConversationTurn.agent('hola', at: _at(0)),
        _caller('quiero soporte', intent: 'soporte', risk: 0.2, at: 1),
        ConversationTurn.agent('claro', at: _at(2)),
      ]);

      expect(context.callerTurnCount, 1);
      expect(context.agentTurnCount, 2);
      expect(context.turns.length, 3);
    });

    test('agregados de riesgo ignoran los turnos del agente', () {
      final context = _contextWith([
        ConversationTurn.agent('hola', at: _at(0)),
        _caller('a', intent: 'consulta', risk: 0.2, at: 1),
        _caller('b', intent: 'fraude', risk: 0.8, at: 2),
      ]);

      expect(context.maxRisk, 0.8);
      expect(context.averageRisk, closeTo(0.5, 0.0001));
      expect(context.latestRisk, 0.8);
      expect(context.riskSeries, [0.2, 0.8]);
    });

    test('maxRisk y latestRisk son 0 / null sin turnos del interlocutor', () {
      final context = _contextWith([ConversationTurn.agent('hola', at: _t0)]);

      expect(context.maxRisk, 0);
      expect(context.averageRisk, 0);
      expect(context.latestRisk, isNull);
      expect(context.dominantIntent, isNull);
    });

    test('detectedIntents no repite y conserva el orden de aparición', () {
      final context = _contextWith([
        _caller('a', intent: 'saludo', risk: 0.1, at: 1),
        _caller('b', intent: 'bancario', risk: 0.7, at: 2),
        _caller('c', intent: 'saludo', risk: 0.1, at: 3),
      ]);

      expect(context.detectedIntents, ['saludo', 'bancario']);
    });

    test('dominantIntent es el más frecuente', () {
      final context = _contextWith([
        _caller('a', intent: 'fraude', risk: 0.9, at: 1),
        _caller('b', intent: 'consulta', risk: 0.1, at: 2),
        _caller('c', intent: 'fraude', risk: 0.9, at: 3),
      ]);

      expect(context.dominantIntent, 'fraude');
      expect(context.intentCounts, {'fraude': 2, 'consulta': 1});
    });

    test('dominantIntent rompe el empate con el más reciente', () {
      final context = _contextWith([
        _caller('a', intent: 'saludo', risk: 0.1, at: 1),
        _caller('b', intent: 'bancario', risk: 0.7, at: 2),
      ]);

      expect(context.dominantIntent, 'bancario');
    });

    test('riskTrend compara las dos últimas puntuaciones', () {
      ConversationContext withRisks(List<double> risks) {
        var index = 0;
        return _contextWith(
          risks
              .map((r) => _caller('t', intent: 'consulta', risk: r, at: ++index))
              .toList(),
        );
      }

      expect(withRisks([]).riskTrend, RiskTrend.unknown);
      expect(withRisks([0.3]).riskTrend, RiskTrend.unknown);
      expect(withRisks([0.2, 0.8]).riskTrend, RiskTrend.rising);
      expect(withRisks([0.8, 0.2]).riskTrend, RiskTrend.falling);
      expect(withRisks([0.50, 0.52]).riskTrend, RiskTrend.stable);
    });

    test('keyMoments ordena por riesgo y descarta los de riesgo cero', () {
      final context = _contextWith([
        _caller('bajo', intent: 'consulta', risk: 0.2, at: 1),
        _caller('alto', intent: 'fraude', risk: 0.95, at: 2),
        _caller('nulo', intent: 'saludo', risk: 0.0, at: 3),
        _caller('medio', intent: 'bancario', risk: 0.6, at: 4),
      ]);

      final moments = context.keyMoments();

      expect(moments.map((t) => t.text), ['alto', 'medio', 'bajo']);
    });

    test('keyMoments respeta el límite', () {
      final context = _contextWith([
        _caller('a', intent: 'fraude', risk: 0.9, at: 1),
        _caller('b', intent: 'fraude', risk: 0.8, at: 2),
        _caller('c', intent: 'fraude', risk: 0.7, at: 3),
        _caller('d', intent: 'fraude', risk: 0.6, at: 4),
      ]);

      expect(context.keyMoments(limit: 2).length, 2);
      expect(context.keyMoments().length, 3);
    });

    test('durationAt usa endedAt cuando la llamada terminó', () {
      final context = _contextWith([
        _caller('a', intent: 'consulta', risk: 0.1, at: 1),
      ]);

      expect(context.durationAt(_at(30)), const Duration(seconds: 30));

      final finished = context.ended(_at(10));
      expect(finished.isFinished, isTrue);
      // Ya terminó: `now` deja de contar.
      expect(finished.durationAt(_at(99)), const Duration(seconds: 10));
    });

    test('durationAt es cero si la llamada no arrancó', () {
      const context = ConversationContext();
      expect(context.durationAt(_at(50)), Duration.zero);
    });

    test('addTurn no muta el contexto anterior', () {
      final first = _contextWith([
        _caller('a', intent: 'consulta', risk: 0.1, at: 1),
      ]);
      final second = first.addTurn(ConversationTurn.agent('b', at: _at(2)));

      expect(first.turns.length, 1);
      expect(second.turns.length, 2);
    });

    test('callerTranscript concatena solo al interlocutor', () {
      final context = _contextWith([
        ConversationTurn.agent('hola, soy SentraVox', at: _at(0)),
        _caller('necesito ayuda', intent: 'soporte', risk: 0.2, at: 1),
        _caller('con mi factura', intent: 'consulta', risk: 0.1, at: 2),
      ]);

      expect(context.callerTranscript, 'necesito ayuda con mi factura');
    });

    test('fullTranscript incluye al agente y al interlocutor con etiquetas',
        () {
      final context = _contextWith([
        ConversationTurn.agent('hola, soy SentraVox', at: _at(0)),
        _caller('necesito ayuda', intent: 'soporte', risk: 0.2, at: 1),
      ]);

      expect(
        context.fullTranscript,
        'Agente: hola, soy SentraVox\nInterlocutor: necesito ayuda',
      );
    });
  });

  group('ConversationSummarizer', () {
    const summarizer = ConversationSummarizer();

    test('contexto vacío invita a iniciar', () {
      final summary =
          summarizer.summarize(const ConversationContext(), now: _t0);

      expect(summary.level, RiskLevel.none);
      expect(summary.details, isEmpty);
      expect(summary.keyMoments, isEmpty);
      expect(summary.recommendation, contains('Iniciar llamada'));
    });

    test('solo el saludo del agente: espera al interlocutor', () {
      final context = _contextWith([
        ConversationTurn.agent('hola', at: _t0),
      ]);

      final summary = summarizer.summarize(context, now: _at(5));

      expect(summary.headline, contains('esperando al interlocutor'));
      expect(summary.level, RiskLevel.none);
    });

    test('titular incluye la intención dominante y el número de turnos', () {
      final context = _contextWith([
        _caller('a', intent: 'fraude', risk: 0.9, at: 1),
        _caller('b', intent: 'fraude', risk: 0.9, at: 2),
      ]);

      final summary = summarizer.summarize(context, now: _at(10));

      expect(summary.headline, contains('2 intervenciones'));
      expect(summary.headline, contains('fraude'));
      expect(summary.headline, startsWith('Llamada en curso'));
    });

    test('el titular cambia al terminar la llamada', () {
      final context = _contextWith([
        _caller('a', intent: 'consulta', risk: 0.1, at: 1),
      ]).ended(_at(20));

      final summary = summarizer.summarize(context, now: _at(60));

      expect(summary.headline, startsWith('Llamada finalizada'));
      expect(summary.headline, contains('1 intervención'));
    });

    test('los umbrales de nivel siguen al riesgo máximo', () {
      RiskLevel levelFor(double risk) {
        final context = _contextWith([
          _caller('t', intent: 'consulta', risk: risk, at: 1),
        ]);
        return summarizer.summarize(context, now: _at(1)).level;
      }

      expect(levelFor(0.0), RiskLevel.none);
      expect(levelFor(0.3), RiskLevel.low);
      expect(levelFor(0.5), RiskLevel.medium);
      expect(levelFor(0.9), RiskLevel.high);
    });

    test('el riesgo alto recomienda bloquear', () {
      final context = _contextWith([
        _caller('dame tu clave', intent: 'fraude', risk: 0.98, at: 1),
      ]);

      final summary = summarizer.summarize(context, now: _at(2));

      expect(summary.recommendation, contains('bloquear'));
      expect(summary.keyMoments.single.text, 'dame tu clave');
    });

    test('los detalles muestran duración, turnos y riesgo con tendencia', () {
      final context = _contextWith([
        ConversationTurn.agent('hola', at: _t0),
        _caller('a', intent: 'consulta', risk: 0.2, at: 1),
        _caller('b', intent: 'bancario', risk: 0.7, at: 2),
      ]);

      final summary = summarizer.summarize(context, now: _at(65));
      final byLabel = {
        for (final detail in summary.details) detail.label: detail.value,
      };

      expect(byLabel['Duración'], '01:05');
      expect(byLabel['Turnos'], '2 interlocutor · 1 agente');
      expect(byLabel['Intenciones'], 'consulta, bancario');
      expect(byLabel['Riesgo actual'], '70% ↑');
      expect(byLabel['Riesgo máximo'], '70%');
      expect(byLabel['Riesgo promedio'], '45%');
    });
  });
}
