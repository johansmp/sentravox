import 'dart:async';

import 'package:flutter/services.dart';

class TtsService {
  static const MethodChannel _channel = MethodChannel('sentravox/tts');

  /// Prepara el motor en segundo plano al empezar una llamada.
  ///
  /// El TTS del sistema no necesita preparación; la implementación neuronal la
  /// usa para cargar el modelo sin bloquear el saludo.
  Future<void> warmUp() async {}

  /// Habla y espera a que el motor termine.
  ///
  /// Devuelve `true` si la locución se completó y `false` si fue interrumpida
  /// (por otro `speak`, por [stop] o por agotarse [timeout]). Esperar el final
  /// es lo que permite reabrir el micrófono sin transcribir la voz del agente.
  Future<bool> speak(
    String text, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      final completed = await _channel
          .invokeMethod<bool>('speak', {'text': text})
          .timeout(timeout);
      return completed ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } on MissingPluginException {
      // Plataforma sin TTS nativo.
    } on PlatformException {
      // El motor ya pudo haberse liberado.
    }
  }

  /// Reproduce un WAV ya sintetizado (TTS neuronal local).
  ///
  /// Espera a que termine la reproducción, igual que [speak], para que el bucle
  /// no reabra el micrófono mientras el agente habla.
  Future<bool> speakWav(
    String path, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final completed = await _channel
          .invokeMethod<bool>('speakWav', {'path': path})
          .timeout(timeout);
      return completed ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> isSpeaking() async {
    try {
      final speaking = await _channel.invokeMethod<bool>('isSpeaking');
      return speaking ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Voces españolas que ofrece el motor TTS del dispositivo.
  ///
  /// El nombre es el identificador estable que se guarda en `voice_id`.
  Future<List<Map<String, Object?>>> voices() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('voices');
      if (raw == null) return const [];

      return raw
          .whereType<Map<Object?, Object?>>()
          .map((voice) => <String, Object?>{
                'name': voice['name']?.toString() ?? '',
                'locale': voice['locale']?.toString() ?? '',
                'quality': voice['quality'],
                'network': voice['network'] == true,
                'gender': voice['gender']?.toString() ?? 'desconocida',
              })
          .where((voice) => (voice['name'] as String).isNotEmpty)
          .toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Estado real de la ruta de audio del TTS durante una llamada.
  Future<Map<String, Object?>> audioDiagnostics() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'audioDiagnostics',
      );
      if (raw == null) return const {};
      return raw.map((key, value) => MapEntry(key.toString(), value));
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }
}
