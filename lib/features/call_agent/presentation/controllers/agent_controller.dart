import 'dart:async';

import 'package:sentravox/features/call_agent/domain/conversation/conversation_context.dart';
import 'package:sentravox/features/call_agent/domain/conversation/conversation_summarizer.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/caller_facts.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/dialogue_engine.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/intent_labels.dart';
import 'package:sentravox/features/call_agent/data/llm/llm_responder.dart';
import 'package:sentravox/features/call_agent/domain/memory/memory_manager.dart';
import 'package:sentravox/features/call_agent/domain/usecases/classify_text.dart';
import 'package:sentravox/features/call_agent/presentation/controllers/conversation_loop_controller.dart';
import 'package:sentravox/features/call_logs/domain/entities/call_log.dart';
import 'package:sentravox/features/call_logs/domain/usecases/save_call_log.dart';
import 'package:sentravox/shared/analysis/sentiment_analyzer.dart';
import 'package:sentravox/shared/analysis/lead_detector.dart';
import 'package:sentravox/features/call_screening/platform/call_control_bridge.dart';

/// El agente en una llamada real.
///
/// Sobre el ciclo compartido de [ConversationLoopController] añade lo propio de
/// una llamada de verdad: clasificador ONNX, guion de filtrado con memoria por
/// número, corte de la llamada ante riesgo alto y registro en el historial.
class AgentController extends ConversationLoopController {
  final ClassifyText classify;
  final MemoryManager memory;
  final SaveCallLog saveCallLog;
  final DialogueEngine engine;
  final CallControlBridge callControl;

  /// Descolgar la llamada al empezar. Lo decide el ajuste `auto_answer`.
  final bool autoAnswer;

  /// Margen tras descolgar antes de saludar: si el agente habla en el mismo
  /// instante, la primera frase se pierde mientras se establece el audio.
  final Duration answerSettleDelay;

  /// Nombre y empresa que representa el agente (prompt engine).
  final String agentName;
  final String agentCompany;

  /// Perfil completo del agente. Si no se pasan, el motor usa valores por
  /// defecto; la pantalla de ajustes los envía todos.
  final String agentRole;
  final String agentPersonality;
  final String ownerName;
  final String ownerTitle;
  final String formality;

  /// Reescribe la respuesta local con un LLM opcional. Null = solo guion local.
  final LlmResponder? llm;

  AgentController({
    required super.stt,
    required super.tts,
    required this.classify,
    required this.memory,
    required this.saveCallLog,
    required super.summarizeCall,
    this.autoAnswer = true,
    this.answerSettleDelay = const Duration(milliseconds: 900),
    this.agentName = 'SentraVox',
    this.agentCompany = '',
    this.agentRole = '',
    this.agentPersonality = '',
    this.ownerName = '',
    this.ownerTitle = '',
    this.formality = 'profesional',
    this.llm,
    DialogueEngine? engine,
    CallControlBridge? callControl,
    super.summarizer = const ConversationSummarizer(),
  })  : engine = engine ??
            DialogueEngine(
              agentName: agentName,
              agentCompany: agentCompany,
              agentRole: agentRole,
              agentPersonality: agentPersonality,
              ownerName: ownerName,
              ownerTitle: ownerTitle,
              formality: formality,
            ),
        callControl = callControl ?? const CallControlBridge();

  bool _endedByAgent = false;
  bool _answered = false;

  /// Detecta que el interlocutor colgó para guardar la llamada en el historial.
  Timer? _callStateTimer;
  bool _sawActive = false;
  bool _audioReady = false;

  /// Comprobaciones IDLE seguidas antes de dar la llamada por colgada cuando
  /// aún no se ha visto ACTIVE. Algunos teléfonos tardan unos segundos en
  /// pasar de «descolgada» a ACTIVE; sin este margen el agente podía cortar
  /// una llamada recién contestada.
  static const int idleChecksBeforeHangup = 3;
  int _idleChecks = 0;

  /// Datos ya guardados en la sesión, para no reescribir lo mismo cada turno.
  final Set<String> _persistedFacts = {};

  @override
  String get greeting => engine.opening();

  @override
  Future<void> onCallStarting() async {
    engine.reset();
    engine.callerNumber = context.number;
    _endedByAgent = false;
    _answered = false;
    _audioReady = false;
    _idleChecks = 0;
    _persistedFacts.clear();

    // El modelo local se carga en segundo plano mientras el agente saluda y
    // escucha. Si aún no está listo en el primer turno, se usa el guion local.
    unawaited(llm?.warmUp());
    unawaited(tts.warmUp());

    await _answerCall();
    _startCallStateMonitor();

    // Lo que ya se sabe de este número: el agente no vuelve a preguntar el
    // nombre a alguien que ya se presentó en una llamada anterior.
    final known = await memory.recallPermanent(context.number);
    if (known.isEmpty) return;

    engine.seed(
      CallerFacts(
        name: known['name'],
        company: known['company'],
        callback: known['callback'],
      ),
    );

    _persistedFacts.addAll(known.keys);
    for (final entry in known.entries) {
      memory.rememberInSession(entry.key, entry.value);
    }
  }

  @override
  Future<TurnAnalysis> analyzeTurn(String text) async {
    final result = await classify(text);
    return TurnAnalysis(intent: result.intent, risk: result.riskScore);
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

    // La memoria se escribe aquí y no en `onTurnAnalyzed` porque los datos
    // (nombre, empresa, teléfono) los extrae el motor al procesar el turno:
    // antes existen solo como texto sin interpretar.
    await _remember(reply.facts);

    var responseText = reply.text;

    // IA avanzada opcional: solo reformula respuestas normales. Los cierres,
    // los temas sensibles (banco, fraude, amenaza) y el riesgo alto se quedan
    // con el guion local, que es el que garantiza que no se revele información
    // ni se alargue una llamada peligrosa. Si el LLM falla o tarda,
    // `responseText` sigue siendo el local.
    final sensitive =
        IntentLabels.isSensitive(IntentLabels.canonical(analysis.intent));

    if (llm != null &&
        !reply.endCall &&
        !sensitive &&
        analysis.risk <= blockingThreshold) {
      final rewritten = await llm!.rewrite(
        persona: engine.persona,
        facts: reply.facts,
        stage: reply.stage,
        transcript: text.length > 600 ? text.substring(0, 600) : text,
        localDraft: reply.text,
        risk: analysis.risk,
      );

      if (rewritten != null &&
          LlmPromptBuilder.isUsableRewrite(reply.text, rewritten)) {
        responseText = rewritten.trim();
      }
    }

    return AgentReply(
      responseText,
      endCall: reply.endCall,
      notice: reply.notice,
    );
  }

  /// Descuelga y prepara el audio antes de que el agente diga nada.
  ///
  /// Este era el hueco entre «el agente se abre» y «el agente atiende la
  /// llamada»: el servicio de screening deja pasar la llamada, pero descolgar
  /// es una operación aparte.
  Future<void> _answerCall() async {
    if (!autoAnswer) return;

    // El altavoz primero: si se enciende después de descolgar, el saludo puede
    // salir por el auricular y no llegar al interlocutor.
    await callControl.setInCallAudio(true);

    _answered = await callControl.answerCall();

    if (!_answered) {
      setNotice(
        'No se pudo contestar automáticamente: falta el permiso para '
        'responder llamadas. Contesta tú y el agente sigue la conversación.',
      );
      return;
    }

    // Dar tiempo a que la ruta de audio quede establecida.
    await Future<void>.delayed(answerSettleDelay);
  }

  /// Vigila el estado de la llamada para cerrar el agente y guardar el
  /// historial cuando el interlocutor cuelga, no solo cuando se pulsa el botón.
  void _startCallStateMonitor() {
    _callStateTimer?.cancel();
    _sawActive = false;
    _idleChecks = 0;
    _callStateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      checkCallStateOnce();
    });
  }

  /// Una comprobación del estado. Pública para poder probarla sin esperar 2 s.
  Future<void> checkCallStateOnce() async {
    if (!isRunning) return;

    final state = await callControl.callState();
    if (state == 'ACTIVE') {
      _sawActive = true;
      _idleChecks = 0;
      if (!_audioReady) {
        // En una llamada contestada manualmente, la ruta de audio se aplica
        // cuando el sistema ya la tiene activa.
        _audioReady = true;
        await callControl.setInCallAudio(true);
      }
      return;
    }

    if (state != 'IDLE') return;

    _idleChecks++;

    // Si ya vimos la llamada activa, IDLE significa que colgaron. Si no, se
    // espera un margen para no confundir la transición al descolgar con un
    // cuelgue.
    final confirmedHangup =
        _sawActive || _idleChecks >= idleChecksBeforeHangup;
    if (!confirmedHangup || !_answered) return;

    _callStateTimer?.cancel();
    _callStateTimer = null;
    if (isRunning) {
      await stop(notice: 'La llamada terminó.');
    }
  }

  Future<void> _remember(CallerFacts facts) async {
    for (final entry in facts.toMemoryMap().entries) {
      if (!_persistedFacts.add(entry.key)) continue;

      memory.rememberInSession(entry.key, entry.value);
      await memory.rememberPermanently(context.number, entry.key, entry.value);
    }
  }

  @override
  Future<void> onBlocking(TurnAnalysis analysis) async {
    // Cortar de verdad la llamada solo es posible siendo marcador
    // predeterminado; si el sistema lo deniega, al menos queda registrado.
    final ended = await callControl.endCall();
    _endedByAgent = ended;

    if (!ended) {
      setNotice(
        'No se pudo colgar automáticamente: SentraVox no es la app de '
        'teléfono predeterminada.',
      );
    }
  }

  @override
  Future<void> onCallFinished(ConversationContext context) async {
    _callStateTimer?.cancel();
    _callStateTimer = null;
    memory.clearSession();

    // Si el agente descolgó y la conversación acabó por su cuenta (mensaje
    // tomado, despedida, sin entender), la llamada sigue abierta: hay que
    // colgarla de verdad. Y en cualquier caso, devolver el audio a su ruta.
    if (_answered && !_endedByAgent) {
      _endedByAgent = await callControl.endCall();
    }
    await callControl.setInCallAudio(false);

    // Toda llamada atendida por el agente queda en el historial, incluso si el
    // interlocutor no llegó a decir nada.
    final blocked = context.maxRisk > blockingThreshold;

    final sentimentValue = SentimentAnalyzer.score(context.callerTranscript);
    final sentimentLabel = SentimentAnalyzer.label(sentimentValue);
    final facts = engine.facts;
    final leadScore = LeadDetector.score(
      dominantIntent: context.dominantIntent ?? 'sin_intencion',
      hasName: facts.hasName,
      hasCompany: facts.hasCompany,
      hasCallback: facts.hasCallback,
      hasPurpose: facts.hasPurpose,
      sentiment: sentimentValue,
      risk: context.maxRisk,
    );

    await saveCallLog(
      CallLogEntry(
        number: context.number,
        // Se guarda la conversación completa: así una llamada atendida sin voz
        // del interlocutor conserva el saludo del agente en el historial.
        transcript: context.fullTranscript,
        intent: context.dominantIntent ?? 'sin_intencion',
        risk: context.maxRisk,
        summary: buildClosingSummary(context) ??
            'El interlocutor no intervino durante la llamada.',
        timestamp: context.startedAt ?? DateTime.now(),
        outcome: blocked
            ? (_endedByAgent
                ? CallOutcome.blockedByAgent
                : CallOutcome.flaggedHighRisk)
            : CallOutcome.agent,
        sentiment: sentimentLabel,
        leadScore: leadScore,
      ),
    );
  }

  @override
  void dispose() {
    _callStateTimer?.cancel();
    _callStateTimer = null;
    // Libera el motor nativo del modelo local al cerrar la pantalla.
    unawaited(llm?.dispose());
    super.dispose();
  }
}
