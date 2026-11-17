import 'package:flutter/material.dart';

class SimulationControls extends StatelessWidget {
  final bool isRunning;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const SimulationControls({
    super.key,
    required this.isRunning,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: isRunning ? null : onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Iniciar llamada'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isRunning ? onStop : null,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Detener'),
          ),
        ),
      ],
    );
  }
}
