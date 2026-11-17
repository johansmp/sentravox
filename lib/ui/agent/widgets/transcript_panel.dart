import 'package:flutter/material.dart';

// ignore: unused_element
class TranscriptPanel extends StatelessWidget {
  final String text;

  const TranscriptPanel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Transcripción en tiempo real",
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            text.isEmpty ? "Esperando audio…" : text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
