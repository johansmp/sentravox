import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:llamadart/llamadart.dart';

import 'llm_service.dart';

/// LLM local basado en llama.cpp (`llamadart`).
///
/// El modelo va empaquetado en el APK y se copia una sola vez al almacenamiento
/// interno mediante un canal nativo. A partir de ahí todo es local: no hay
/// peticiones HTTP, no se necesita Wi-Fi ni datos, y el texto de la llamada no
/// sale del teléfono.
class LocalLlmService {
  static const String assetPath =
      'assets/models/Qwen3.5-0.8B-Q4_K_M.gguf';
  static const String modelName = 'Qwen3.5-0.8B-Q4_K_M.gguf';

  /// Una sola instancia por proceso: el modelo tarda varios segundos en cargar
  /// y la app lo reutiliza entre llamadas y desde Configuración.
  static final LocalLlmService shared = LocalLlmService();

  static const MethodChannel _channel = MethodChannel('sentravox/local_llm');

  LlamaEngine? _engine;
  Future<void>? _loading;
  String? _lastError;

  bool get isLoaded => _engine != null;
  String? get lastError => _lastError;

  /// Copia el modelo empaquetado al almacenamiento interno si hace falta.
  Future<Map<String, Object?>> prepareModel() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'prepareModel',
        {'asset': assetPath, 'name': modelName},
      );
      if (result == null) {
        throw StateError('El canal nativo no devolvió el estado del modelo.');
      }
      return result.map((key, value) => MapEntry(key.toString(), value));
    } on MissingPluginException {
      throw StateError('La copia nativa del modelo no está disponible.');
    } on PlatformException catch (e) {
      throw StateError(e.message ?? 'No se pudo preparar el modelo local.');
    }
  }

  Future<Map<String, Object?>> modelStatus() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'modelStatus',
        {'name': modelName},
      );
      if (result == null) return const {};
      return result.map((key, value) => MapEntry(key.toString(), value));
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  /// Carga el motor una sola vez. Varias llamadas concurrentes esperan la
  /// misma carga en lugar de duplicarla.
  Future<void> ensureLoaded() {
    if (_engine != null) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    _lastError = null;

    final status = await prepareModel();
    final path = (status['path'] as String?) ?? '';
    if (path.isEmpty) {
      throw StateError('El modelo local no tiene una ruta válida.');
    }

    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.setModel(
        LlamaModel(ModelSource.path(path)),
        params: const ModelParams(
          // CPU: es la opción más compatible entre fabricantes y emuladores.
          gpuLayers: 0,
          contextSize: 1024,
        ),
      );
      _engine = engine;
    } catch (e) {
      _lastError = 'No se pudo cargar el modelo local: $e';
      await engine.dispose();
      rethrow;
    }
  }

  /// Genera una respuesta. Devuelve `null` si el modelo no está listo o falla,
  /// para que el guion local siga funcionando sin cortar la llamada.
  Future<String?> complete({
    required String systemPrompt,
    required String userPrompt,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final watch = Stopwatch()..start();
    try {
      // La carga inicial puede tardar; el timeout cubre el turno completo.
      final reply = await _complete(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      ).timeout(timeout);
      debugPrint(
        'LocalLlm: generación en ${watch.elapsedMilliseconds} ms '
        '(timeout ${timeout.inSeconds}s)',
      );
      return reply;
    } on TimeoutException {
      _lastError = 'El modelo local tardó más de ${timeout.inSeconds} s.';
      debugPrint(_lastError);
      return null;
    } catch (e) {
      _lastError = 'Fallo del modelo local: $e';
      debugPrint(_lastError);
      return null;
    }
  }

  Future<String?> _complete({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    await ensureLoaded();
    final engine = _engine;
    if (engine == null) return null;

    // Una sesión nueva por turno: el contexto lo lleva el guion local, no el
    // modelo, así que no arrastramos historial entre llamadas.
    final session = ChatSession(
      engine,
      systemPrompt: systemPrompt,
      maxContextTokens: 1024,
    );

    final reply = await session.send(
      userPrompt,
      params: const GenerationParams(
        maxTokens: 48,
        temp: 0.15,
        topK: 20,
        topP: 0.8,
        penalty: 1.05,
      ),
      enableThinking: false,
    );

    debugPrint('LocalLlm raw: "${reply.text}"');
    return LlmService.sanitize(reply.text);
  }

  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await engine.dispose();
    }
  }
}
