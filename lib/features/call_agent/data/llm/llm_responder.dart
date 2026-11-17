import 'package:sentravox/features/call_agent/domain/dialogue/agent_persona.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/caller_facts.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/dialogue_engine.dart';
import 'package:sentravox/shared/services/llm/llm_service.dart';

/// Punto de extensión para la IA avanzada.
///
/// Se abstrae para poder probar el controlador sin red y para que el guion
/// local siga siendo obligatorio: si esto devuelve `null`, la llamada continúa
/// con la respuesta determinista.
abstract class LlmResponder {
  /// Prepara el modelo en segundo plano al empezar una llamada.
  Future<void> warmUp() async {}

  Future<String?> rewrite({
    required AgentPersona persona,
    required CallerFacts facts,
    required ScreeningStage stage,
    required String transcript,
    required String localDraft,
    required double risk,
  });

  /// Libera recursos nativos al terminar la llamada.
  Future<void> dispose() async {}
}

/// Implementación real: OpenAI-compatible Chat Completions.
class LlmServiceResponder extends LlmResponder {
  final LlmService service;

  LlmServiceResponder(this.service);

  @override
  Future<String?> rewrite({
    required AgentPersona persona,
    required CallerFacts facts,
    required ScreeningStage stage,
    required String transcript,
    required String localDraft,
    required double risk,
  }) {
    if (!service.config.usable) return Future.value(null);

    return service.complete(
      systemPrompt: persona.systemPrompt,
      userPrompt: LlmPromptBuilder.build(
        facts: facts,
        stage: stage,
        transcript: transcript,
        localDraft: localDraft,
        risk: risk,
      ),
    );
  }
}

/// Construye el turno de usuario que se le da al modelo.
///
/// Es puro y determinista para poder probarlo: el prompt debe contener los
/// datos ya extraídos y la respuesta local como guía, de modo que el modelo
/// reformule sin inventar ni cambiar la intención del guion.
class LlmPromptBuilder {
  const LlmPromptBuilder._();

  static String build({
    required CallerFacts facts,
    required ScreeningStage stage,
    required String transcript,
    required String localDraft,
    required double risk,
  }) {
    final known = <String>[
      if (facts.hasName) 'nombre: ${facts.name}',
      if (facts.hasCompany) 'empresa: ${facts.company}',
      if (facts.hasPurpose) 'motivo: ${facts.purpose}',
      if (facts.hasCallback) 'teléfono de devolución: ${facts.callback}',
    ];

    return 'Etapa del guion: ${stage.name}. '
        'Riesgo estimado: ${(risk * 100).toStringAsFixed(0)}%. '
        'Datos ya confirmados: ${known.isEmpty ? 'ninguno' : known.join('; ')}. '
        'El interlocutor acaba de decir: "$transcript". '
        'El guion local respondería: "$localDraft". '
        'Reformula esa respuesta para que suene natural, breve y en español de '
        'Colombia. Conserva exactamente la misma intención y la misma pregunta '
        'pendiente; no añadas preguntas nuevas, no inventes datos, no cierres '
        'la llamada y no recites el guion. Si te preguntan si eres una persona '
        'o una IA, di con honestidad que eres un asistente virtual; nunca '
        'finjas ser el titular.';
  }

  /// Sistema compacto para el modelo local.
  ///
  /// No repite todo el perfil: el guion ya lo aplicó a [localDraft]. Así el
  /// prefill es corto y la respuesta llega en un tiempo usable durante una
  /// llamada.
  static String localSystemPrompt(AgentPersona persona) {
    return 'Eres ${persona.displayName}, un asistente telefónico en español de '
        'Colombia. Reescribe la respuesta sugerida en una sola frase breve, '
        'manteniendo la misma pregunta. No inventes datos, no pidas claves ni '
        'datos bancarios y no cierres la llamada.';
  }

  /// Prompt de usuario compacto para el modelo local.
  static String buildLocal({
    required String transcript,
    required String localDraft,
  }) {
    return 'El interlocutor dijo: "$transcript". '
        'Respuesta sugerida: "$localDraft". '
        'Reescríbela más natural, en una sola frase breve y en español de '
        'Colombia, sin cambiar la intención ni la pregunta. No inventes datos '
        'ni cierres la llamada.';
  }

  /// Rechaza una respuesta del LLM que rompería el turno.
  ///
  /// El guion local siempre termina en pregunta o cierra. Si el modelo convierte
  /// una pregunta en una afirmación, la llamada se queda esperando y el
  /// interlocutor no sabe qué contestar. También se descartan las respuestas
  /// largas y las típicas evasivas de chatbot.
  static bool isUsableRewrite(String localDraft, String candidate) {
    final text = candidate.trim();
    if (text.isEmpty || text.length > 360) return false;

    if (localDraft.contains('?') && !text.contains('?')) return false;

    final lower = text.toLowerCase();

    // Nunca dejar que el modelo invente un dato sensible ni un teléfono que el
    // interlocutor no haya dicho. El guion local ya tiene los datos extraídos;
    // si el número no está ahí, no se dice.
    const forbidden = [
      'clave', 'contraseña', 'contrasena', 'código de verificación',
      'codigo de verificacion', 'cvv', 'pin', 'número de tarjeta',
      'numero de tarjeta', 'datos bancarios',
    ];
    if (forbidden.any(lower.contains)) return false;

    for (final match in RegExp(r'\d[\d\s\-().]{5,}\d').allMatches(text)) {
      if (!localDraft.contains(match.group(0)!)) return false;
    }

    if (lower.contains('como modelo') ||
        lower.contains('no puedo ayudar') ||
        lower.contains('no puedo responder') ||
        lower.contains('openai') ||
        lower.contains('lenguaje de inteligencia')) {
      return false;
    }

    return true;
  }
}
