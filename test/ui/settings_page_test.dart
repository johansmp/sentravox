import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/settings/domain/entities/app_settings.dart';
import 'package:sentravox/features/settings/domain/repositories/settings_repository.dart';
import 'package:sentravox/features/settings/presentation/controllers/settings_controller.dart';
import 'package:sentravox/features/settings/presentation/settings_scope.dart';
import 'package:sentravox/ui/settings/settings_page.dart';

class _FakeSettingsRepository implements SettingsRepository {
  AppSettings settings = const AppSettings(
    agentName: 'Alejandro',
    agentCompany: 'Innovatech',
    agentRole: 'recepcionista',
    ownerName: 'Carlos',
    formality: 'amable',
  );

  @override
  Future<AppSettings> load() async => settings;

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
  testWidgets('Configuración muestra el perfil y la vista previa del saludo',
      (tester) async {
    final controller = SettingsController(_FakeSettingsRepository());
    addTearDown(controller.dispose);

    await controller.load();
    await tester.pumpWidget(
      SettingsScope(
        controller: controller,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    // Deja terminar la carga de permisos y el reintento de voces.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('Configuración'), findsOneWidget);
    expect(find.text('Protección activa'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Perfil del agente (prompt engine)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Perfil del agente (prompt engine)'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Vista previa del saludo'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Vista previa del saludo'), findsOneWidget);
    expect(
      find.textContaining('Hola, soy el asistente virtual de Alejandro'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Voz del agente'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Voz del agente'), findsOneWidget);
    expect(find.text('Perfil de voz (5 opciones)'), findsOneWidget);
  });
}
