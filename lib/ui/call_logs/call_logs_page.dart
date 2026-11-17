import 'package:flutter/material.dart';
import '../../features/call_logs/domain/entities/call_log.dart';
import '../../features/call_logs/domain/usecases/get_call_logs.dart';
import 'call_log_card.dart';
import 'call_log_details_page.dart';

class CallLogsPage extends StatefulWidget {
  final GetCallLogs getCallLogs;

  const CallLogsPage({super.key, required this.getCallLogs});

  @override
  State<CallLogsPage> createState() => _CallLogsPageState();
}

class _CallLogsPageState extends State<CallLogsPage> {
  late Future<List<CallLogEntry>> _logsFuture;

  @override
  void initState() {
    super.initState();
    _logsFuture = widget.getCallLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Historial de llamadas"),
      ),
      body: FutureBuilder<List<CallLogEntry>>(
        future: _logsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snapshot.data!;

          if (logs.isEmpty) {
            return const Center(
              child: Text("No hay llamadas registradas"),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return CallLogCard(
                log: log,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallLogDetailsPage(log: log),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
