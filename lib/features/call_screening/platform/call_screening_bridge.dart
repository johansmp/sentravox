import 'package:flutter/services.dart';

/// Canal de screening de llamadas, en los dos sentidos.
///
/// Nativo → Dart: `activate_agent` cuando entra un desconocido que debe atender
/// el agente, y `screening_message` para reflejarlo en la UI.
///
/// Dart → nativo: `drainEvents` recoge los eventos que el servicio encoló
/// mientras no había app viva (llamadas filtradas con SentraVox cerrado) y
/// `consumePendingActivation` recoge la llamada que debía atender el agente.
class PendingActivation {
  final String number;
  final double risk;
  final DateTime at;

  const PendingActivation({
    required this.number,
    required this.risk,
    required this.at,
  });

  /// Una activación caducada no se atiende: la llamada ya terminó.
  bool isFresh(DateTime now, {Duration window = const Duration(seconds: 90)}) =>
      now.difference(at) <= window && !now.isBefore(at);
}

class CallScreeningBridge {
  static const MethodChannel _channel =
      MethodChannel('sentravox/call_screening');

  const CallScreeningBridge();

  /// Registra los callbacks nativos. Llamar una sola vez al arrancar.
  void attach({
    required void Function(String number, double risk) onActivateAgent,
    void Function(String number, double risk, String message)?
        onScreeningMessage,
  }) {
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      final map = args is Map ? args : const <Object?, Object?>{};

      final number = (map['number'] as String?) ?? 'desconocido';
      final risk = (map['risk'] as num?)?.toDouble() ?? 0;

      switch (call.method) {
        case 'activate_agent':
          onActivateAgent(number, risk);
          return null;
        case 'screening_message':
          onScreeningMessage?.call(
            number,
            risk,
            (map['message'] as String?) ?? '',
          );
          return null;
        default:
          throw MissingPluginException(
            'Método de screening no soportado: ${call.method}',
          );
      }
    });
  }

  void detach() => _channel.setMethodCallHandler(null);

  /// Recoge la llamada que el servicio de screening dejó anotada para el
  /// agente, si hay alguna.
  ///
  /// Existe porque `activate_agent` solo llega cuando hay UI viva, y una
  /// llamada entra casi siempre con la app en segundo plano o cerrada. El
  /// nativo lo anota en SharedPreferences y aquí se recoge al arrancar y al
  /// volver al primer plano. La lectura nativa borra el dato, así que una
  /// activación se atiende una sola vez.
  Future<PendingActivation?> consumePendingActivation() async {
    try {
      final result = await _channel
          .invokeMethod<Map<Object?, Object?>>('consumePendingActivation');

      if (result == null) return null;

      final number = (result['number'] as String?) ?? '';
      if (number.isEmpty) return null;

      return PendingActivation(
        number: number,
        risk: (result['risk'] as num?)?.toDouble() ?? 0,
        at: DateTime.fromMillisecondsSinceEpoch(
          (result['timestamp'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Vacía la cola nativa. El nativo la borra al entregarla, así que cada
  /// evento se importa una sola vez.
  Future<List<Map<Object?, Object?>>> drainEvents() async {
    try {
      final events =
          await _channel.invokeMethod<List<Object?>>('drainEvents') ?? const [];
      return events.whereType<Map<Object?, Object?>>().toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}
