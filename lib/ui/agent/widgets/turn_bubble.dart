import 'package:flutter/material.dart';

import '../../../features/call_agent/domain/conversation/conversation_turn.dart';
import 'risk_palette.dart';

/// Una intervención de la conversación. El interlocutor a la izquierda con su
/// intención y riesgo; el agente a la derecha.
class TurnBubble extends StatelessWidget {
  final ConversationTurn turn;

  const TurnBubble({super.key, required this.turn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCaller = turn.isCaller;

    final background = isCaller
        ? scheme.surfaceContainerHighest
        : scheme.primaryContainer;
    final foreground =
        isCaller ? scheme.onSurface : scheme.onPrimaryContainer;

    return Align(
      alignment: isCaller ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isCaller ? 4 : 16),
            bottomRight: Radius.circular(isCaller ? 16 : 4),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isCaller ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(
              isCaller ? 'Interlocutor' : 'SentraVox',
              style: theme.textTheme.labelSmall?.copyWith(
                color: foreground.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              turn.text,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
            if (turn.intent != null || turn.risk != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: isCaller ? WrapAlignment.start : WrapAlignment.end,
                children: [
                  if (turn.intent != null)
                    _Tag(
                      label: turn.intent!,
                      color: scheme.primary,
                    ),
                  if (turn.risk != null)
                    _Tag(
                      label: 'riesgo ${RiskPalette.percent(turn.risk!)}',
                      color: RiskPalette.forRisk(context, turn.risk!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
