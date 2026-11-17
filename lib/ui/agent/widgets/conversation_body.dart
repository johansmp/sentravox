import 'package:flutter/material.dart';

import '../../../features/call_agent/domain/fsm/agent_fsm.dart';
import '../../../features/call_agent/presentation/controllers/conversation_loop_controller.dart';
import 'agent_state_indicator.dart';
import 'conversation_context_panel.dart';
import 'conversation_view.dart';

/// Cuerpo compartido por la simulación y la llamada real: estado del agente,
/// avisos, conversación, panel de contexto y los controles que aporte cada
/// pantalla.
class ConversationBody extends StatelessWidget {
  final ConversationLoopController controller;
  final Widget Function(BuildContext context) controlsBuilder;

  const ConversationBody({
    super.key,
    required this.controller,
    required this.controlsBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final summary = controller.summary();

        // El panel no debe comerse la pantalla en horizontal ni en pantallas
        // cortas: se limita a una fracción del alto disponible.
        final panelMaxHeight =
            (MediaQuery.sizeOf(context).height * 0.32).clamp(120.0, 260.0);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              AgentStateIndicator(
                state: controller.state,
                risk: controller.context.latestRisk ?? 0,
              ),
              if (controller.state == AgentState.analyzing)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (controller.notice != null)
                _Banner(
                  message: controller.notice!,
                  icon: Icons.info_outline,
                  background: scheme.secondaryContainer,
                  foreground: scheme.onSecondaryContainer,
                ),
              if (controller.error != null)
                _Banner(
                  message: controller.error!,
                  icon: Icons.error_outline,
                  background: scheme.errorContainer,
                  foreground: scheme.onErrorContainer,
                ),
              const SizedBox(height: 8),
              Expanded(
                child: ConversationView(
                  turns: controller.context.turns,
                  livePartial: controller.livePartial,
                  isListening: controller.state == AgentState.listening,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: panelMaxHeight),
                child: SingleChildScrollView(
                  child: ConversationContextPanel(
                    summary: summary,
                    closingSummary: controller.closingSummary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              controlsBuilder(context),
            ],
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color background;
  final Color foreground;

  const _Banner({
    required this.message,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }
}
