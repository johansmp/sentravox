import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_logs/domain/entities/call_log.dart';
import 'package:sentravox/features/call_logs/domain/repositories/call_log_repository.dart';
import 'package:sentravox/features/settings/domain/entities/app_settings.dart';
import 'package:sentravox/features/settings/domain/repositories/settings_repository.dart';
import 'package:sentravox/features/settings/presentation/controllers/settings_controller.dart';
import 'package:sentravox/features/settings/presentation/settings_scope.dart';
import 'package:sentravox/shared/navigation/route_observer.dart';
import 'package:sentravox/ui/home_page.dart';

class _FakeCallLogs implements CallLogRepository {
  final List<CallLogEntry> logs = [];
  int reads = 0;

  @override
  Future<List<CallLogEntry>> getAll() async {
    reads++;
    return List<CallLogEntry>.of(logs);
  }

  @override
  Future<void> save(CallLogEntry entry) async => logs.add(entry);
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> setBoolean(String key, bool value) async {}

  @override
  Future<void> setDouble(String key, double value) async {}

  @override
  Future<void> setString(String key, String value) async {}

  @override
  Future<List<String>> blocklist() async => const [];

  @override
  Future<void> setBlocklist(List<String> numbers) async {}
}

void main() {
  testWidgets('el inicio recarga las llamadas al volver de otra pantalla',
      (tester) async {
    final logs = _FakeCallLogs();
    final controller = SettingsController(_FakeSettingsRepository());
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      SettingsScope(
        controller: controller,
        child: MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: HomePage(callLogRepository: logs),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin llamadas analizadas hoy'), findsOneWidget);

    // Una llamada terminó mientras había otra ruta encima del inicio.
    logs.logs.add(
      CallLogEntry(
        number: '3001234567',
        transcript: 'Agente: hola',
        intent: 'sin_intencion',
        risk: 0,
        summary: 'Llamada atendida por el agente.',
        timestamp: DateTime.now(),
      ),
    );

    final navigator = Navigator.of(tester.element(find.byType(HomePage)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('otra pantalla')),
      ),
    );
    await tester.pumpAndSettle();

    navigator.pop();
    await tester.pumpAndSettle();

    // Antes los contadores solo se cargaban al arrancar y al abrir el
    // historial: al volver de una llamada seguían en cero.
    expect(find.text('1 llamada analizada hoy'), findsOneWidget);
  });
}
