import 'package:flutter/material.dart';
import '../../features/call_logs/domain/entities/call_log.dart';

class CallLogCard extends StatelessWidget {
  final CallLogEntry log;
  final VoidCallback onTap;

  const CallLogCard({
    super.key,
    required this.log,
    required this.onTap,
  });

  Color _riskColor(double risk) {
    if (risk >= 0.8) return Colors.redAccent;
    if (risk >= 0.5) return Colors.orangeAccent;
    return Colors.green;
  }

  IconData _outcomeIcon() {
    if (log.wasBlocked) return Icons.block;
    switch (log.outcome) {
      case CallOutcome.agent:
        return Icons.smart_toy_outlined;
      case CallOutcome.flaggedHighRisk:
        return Icons.warning_amber_rounded;
      case CallOutcome.skippedDisabled:
        return Icons.shield_outlined;
      default:
        return Icons.phone;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _riskColor(log.risk);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(_outcomeIcon(), color: Colors.white),
        ),
        title: Text(log.number),
        subtitle: Text(
          '${CallOutcome.label(log.outcome)} • ${log.intent}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${(log.risk * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            Text(
              _formatTime(log.timestamp),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }
}
