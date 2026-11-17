import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_agent/presentation/controllers/call_simulation_controller.dart';
import 'package:sentravox/features/call_logs/domain/usecases/summarize_call.dart';
import 'package:sentravox/shared/services/nlp/nlp_service.dart';
import 'package:sentravox/shared/services/stt/stt_service.dart';
import 'package:sentravox/shared/services/tts/tts_service.dart';

class _FakeStt extends SttService {
  final StreamController<SttResult> controller =
      StreamController<SttResult>.broadcast();

  @override
  Stream<SttResult> get results => controller.stream;

  @override
  Future<void> startListening({bool continuous = false}) async {}

  @override
  Future<void> stopListening() async {}
}

class _FakeTts extends TtsService {
  final List<String> spoken = [];

  @override
  Future<bool> speak(String text, {Duration? timeout}) async {
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  test('si el STT falla, la simulación pasa a modo texto y sigue', () async {
    final stt = _FakeStt();
    final tts = _FakeTts();
    final controller = CallSimulationController(
      stt: stt,
      tts: tts,
      nlp: NlpService(),
      summarizeCall: SummarizeCall(),
    );

    addTearDown(() async {
      controller.dispose();
      await stt.controller.close();
    });

    await controller.start(number: 'simulación');
    expect(controller.isRunning, isTrue);

    // Código 12: el motor no soporta el idioma / no puede comprobarlo. Antes
    // era fatal y la simulación moría; ahora debe ofrecer el modo texto.
    stt.controller.addError(
      PlatformException(
        code: 'stt_error',
        message: 'Error de reconocimiento desconocido (12).',
        details: 12,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.isRunning, isTrue);
    expect(controller.isTextMode, isTrue);
    expect(controller.notice, contains('micrófono'));

    await controller.submitText('me llamo Edward Mora');

    expect(tts.spoken.last, contains('Edward Mora'));
    expect(tts.spoken.last, isNot(contains('¿Me regala su nombre?')));
    expect(controller.isRunning, isTrue);
  });
}
