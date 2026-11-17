import 'package:sentravox/features/call_agent/domain/dialogue/agent_persona.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/caller_facts.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/dialogue_engine.dart';
import 'package:sentravox/shared/services/llm/local_llm_service.dart';

import 'llm_responder.dart';

/// Reescribe la respuesta del guion con el modelo **local**.
///
/// El modelo nunca decide el flujo: recibe la respuesta que el guion ya
/// calculó y solo la reformula. Si no está cargado, tarda o devuelve algo que
/// rompe el turno, el controlador sigue con el texto local.
class LocalLlmResponder extends LlmResponder {
  final LocalLlmService service;

  /// Si es true, [dispose] libera el motor. El agente usa la instancia
  /// compartida y no debe descargarla al cerrar una llamada.
  final bool disposeService;

  LocalLlmResponder(this.service, {this.disposeService = false});

  @override
  Future<void> warmUp() => service.ensureLoaded().catchError((Object _) {});

  @override
  Future<String?> rewrite({
    required AgentPersona persona,
    required CallerFacts facts,
    required ScreeningStage stage,
    required String transcript,
    required String localDraft,
    required double risk,
  }) async {
    // Para el modelo local se usa un prompt corto: el guion ya lleva el perfil
    // y los datos, y un prompt largo dispara el tiempo de prefill.
    final systemPrompt = LlmPromptBuilder.localSystemPrompt(persona);

    final userPrompt = LlmPromptBuilder.buildLocal(
      transcript: transcript,
      localDraft: localDraft,
    );

    final raw = await service.complete(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
    );

    if (raw == null) return null;
    return LlmPromptBuilder.isUsableRewrite(localDraft, raw) ? raw : null;
  }

  @override
  Future<void> dispose() async {
    if (disposeService) await service.dispose();
  }
}
