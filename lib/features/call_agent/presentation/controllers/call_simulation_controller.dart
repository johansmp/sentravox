import 'package:sentravox/features/call_agent/domain/conversation/conversation_summarizer.dart';
import 'package:sentravox/features/call_agent/domain/conversation/risk_model.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/dialogue_engine.dart';
import 'package:sentravox/features/call_agent/presentation/controllers/conversation_loop_controller.dart';
import 'package:sentravox/shared/services/nlp/nlp_service.dart';

/// Simulación de llamada de la pantalla «Probar IA del agente».
///
/// Usa el clasificador de reglas en Dart ([NlpService]) y no persiste nada: es
/// un banco de pruebas del ciclo de conversación sin depender del modelo ONNX
/// ni de una llamada real.
///
/// El guion es el mismo [DialogueEngine] que usa el agente en llamadas reales:
/// la simulación solo cambia de dónde salen la intención y el riesgo. Antes
/// tenía su propio generador de respuestas y por eso «probar la IA» no se
/// parecía a lo que hacía el agente de verdad.
class CallSimulationController extends ConversationLoopController {
  final NlpService nlp;
  final DialogueEngine engine;

  CallSimulationController({
    required super.stt,
    required super.tts,
    required this.nlp,
    required super.summarizeCall,
    String agentName = 'SentraVox',
    String agentCompany = '',
    String agentRole = '',
    String agentPersonality = '',
    String ownerName = '',
    String ownerTitle = '',
    String formality = 'profesional',
    DialogueEngine? engine,
    super.summarizer = const ConversationSummarizer(),
    super.allowTextFallback = true,
  }) : engine = engine ??
            DialogueEngine(
              agentName: agentName,
              agentCompany: agentCompany,
              agentRole: agentRole,
              agentPersonality: agentPersonality,
              ownerName: ownerName,
              ownerTitle: ownerTitle,
              formality: formality,
            );

  @override
  String get greeting => engine.opening();

  @override
  Future<void> onCallStarting() async {
    // Cada simulación empieza en blanco: sin esto la segunda llamada arrastraba
    // el nombre y el motivo de la primera.
    engine.reset();
  }

  @override
  Future<TurnAnalysis> analyzeTurn(String text) async {
    final intent = await nlp.classify(text);
    final risk = SimulatedRiskModel.evaluate(intent: intent, text: text);
    return TurnAnalysis(intent: intent, risk: risk);
  }

  @override
  Future<AgentReply> generateReply({
    required String text,
    required TurnAnalysis analysis,
  }) async {
    final reply = engine.generate(
      intent: analysis.intent,
      risk: analysis.risk,
      transcript: text,
    );

    return AgentReply(
      reply.text,
      endCall: reply.endCall,
      notice: reply.notice,
    );
  }
}
