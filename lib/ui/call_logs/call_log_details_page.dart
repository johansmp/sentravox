import 'package:flutter/material.dart';
import '../../features/call_logs/domain/entities/call_log.dart';

class CallLogDetailsPage extends StatelessWidget {
  final CallLogEntry log;

  const CallLogDetailsPage({super.key, required this.log});

  Color _riskColor(double risk) {
    if (risk >= 0.8) return Colors.redAccent;
    if (risk >= 0.5) return Colors.orangeAccent;
    return Colors.green;
  }

  /// Distingue una llamada filtrada antes de contestar de una atendida en la
  /// que el interlocutor no llegó a hablar. Antes ambas decían «se filtró antes
  /// de contestar», lo que hacía pensar que el agente no había intervenido.
  String _emptyTranscriptMessage() {
    const answered = {
      CallOutcome.agent,
      CallOutcome.blockedByAgent,
      CallOutcome.flaggedHighRisk,
    };

    if (answered.contains(log.outcome)) {
      return 'El agente atendió la llamada, pero no se registró voz del '
          'interlocutor.';
    }
    return 'La llamada se filtró antes de contestar, no hay transcripción.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Detalles de llamada"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            ListTile(
              leading: Icon(Icons.phone, color: _riskColor(log.risk)),
              title: Text(log.number),
              subtitle: Text(log.timestamp.toLocal().toString()),
            ),
            const SizedBox(height: 16),

            Text("Resultado",
                style: Theme.of(context).textTheme.titleMedium),
            Text(CallOutcome.label(log.outcome)),
            const SizedBox(height: 16),

            Text("Intención detectada",
                style: Theme.of(context).textTheme.titleMedium),
            Text(log.intent),
            const SizedBox(height: 16),

            Text("Nivel de riesgo",
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              "${(log.risk * 100).toStringAsFixed(0)}%",
              style: TextStyle(
                color: _riskColor(log.risk),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            Text("Resumen automático",
                style: Theme.of(context).textTheme.titleMedium),
            Text(log.summary),
            const SizedBox(height: 16),

            Text("Transcripción completa",
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              log.transcript.trim().isEmpty
                  ? _emptyTranscriptMessage()
                  : log.transcript,
            ),
          ],
        ),
      ),
    );
  }
}
