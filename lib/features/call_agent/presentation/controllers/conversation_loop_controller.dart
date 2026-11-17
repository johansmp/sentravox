import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:sentravox/features/call_agent/domain/conversation/conversation_context.dart';
import 'package:sentravox/features/call_agent/domain/conversation/conversation_summarizer.dart';
import 'package:sentravox/features/call_agent/domain/conversation/conversation_turn.dart';
import 'package:sentravox/features/call_agent/domain/fsm/agent_fsm.dart';
import 'package:sentravox/features/call_logs/domain/usecases/summarize_call.dart';
import 'package:sentravox/shared/services/stt/stt_error_policy.dart';
import 'package:sentravox/shared/services/stt/stt_service.dart';
import 'package:sentravox/shared/services/tts/tts_service.dart';

/// Resultado de analizar una intervención del interlocutor.
class TurnAnalysis {
  final String intent;
  final double risk;

  const TurnAnalysis({required this.intent, required this.risk});
}

/// Lo que el agente responde en su turno, más la decisión que lo acompaña.
class AgentReply {
  final String text;

  /// El agente da la llamada por terminada: ya tiene lo que necesitaba, el
  /// interlocutor se despidió o no hay nada que rescatar. El bucle cuelga tras
  /// hablar en lugar de reabrir el micrófono, que es lo que antes convertía
  /// cualquier conversación en un intercambio sin final.
  final bool endCall;

  /// Motivo del cierre, para la pantalla y el historial.
  final String? notice;

  const AgentReply(this.text, {this.endCall = false, this.notice});
}

/// Coreografía compartida de una conversación por voz.
///
/// El turno de palabra es explícito y frágil de reproducir, así que vive en un
/// solo sitio: la simulación y las llamadas reales heredan de aquí para que
/// ambas se comporten igual.
///
/// Ciclo de un turno:
///   resultado definitivo → cerrar micrófono → analizar → responder
///   → `await tts.speak` → **solo entonces** reabrir micrófono.
///
/// Cerrar el micrófono antes de hablar no es opcional: si sigue abierto, el
/// reconocedor transcribe la propia voz del agente y la conversación se
/// realimenta.
abstract class ConversationLoopController extends ChangeNotifier {
  final SttService stt;
  final TtsService tts;
  final SummarizeCall summarizeCall;
  final ConversationSummarizer summarizer;
  final double blockingThreshold;

  /// Si el micrófono falla, la simulación puede seguir por texto en lugar de
  /// terminar. Las llamadas reales dejan esto en false.
  final bool allowTextFallback;

  ConversationLoopController({
    required this.stt,
    required this.tts,
    required this.summarizeCall,
    this.summarizer = const ConversationSummarizer(),
    this.blockingThreshold = 0.7,
    this.allowTextFallback = false,
  });

  /// Cuántos errores transitorios seguidos se toleran antes de rendirse.
  static const int maxConsecutiveSttErrors = 3;

  // ---------------------------------------------------------------------------
  // Puntos de extensión
  // ---------------------------------------------------------------------------

  /// Lo primero que dice el agente al descolgar.
  String get greeting;

  /// Se ejecuta con el número ya fijado y antes del saludo: buen sitio para
  /// recuperar lo que se sepa del interlocutor.
  Future<void> onCallStarting() async {}

  /// Clasifica la intervención y le asigna riesgo.
  Future<TurnAnalysis> analyzeTurn(String text);

  /// Respuesta del agente a esa intervención.
  Future<AgentReply> generateReply({
    required String text,
    required TurnAnalysis analysis,
  });

  /// Efectos secundarios tras analizar (memoria, telemetría…).
  Future<void> onTurnAnalyzed(String text, TurnAnalysis analysis) async {}

  /// El riesgo superó el umbral: la llamada va a terminar.
  Future<void> onBlocking(TurnAnalysis analysis) async {}

  /// La llamada terminó, por cualquier vía. Buen sitio para persistirla.
  Future<void> onCallFinished(ConversationContext context) async {}

  // ---------------------------------------------------------------------------
  // Estado observable
  // ---------------------------------------------------------------------------

  AgentState _state = AgentState.idle;
  AgentState get state => _state;

  ConversationContext _context = const ConversationContext();
  ConversationContext get context => _context;

  String _livePartial = '';
  String get livePartial => _livePartial;

  String? _error;
  String? get error => _error;

  String? _notice;
  String? get notice => _notice;

  String? _closingSummary;
  String? get closingSummary => _closingSummary;

  bool _running = false;
  bool get isRunning => _running;

  bool _processingTurn = false;
  bool get isProcessingTurn => _processingTurn;

  /// La simulación cambió a entrada de texto porque el micrófono falló.
  bool _textOnly = false;
  bool get isTextMode => _textOnly;

  StreamSubscription<SttResult>? _subscription;
  Timer? _ticker;
  bool _disposed = false;
  int _consecutiveSttErrors = 0;

  ConversationSummary summary({DateTime? now}) =>
      summarizer.summarize(_context, now: now ?? DateTime.now());

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  Future<void> start({String number = 'simulación'}) async {
    if (_running || _disposed) return;

    _running = true;
    _error = null;
    _notice = null;
    _closingSummary = null;
    _livePartial = '';
    _consecutiveSttErrors = 0;
    _textOnly = false;
    _context = ConversationContext(number: number, startedAt: DateTime.now());

    _subscription ??= stt.results.listen(_onSttResult, onError: _onSttError);
    _startTicker();

    try {
      await onCallStarting();
    } catch (_) {
      // Recuperar el contexto es opcional: la llamada se atiende igual.
    }
    if (!_running) return;

    _setState(AgentState.intro);

    addTurn(ConversationTurn.agent(greeting, at: DateTime.now()));
    await tts.speak(greeting);

    if (!_running) return;
    await resumeListening();
  }

  Future<void> stop({String? notice}) async {
    if (!_running) return;

    _running = false;
    _processingTurn = false;
    _livePartial = '';
    _textOnly = false;
    if (notice != null) _notice = notice;
    _setState(AgentState.closing);

    _ticker?.cancel();
    _ticker = null;

    try {
      await stt.stopListening();
    } catch (_) {
      // best effort: puede que el canal ya esté caído.
    }
    try {
      await tts.stop();
    } catch (_) {
      // idem.
    }

    _context = _context.ended(DateTime.now());
    _closingSummary = buildClosingSummary(_context);

    try {
      await onCallFinished(_context);
    } catch (e) {
      // Un fallo al persistir no debe dejar la llamada colgada.
      _error ??= 'No se pudo guardar el registro de la llamada: $e';
    }

    _setState(AgentState.idle);
  }

  @protected
  String? buildClosingSummary(ConversationContext context) {
    if (context.callerTurnCount == 0) return null;

    return summarizeCall(
      context.callerTranscript,
      context.dominantIntent ?? 'desconocida',
      context.maxRisk,
    );
  }

  // ---------------------------------------------------------------------------
  // STT
  // ---------------------------------------------------------------------------

  @protected
  Future<void> resumeListening() async {
    if (!_running || _disposed) return;

    _setState(AgentState.listening);

    // En modo texto el micrófono está deliberadamente cerrado; el siguiente
    // turno llega por `submitText`.
    if (_textOnly) return;

    try {
      await stt.startListening(continuous: true);
    } on PlatformException catch (e) {
      await fail(e.message ?? 'Error nativo de reconocimiento (${e.code}).');
    } on MissingPluginException {
      await fail('El canal nativo de voz no está registrado. Reinstala la app.');
    }
  }

  /// Inyecta una intervención escrita.
  ///
  /// Solo se usa en la simulación y en pruebas: permite seguir la conversación
  /// cuando el micrófono o el servicio de reconocimiento fallan (por ejemplo,
  /// «Error de red» sin conexión). En una llamada real el turno entra por STT.
  Future<void> submitText(String text) async {
    if (!_running || _disposed || _processingTurn) return;

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Si el usuario escribe, la simulación pasa a modo texto: el micrófono se
    // cierra y sus errores dejan de tumbar la conversación.
    _textOnly = true;

    try {
      await stt.stopListening();
    } catch (_) {
      // best effort: el micrófono pudo estar ya cerrado.
    }

    await _handleCallerTurn(trimmed);
  }

  void _onSttResult(SttResult result) {
    if (!_running || _disposed || _textOnly) return;

    if (!result.isFinal) {
      // El parcial solo interesa mientras escuchamos; durante el turno del
      // agente cualquier residuo se descarta.
      if (_state == AgentState.listening && !_processingTurn) {
        _livePartial = result.text;
        _safeNotify();
      }
      return;
    }

    _livePartial = '';
    _consecutiveSttErrors = 0;

    final text = result.text.trim();

    if (_processingTurn) return;

    if (text.isEmpty) {
      resumeListening();
      return;
    }

    _handleCallerTurn(text);
  }

  Future<void> _onSttError(Object error) async {
    if (!_running || _disposed || _textOnly) return;

    final message = SttErrorPolicy.describe(error);

    if (SttErrorPolicy.isFatal(error)) {
      if (allowTextFallback) {
        _switchToTextMode();
        return;
      }
      await fail(message);
      return;
    }

    _consecutiveSttErrors++;

    if (_consecutiveSttErrors > maxConsecutiveSttErrors) {
      if (allowTextFallback) {
        _switchToTextMode();
        return;
      }
      await fail('El reconocimiento de voz falla repetidamente. $message');
      return;
    }

    // Transitorio: la llamada continúa y se vuelve a escuchar.
    if (!_processingTurn) await resumeListening();
  }

  /// La simulación no puede oír: se mantiene abierta para escribir el turno.
  void _switchToTextMode() {
    _textOnly = true;
    _consecutiveSttErrors = 0;
    _livePartial = '';
    unawaited(stt.stopListening().catchError((_) {}));
    setNotice(
      'El micrófono no está disponible. Escribe el mensaje abajo para '
      'continuar la simulación.',
    );
    _setState(AgentState.listening);
  }

  // ---------------------------------------------------------------------------
  // Turno
  // ---------------------------------------------------------------------------

  /// Nunca lanza: se invoca sin await desde el listener del stream.
  Future<void> _handleCallerTurn(String text) async {
    _processingTurn = true;

    try {
      // Cerrar el micrófono antes de que hable el agente.
      try {
        await stt.stopListening();
      } catch (_) {
        // best effort.
      }

      if (!_running) return;
      _setState(AgentState.analyzing);

      final analysis = await analyzeTurn(text);
      if (!_running) return;

      addTurn(
        ConversationTurn.caller(
          text,
          intent: analysis.intent,
          risk: analysis.risk,
          at: DateTime.now(),
        ),
      );

      await onTurnAnalyzed(text, analysis);
      if (!_running) return;

      final reply = await generateReply(text: text, analysis: analysis);
      if (!_running) return;

      final blocking = analysis.risk > blockingThreshold;
      _setState(blocking ? AgentState.blocking : AgentState.responding);
      addTurn(ConversationTurn.agent(reply.text, at: DateTime.now()));

      await tts.speak(reply.text);
      if (!_running) return;

      if (blocking) {
        await onBlocking(analysis);
        _processingTurn = false;
        await stop(
          notice: 'Llamada finalizada por riesgo alto '
              '(${(analysis.risk * 100).toStringAsFixed(0)}%).',
        );
        return;
      }

      // El agente decidió cerrar: se cuelga en vez de volver a escuchar.
      if (reply.endCall) {
        _processingTurn = false;
        await stop(
          notice: reply.notice ?? 'El agente dio por terminada la llamada.',
        );
        return;
      }

      await resumeListening();
    } on PlatformException catch (e) {
      await fail(e.message ?? 'Error nativo (${e.code}).');
    } catch (e) {
      await fail('Error inesperado durante el turno: $e');
    } finally {
      _processingTurn = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  @protected
  void addTurn(ConversationTurn turn) {
    _context = _context.addTurn(turn);
    _safeNotify();
  }

  /// `notifyListeners` lanza si el notifier ya se liberó, y las llamadas
  /// terminan de forma asíncrona: pueden resolverse después del dispose.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @protected
  Future<void> fail(String message) async {
    _error = message;
    await stop();
  }

  @protected
  void setNotice(String message) {
    _notice = message;
    _safeNotify();
  }

  void _setState(AgentState state) {
    _state = state;
    _safeNotify();
  }

  /// Refresca la duración mostrada en el panel de contexto.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_running && !_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    final wasRunning = _running;

    _disposed = true;
    _running = false;
    _processingTurn = false;
    _ticker?.cancel();
    _subscription?.cancel();

    // Liberar el micrófono y cortar la voz al salir de la pantalla.
    stt.stopListening().catchError((_) {});
    tts.stop().catchError((_) {});

    if (wasRunning) {
      // Cerrar la pantalla en mitad de una llamada no debe hacerla desaparecer
      // del historial. Se persiste sin notificar: el notifier ya está muerto.
      _context = _context.ended(DateTime.now());
      _closingSummary = buildClosingSummary(_context);
      onCallFinished(_context).catchError((_) {});
    }

    super.dispose();
  }
}
