import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Configuración del modo de IA avanzada.
///
/// Es opcional y está desactivado por defecto: la app funciona entera sin red.
/// Cuando se activa, solo se envía el texto del turno actual y los datos ya
/// extraídos, nunca audio ni la grabación de la llamada.
class LlmConfig {
  final bool enabled;
  final String endpoint;
  final String model;
  final String apiKey;
  final Duration timeout;

  const LlmConfig({
    this.enabled = false,
    this.endpoint = 'https://api.openai.com/v1/chat/completions',
    this.model = 'gpt-4o-mini',
    this.apiKey = '',
    this.timeout = const Duration(seconds: 4),
  });

  bool get usable =>
      enabled && apiKey.trim().isNotEmpty && endpoint.trim().isNotEmpty;
}

/// Cliente mínimo para APIs compatibles con OpenAI Chat Completions.
///
/// No añade dependencias: usa `dart:io`. Devuelve `null` ante cualquier fallo
/// —sin red, clave inválida, timeout, respuesta rara— para que el llamador
/// caiga al guion local sin romper la llamada.
class LlmService {
  final LlmConfig config;

  /// Permite inyectar un cliente en pruebas.
  final HttpClient Function()? clientFactory;

  const LlmService({
    required this.config,
    this.clientFactory,
  });

  Future<String?> complete({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    if (!config.usable || kIsWeb) return null;

    final uri = Uri.tryParse(config.endpoint.trim());
    if (uri == null || uri.host.isEmpty) return null;

    // Nunca se manda una clave por HTTP plano salvo a un modelo local.
    if (uri.scheme != 'https' && !_isLocalHost(uri.host)) return null;

    final client = (clientFactory ?? HttpClient.new)()
      ..connectionTimeout = config.timeout;

    try {
      final request = await client.postUrl(uri).timeout(config.timeout);

      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader,
          'Bearer ${config.apiKey.trim()}');
      request.write(jsonEncode({
        'model': config.model.trim().isEmpty ? 'gpt-4o-mini' : config.model.trim(),
        'temperature': 0.3,
        'max_tokens': 180,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      }));

      final response = await request.close().timeout(config.timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(config.timeout);
      return sanitize(_extractContent(body));
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static bool _isLocalHost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '10.0.2.2' ||
        h.startsWith('192.168.') ||
        h.startsWith('10.') ||
        h.endsWith('.local');
  }

  static String? _extractContent(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;

      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;

      final first = choices.first;
      if (first is! Map) return null;

      final message = first['message'];
      if (message is Map) {
        final content = message['content'];
        if (content is String) return content;
      }

      // Algunos proveedores devuelven `text` en vez de `message.content`.
      final text = first['text'];
      return text is String ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// Deja solo lo que se puede decir en voz alta.
  static String? sanitize(String? raw) {
    if (raw == null) return null;

    var text = raw.trim();
    if (text.isEmpty) return null;

    // Markdown, comillas y prefijos típicos de un chatbot.
    text = text
        .replaceAll(RegExp(r'```[a-zA-Z]*'), '')
        .replaceAll('```', '')
        .replaceAll(RegExp(r'^\s*(?:asistente|agente|respuesta)\s*:\s*',
            caseSensitive: false), '')
        .replaceAll(RegExp(r"^[\x22“”']+|[\x22“”']+$"), '')
        .replaceAll(RegExp(r'[*_#>`]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isEmpty) return null;

    // Una respuesta de voz no debe ser un párrafo: se corta en la segunda
    // frase completa, o a 320 caracteres.
    final sentences = RegExp(r'[^.!?¡¿]+[.!?]+')
        .allMatches(text)
        .map((m) => m.group(0)!.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (sentences.length >= 2) {
      text = '${sentences[0]} ${sentences[1]}';
    } else if (text.length > 320) {
      text = '${text.substring(0, 320).trimRight()}…';
    }

    return text.isEmpty ? null : text;
  }
}
