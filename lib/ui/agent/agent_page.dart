import 'package:flutter/material.dart';

import '../../features/call_agent/data/llm/local_llm_responder.dart';
import '../../features/call_agent/data/repositories_impl/rules_classifier_repository_impl.dart';
import '../../features/call_agent/domain/memory/memory_local_datasource.dart';
import '../../features/call_agent/domain/memory/memory_manager.dart';
import '../../features/call_agent/domain/memory/memory_repository_impl.dart';
import '../../features/call_agent/domain/usecases/classify_text.dart';
import '../../features/call_agent/presentation/controllers/agent_controller.dart';
import '../../features/call_logs/domain/repositories/call_log_repository.dart';
import '../../features/call_logs/domain/usecases/save_call_log.dart';
import '../../features/call_logs/domain/usecases/summarize_call.dart';
import '../../features/settings/presentation/settings_scope.dart';
import '../../shared/services/stt/stt_service.dart';
import '../../shared/services/tts/neural_tts_service.dart';
import '../../shared/services/llm/local_llm_service.dart';
import 'widgets/conversation_body.dart';

/// El agente atendiendo una llamada real. Se abre desde el servicio de
/// screening cuando entra un número desconocido.
class AgentPage extends StatefulWidget {
  final String number;
  final CallLogRepository callLogRepository;

  /// Descolgar la llamada al abrir. Lo trae `main.dart` desde los ajustes,
  /// porque el controlador se crea en `initState` y ahí todavía no se puede
  /// consultar `SettingsScope`.
  final bool autoAnswer;

  const AgentPage({
    super.key,
    required this.number,
    required this.callLogRepository,
    this.autoAnswer = true,
  });

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  late final AgentController _controller;

  @override
  void initState() {
    super.initState();

    final settings = SettingsScope.read(context).settings;

    final llm = settings.llmEnabled
        ? LocalLlmResponder(LocalLlmService.shared)
        : null;

    _controller = AgentController(
      stt: SttService(),
      tts: HybridTtsService(voiceProfile: settings.voiceProfile),
      classify: ClassifyText(RulesClassifierRepositoryImpl()),
      memory: MemoryManager(MemoryRepositoryImpl(MemoryLocalDatasource())),
      saveCallLog: SaveCallLog(widget.callLogRepository),
      summarizeCall: SummarizeCall(),
      autoAnswer: widget.autoAnswer,
      agentName: settings.agentName,
      agentCompany: settings.agentCompany,
      agentRole: settings.agentRole,
      agentPersonality: settings.agentPersonality,
      ownerName: settings.ownerName,
      ownerTitle: settings.ownerTitle,
      formality: settings.formality,
      llm: llm,
    );

    // La llamada ya está entrando: el agente contesta sin esperar al usuario.
    _controller.start(number: widget.number);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configuredName = SettingsScope.of(context).settings.agentName.trim();
    final agentName = configuredName.isEmpty ? 'SentraVox' : configuredName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Agente $agentName'),
            Text(
              'Número: ${widget.number}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ConversationBody(
          controller: _controller,
          controlsBuilder: (context) => Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _controller.isRunning
                      ? () => _controller.stop()
                      : null,
                  icon: const Icon(Icons.call_end),
                  label: const Text('Finalizar llamada'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
