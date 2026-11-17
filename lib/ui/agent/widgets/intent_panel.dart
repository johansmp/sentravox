import 'package:flutter/material.dart';

// ignore: unused_element
class IntentPanel extends StatelessWidget {
  final String intent;
  final double risk;

  const IntentPanel({
    super.key,
    required this.intent,
    required this.risk,
  });

  @override
  Widget build(BuildContext context) {
    final label = intent.isEmpty ? "Sin intención detectada" : intent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        children: [
          Icon(Icons.psychology, color: Colors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Intención detectada",
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
