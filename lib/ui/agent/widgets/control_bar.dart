import 'package:flutter/material.dart';
import 'package:sentravox/features/call_agent/presentation/controllers/agent_controller.dart';

class ControlBar extends StatelessWidget {
  final AgentController controller;

  const ControlBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: () => controller.stop(),
            child: const Text("Detener agente"),
          ),
        ),
      ],
    );
  }
}
