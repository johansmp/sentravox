import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_agent/data/llm/llm_responder.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/agent_persona.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/caller_facts.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/dialogue_engine.dart';
import 'package:sentravox/features/call_agent/domain/entities/intent.dart';
import 'package:sentravox/features/call_agent/domain/memory/memory_entry.dart';
import 'package:sentravox/features/call_agent/domain/memory/memory_manager.dart';
import 'package:sentravox/features/call_agent/domain/memory/memory_repository.dart';
import 'package:sentravox/features/call_agent/domain/repositories/classifier_repository.dart';
import 'package:sentravox/features/call_agent/domain/usecases/classify_text.dart';
import 'package:sentravox/features/call_agent/presentation/controllers/agent_controller.dart';
import 'package:sentravox/features/call_logs/domain/entities/call_log.dart';
import 'package:sentravox/features/call_logs/domain/repositories/call_log_repository.dart';
import 'package:sentravox/features/call_logs/domain/usecases/save_call_log.dart';
import 'package:sentravox/features/call_logs/domain/usecases/summarize_call.dart';
import 'package:sentravox/features/call_screening/platform/call_control_bridge.dart';
import 'package:sentravox/shared/services/nlp/nlp_service.dart';
import 'package:sentravox/shared/services/stt/stt_service.dart';
import 'package:sentravox/shared/services/tts/tts_service.dart';

/// Registra en un solo sitio el orden de las acciones sobre la llamada: lo que
/// importa aquí es la secuencia (altavoz → descolgar → saludo), no cada llamada
/// por separado.
class FakeCallControl extends CallControlBridge {
  final List<String> log;
  final bool answerSucceeds;
  String callStateValue;

  FakeCallControl(
    this.log, {
    this.answerSucceeds = true,
    this.callStateValue = 'ACTIVE',
  });

  @override
  Future<bool> answerCall() async {
    log.add('answer');
    return answerSucceeds;
  }

  @override
  Future<bool> canAnswerCalls() async => answerSucceeds;

  @override
  Future<String> callState() async => callStateValue;

  @override
  Future<bool> setInCallAudio(bool enabled) async {
    log.add('audio:$enabled');
    return true;
  }

  @override
  Future<bool> endCall() async {
    log.add('end');
    return true;
  }
}

class FakeStt extends SttService {
  final StreamController<SttResult> controller =
      StreamController<SttResult>.broadcast();
  final List<String> log;

  FakeStt(this.log);

  @override
  Stream<SttResult> get results => controller.stream;

  @override
  Future<void> startListening({bool continuous = false}) async {
    log.add('listen');
  }

  @override
  Future<void> stopListening() async {}

  Future<void> say(String text) async {
    controller.add(SttResult(text: text, isFinal: true));
    // Dejar correr el turno completo (análisis, respuesta, TTS).
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
}

class FakeTts extends TtsService {
  final List<String> log;
  final List<String> spoken = [];

  FakeTts(this.log);

  @override
  Future<bool> speak(String text, {Duration? timeout}) async {
    log.add('speak');
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async {}
}

class FakeLlm extends LlmResponder {
  int calls = 0;
  final String reply;

  FakeLlm({this.reply = 'Respuesta reescrita por la IA avanzada.'});

  @override
  Future<String?> rewrite({
    required AgentPersona persona,
    required CallerFacts facts,
    required ScreeningStage stage,
    required String transcript,
    required String localDraft,
    required double risk,
  }) async {
    calls++;
    return reply;
  }
}

/// Clasificador de reglas en Dart haciendo de clasificador ONNX: basta para
/// mover el guion, que es lo que se está probando.
class FakeClassifier implements ClassifierRepository {
  final NlpService nlp = NlpService();
  final double risk;

  FakeClassifier({this.risk = 0.1});

  @override
  Future<IntentResult> classify(String text) async {
    final intent = await nlp.classify(text);
    return IntentResult(intent: intent, confidence: 1, riskScore: risk);
  }
}

class InMemoryMemory implements MemoryRepository {
  final List<MemoryEntry> entries = [];

  @override
  Future<void> save(MemoryEntry entry) async => entries.add(entry);

  @override
  Future<List<MemoryEntry>> getByNumber(String number) async =>
      entries.where((e) => e.number == number).toList();
}

class InMemoryCallLogs implements CallLogRepository {
  final List<CallLogEntry> saved = [];

  @override
  Future<void> save(CallLogEntry entry) async => saved.add(entry);

  @override
  Future<List<CallLogEntry>> getAll() async => saved;
}

({
  AgentController controller,
  FakeStt stt,
  FakeTts tts,
  List<String> log,
  InMemoryMemory memory,
  InMemoryCallLogs logs,
}) build({
  bool autoAnswer = true,
  bool answerSucceeds = true,
  double risk = 0.1,
  LlmResponder? llm,
}) {
  final log = <String>[];
  final stt = FakeStt(log);
  final tts = FakeTts(log);
  final memory = InMemoryMemory();
  final logs = InMemoryCallLogs();

  final controller = AgentController(
    stt: stt,
    tts: tts,
    classify: ClassifyText(FakeClassifier(risk: risk)),
    memory: MemoryManager(memory),
    saveCallLog: SaveCallLog(logs),
    summarizeCall: SummarizeCall(),
    callControl: FakeCallControl(log, answerSucceeds: answerSucceeds),
    autoAnswer: autoAnswer,
    answerSettleDelay: Duration.zero,
    llm: llm,
  );

  return (
    controller: controller,
    stt: stt,
    tts: tts,
    log: log,
    memory: memory,
    logs: logs,
  );
}

void main() {
  test('descuelga y prepara el audio antes de saludar', () async {
    final t = build();

    await t.controller.start(number: '3001234567');

    // El altavoz antes de descolgar, y el saludo solo después de descolgar:
    // hablar antes de que exista la llamada es hablarle a nadie.
    expect(t.log.take(3).toList(), ['audio:true', 'answer', 'speak']);
    expect(t.tts.spoken.first, contains('asistente virtual'));

    await t.controller.stop();
  });

  test('sin auto-contestar no toca la llamada', () async {
    final t = build(autoAnswer: false);

    await t.controller.start(number: '3001234567');

    expect(t.log.contains('answer'), isFalse);
    expect(t.log.contains('audio:true'), isFalse);
    expect(t.tts.spoken, isNotEmpty);

    await t.controller.stop();
  });

  test('avisa cuando el sistema no deja contestar', () async {
    final t = build(answerSucceeds: false);

    await t.controller.start(number: '3001234567');

    expect(t.controller.notice, contains('No se pudo contestar'));

    await t.controller.stop();
  });

  test('el agente cuelga la llamada que él mismo descolgó', () async {
    final t = build();
    await t.controller.start(number: '3001234567');

    await t.stt.say('Me llamo Ana Ruiz');
    await t.stt.say('Es por la factura de marzo');
    await t.stt.say('La factura 4471');
    await t.stt.say('Mi número es 3001234567');
    await t.stt.say('No, nada más');

    expect(t.controller.isRunning, isFalse, reason: 'el agente cierra la llamada');
    expect(t.log.contains('end'), isTrue, reason: 'y la cuelga de verdad');
    expect(t.log.last, 'audio:false', reason: 'y devuelve el audio a su ruta');

    // La llamada queda en el historial con lo que se averiguó.
    expect(t.logs.saved, hasLength(1));
    expect(t.logs.saved.single.outcome, CallOutcome.agent);
    expect(t.logs.saved.single.number, '3001234567');

    // Y el nombre queda recordado para la próxima llamada del mismo número.
    expect(
      t.memory.entries.any((e) => e.key == 'name' && e.value == 'Ana Ruiz'),
      isTrue,
    );
  });

  test('no repite la misma respuesta turno tras turno', () async {
    final t = build();
    await t.controller.start(number: '3001234567');

    await t.stt.say('Buenas tardes');
    await t.stt.say('Me llamo Ana');
    await t.stt.say('Es por el internet que no funciona');

    final replies = t.tts.spoken;
    expect(replies.toSet().length, replies.length);
    // Y nunca recita la conversación de vuelta.
    expect(replies.any((r) => r.contains('U:') || r.contains('A:')), isFalse);

    await t.controller.stop();
  });

  test('el texto inyectado reconoce «me llamó» y no repite el nombre', () async {
    final t = build();
    await t.controller.start(number: '3001234567');

    await t.controller.submitText('me llamó Edward Mora');

    expect(t.controller.engine.facts.name, 'Edward Mora');
    expect(t.tts.spoken.last, isNot(contains('¿Me regala su nombre?')));
    expect(t.tts.spoken.last, contains('motivo'));

    await t.controller.stop();
  });

  test('la IA avanzada reescribe respuestas normales', () async {
    final llm = FakeLlm(reply: 'Claro, ¿me regala su nombre?');
    final t = build(llm: llm);
    await t.controller.start(number: '3001234567');

    await t.stt.say('Buenas tardes');

    expect(llm.calls, 1);
    expect(t.tts.spoken.last, 'Claro, ¿me regala su nombre?');

    await t.controller.stop();
  });

  test('la IA avanzada no reescribe un cierre ni un riesgo alto', () async {
    final llm = FakeLlm();
    final t = build(llm: llm);
    await t.controller.start(number: '3001234567');

    await t.stt.say('Me llamo Ana');
    final callsBeforeClose = llm.calls;

    await t.stt.say('Hasta luego');
    expect(llm.calls, callsBeforeClose, reason: 'el cierre lo decide el guion');

    await t.controller.stop();

    final risky = FakeLlm();
    final t2 = build(llm: risky, risk: 0.95);
    await t2.controller.start(number: '3001234567');
    await t2.stt.say('Deme la clave de su cuenta');

    expect(risky.calls, 0);
    expect(t2.controller.isRunning, isFalse);

    await t2.controller.stop();
  });

  test('la llamada que termina sola se guarda en el historial', () async {
    final t = build();
    await t.controller.start(number: '3001234567');

    final callControl = t.controller.callControl as FakeCallControl;
    // Primero se ve ACTIVE (llamada descolgada) y luego IDLE (colgaron).
    await t.controller.checkCallStateOnce();
    callControl.callStateValue = 'IDLE';

    await t.controller.checkCallStateOnce();

    expect(t.controller.isRunning, isFalse);
    expect(t.logs.saved, hasLength(1));
    expect(t.controller.notice, contains('terminó'));
    // Aunque el interlocutor no habló, el saludo del agente queda guardado:
    // antes la transcripción vacía parecía una llamada filtrada.
    expect(t.logs.saved.single.transcript, contains('Agente:'));
  });

  test('un IDLE transitorio al descolgar no corta la llamada', () async {
    final t = build();
    await t.controller.start(number: '3001234567');

    final callControl = t.controller.callControl as FakeCallControl;
    callControl.callStateValue = 'IDLE';

    // Los dos primeros IDLE pueden ser la transición al descolgar.
    await t.controller.checkCallStateOnce();
    await t.controller.checkCallStateOnce();

    expect(t.controller.isRunning, isTrue);
    expect(t.logs.saved, isEmpty);

    // El tercero ya confirma que la llamada no está activa.
    await t.controller.checkCallStateOnce();
    expect(t.controller.isRunning, isFalse);
    expect(t.logs.saved, hasLength(1));
  });
}
