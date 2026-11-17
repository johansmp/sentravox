import 'package:flutter/material.dart';

import '../../../features/call_agent/domain/conversation/conversation_summarizer.dart';
import 'risk_palette.dart';

/// Panel de contexto: resume la llamada completa mientras ocurre.
class ConversationContextPanel extends StatelessWidget {
  final ConversationSummary summary;
  final String? closingSummary;

  const ConversationContextPanel({
    super.key,
    required this.summary,
    this.closingSummary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = RiskPalette.forLevel(context, summary.level);
    final hasDetail = summary.keyMoments.isNotEmpty || closingSummary != null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_outlined, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Contexto de la conversación',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    RiskPalette.label(summary.level),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(summary.headline, style: theme.textTheme.bodyMedium),
            if (summary.details.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: summary.details
                    .map((detail) => _DetailChip(detail: detail))
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.flag_outlined, size: 15, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    summary.recommendation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (hasDetail)
              Theme(
                // Quita las líneas divisorias por defecto del ExpansionTile.
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    'Detalle del análisis',
                    style: theme.textTheme.labelLarge,
                  ),
                  children: [
                    if (summary.keyMoments.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Momentos de mayor riesgo',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...summary.keyMoments.map((turn) {
                              final risk = turn.risk ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 5),
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: RiskPalette.forRisk(
                                            context, risk),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '«${turn.text}» — ${turn.intent ?? "?"} '
                                        '(${RiskPalette.percent(risk)})',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    if (closingSummary != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          closingSummary!.trim(),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final SummaryDetail detail;

  const _DetailChip({required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${detail.label}: ',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            TextSpan(
              text: detail.value,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
