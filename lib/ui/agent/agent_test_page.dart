import 'package:flutter/material.dart';

import '../../features/call_agent/presentation/controllers/call_simulation_controller.dart';
import '../../features/call_logs/domain/usecases/summarize_call.dart';
import '../../features/settings/presentation/settings_scope.dart';
import '../../shared/services/nlp/nlp_service.dart';
import '../../shared/services/stt/stt_service.dart';
import '../../shared/services/tts/neural_tts_service.dart';
import 'widgets/conversation_body.dart';
import 'widgets/simulation_controls.dart';

/// Simulación completa de una llamada: escucha continua, transcripción parcial
/// y definitiva, intención y respuesta por turno, y un panel de contexto que
/// resume la llamada mientras ocurre.
class AgentTestPage extends StatefulWidget {
  const AgentTestPage({super.key});

  @override
  State<AgentTestPage> createState() => _AgentTestPageState();
}

class _AgentTestPageState extends State<AgentTestPage> {
  late final CallSimulationController _controller;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();

    final settings = SettingsScope.read(context).settings;

    _controller = CallSimulationController(
      stt: SttService(),
      tts: HybridTtsService(voiceProfile: settings.voiceProfile),
      nlp: NlpService(),
      summarizeCall: SummarizeCall(),
      agentName: settings.agentName,
      agentCompany: settings.agentCompany,
      agentRole: settings.agentRole,
      agentPersonality: settings.agentPersonality,
      ownerName: settings.ownerName,
      ownerTitle: settings.ownerTitle,
      formality: settings.formality,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isEmpty || !_controller.isRunning) return;

    _textController.clear();
    _controller.submitText(text);
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
            const Text('Simulación de llamada'),
            Text(
              'Agente $agentName',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ConversationBody(
          controller: _controller,
          controlsBuilder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SimulationControls(
                isRunning: _controller.isRunning,
                onStart: _controller.start,
                onStop: _controller.stop,
              ),
              if (_controller.isTextMode) ...[
                const SizedBox(height: 6),
                Text(
                  'Modo texto: el micrófono está desactivado.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      enabled: _controller.isRunning &&
                          !_controller.isProcessingTurn,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText: 'Escribir mensaje si el micrófono falla',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Enviar mensaje',
                    onPressed: _controller.isRunning &&
                            !_controller.isProcessingTurn
                        ? _sendText
                        : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
