import 'package:flutter/material.dart';
import 'package:sentravox/features/call_agent/domain/fsm/agent_fsm.dart';

class AgentStateIndicator extends StatelessWidget {
  final AgentState state;
  final double risk;

  const AgentStateIndicator({
    super.key,
    required this.state,
    required this.risk,
  });

  Color _stateColor(BuildContext context) {
    switch (state) {
      case AgentState.listening:
        return Colors.blueAccent;
      case AgentState.analyzing:
        return Colors.orangeAccent;
      case AgentState.responding:
        return Colors.green;
      case AgentState.blocking:
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  String _stateLabel() {
    switch (state) {
      case AgentState.intro:
        return "Presentándose";
      case AgentState.listening:
        return "Escuchando…";
      case AgentState.analyzing:
        return "Analizando…";
      case AgentState.responding:
        return "Respondiendo…";
      case AgentState.blocking:
        return "Bloqueando llamada";
      case AgentState.closing:
        return "Finalizando";
      default:
        return "Inactivo";
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.1),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _stateLabel(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text(
            "Riesgo: ${(risk * 100).toStringAsFixed(0)}%",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
