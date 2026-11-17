import 'package:flutter/widgets.dart';

import 'controllers/settings_controller.dart';

/// Hace visible el [SettingsController] en todo el árbol.
///
/// `InheritedNotifier` ya reconstruye a quien dependa de él cuando el
/// controlador notifica, así que el interruptor de seguridad queda coherente en
/// todas las pantallas sin paquetes de gestión de estado.
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({
    super.key,
    required SettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Se reconstruye con cada cambio de ajustes.
  static SettingsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(
      scope?.notifier != null,
      'No se encontró un SettingsScope: envuelve la app con SettingsScope.',
    );
    return scope!.notifier!;
  }

  /// Acceso sin suscripción, para callbacks que solo escriben.
  static SettingsController read(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<SettingsScope>();
    assert(
      scope?.notifier != null,
      'No se encontró un SettingsScope: envuelve la app con SettingsScope.',
    );
    return scope!.notifier!;
  }
}
