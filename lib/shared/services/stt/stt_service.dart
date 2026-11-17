import 'dart:async';

import 'package:flutter/services.dart';

/// Un evento de reconocimiento de voz emitido por el lado nativo.
///
/// Las hipótesis parciales (`isFinal == false`) llegan primero y van cambiando;
/// solo `isFinal == true` es el texto definitivo.
class SttResult {
  final String text;
  final bool isFinal;

  const SttResult({required this.text, required this.isFinal});

  @override
  String toString() => 'SttResult(text: "$text", isFinal: $isFinal)';
}

class SttService {
  static const MethodChannel _methodChannel = MethodChannel('sentravox/stt');
  static const EventChannel _eventChannel = EventChannel('sentravox/stt_stream');

  /// Un único broadcast stream para todo el servicio: llamar a
  /// `receiveBroadcastStream()` más de una vez sobre el mismo canal provoca
  /// suscripciones nativas en conflicto.
  Stream<SttResult>? _results;

  Stream<SttResult> get results {
    _results ??= _eventChannel.receiveBroadcastStream().map(_parse);
    return _results!;
  }

  /// Solo resultados definitivos, como texto plano.
  Stream<String> get transcripts =>
      results.where((r) => r.isFinal).map((r) => r.text);

  /// Hipótesis parciales, útiles para ir mostrando texto mientras se habla.
  Stream<String> get partialTranscripts =>
      results.where((r) => !r.isFinal).map((r) => r.text);

  Future<bool> isAvailable() async {
    final available = await _methodChannel.invokeMethod<bool>('isAvailable');
    return available ?? false;
  }

  /// Arranca el reconocedor.
  ///
  /// Con [continuous] el lado nativo se rearranca solo tras los silencios, de
  /// modo que el micrófono sigue vivo durante una conversación. Tras cada
  /// resultado definitivo el control vuelve a Dart, que decide cuándo reabrir
  /// la escucha (normalmente después de que el agente termine de hablar).
  Future<void> startListening({bool continuous = false}) async {
    await _methodChannel.invokeMethod('startListening', {
      'continuous': continuous,
    });
  }

  Future<void> stopListening() async {
    await _methodChannel.invokeMethod('stopListening');
  }

  /// Escucha una sola frase y devuelve el texto definitivo.
  ///
  /// La suscripción al EventChannel se abre *antes* de arrancar el reconocedor:
  /// así el `StreamHandler` nativo ya tiene su `EventSink` cuando llegan los
  /// resultados. Lanza [TimeoutException] si no llega nada y propaga los
  /// [PlatformException] que emite el lado nativo.
  Future<String> listenOnce({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final completer = Completer<String>();

    // 1) Suscribirse primero.
    final subscription = results.listen(
      (result) {
        if (result.isFinal && !completer.isCompleted) {
          completer.complete(result.text);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    try {
      // 2) Y solo entonces arrancar la escucha nativa.
      await startListening();
      return await completer.future.timeout(timeout);
    } finally {
      try {
        await stopListening();
      } catch (_) {
        // best effort: si el canal ya falló, no hay nada que detener.
      }
      await subscription.cancel();
    }
  }

  static SttResult _parse(dynamic event) {
    if (event is Map) {
      return SttResult(
        text: (event['text'] as String?) ?? '',
        isFinal: (event['isFinal'] as bool?) ?? false,
      );
    }

    // Compatibilidad: si el nativo manda un String plano, se asume definitivo.
    return SttResult(text: event?.toString() ?? '', isFinal: true);
  }
}
