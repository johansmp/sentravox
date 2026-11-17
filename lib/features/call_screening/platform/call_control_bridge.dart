import 'package:flutter/services.dart';

import '../domain/entities/screening_diagnostics.dart';

/// Resultado de pedir el rol de filtrado de llamadas.
enum ScreeningRoleRequest {
  /// Se abrió el diálogo del sistema; el resultado lo dirá el estado al volver.
  requested,

  /// Ya lo teníamos.
  alreadyHeld,

  /// Android 10+ pero el dispositivo no ofrece el rol. Queda la vía de ser la
  /// app de teléfono predeterminada.
  roleUnavailable,

  /// Android 9 o anterior: no existe el rol, se pidió el marcador por defecto.
  legacyDialer,

  /// No se pudo ni abrir el diálogo.
  failed,

  /// Plataforma sin implementación nativa.
  unsupported;

  static ScreeningRoleRequest parse(String? status) {
    return switch (status) {
      'requested' => requested,
      'already_held' => alreadyHeld,
      'role_unavailable' => roleUnavailable,
      'legacy_dialer_requested' => legacyDialer,
      'no_role_manager' || 'request_failed' => failed,
      _ => unsupported,
    };
  }

  /// Mensaje para el usuario, o null si no hay nada que explicar.
  String? get explanation {
    return switch (this) {
      requested || alreadyHeld => null,
      roleUnavailable =>
        'Este teléfono no ofrece el permiso de filtrado de llamadas. '
            'La alternativa es configurar SentraVox como app de teléfono '
            'predeterminada.',
      legacyDialer =>
        'Tu versión de Android no tiene permiso de filtrado: solo la app de '
            'teléfono predeterminada puede filtrar llamadas.',
      failed => 'No se pudo abrir el diálogo del sistema.',
      unsupported => 'Función no disponible en esta plataforma.',
    };
  }
}

/// Control de la llamada en curso.
///
/// `endCall()` solo funciona en API 28+ y con el permiso ANSWER_PHONE_CALLS,
/// que el sistema concede en la práctica únicamente a la app de teléfono
/// predeterminada. Devuelve false en lugar de lanzar para que quien llama pueda
/// degradar con elegancia.
class CallControlBridge {
  static const MethodChannel _channel = MethodChannel('sentravox/dialer');

  const CallControlBridge();

  Future<bool> endCall() async {
    try {
      return await _channel.invokeMethod<bool>('end_call') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Descuelga la llamada que está sonando.
  ///
  /// Filtrar y contestar son cosas distintas: `CallScreeningService` solo deja
  /// pasar la llamada, y sin esto el teléfono sigue sonando con el agente ya
  /// abierto. Necesita `ANSWER_PHONE_CALLS` (API 26+); devuelve false si el
  /// sistema lo deniega.
  Future<bool> answerCall() async {
    try {
      return await _channel.invokeMethod<bool>('answer_call') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> canAnswerCalls() async {
    try {
      return await _channel.invokeMethod<bool>('can_answer_calls') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Estado de la llamada: IDLE, RINGING, ACTIVE o UNKNOWN.
  Future<String> callState() async {
    try {
      return await _channel.invokeMethod<String>('call_state') ?? 'UNKNOWN';
    } on MissingPluginException {
      return 'UNKNOWN';
    } on PlatformException {
      return 'UNKNOWN';
    }
  }

  /// Pone la llamada en altavoz y manda la voz del agente por esa ruta.
  ///
  /// Android no permite inyectar audio en el canal de subida de una llamada, así
  /// que el acoplamiento acústico por el altavoz es la única vía sin permisos de
  /// sistema. Depende del terminal.
  Future<bool> setInCallAudio(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>(
            'set_in_call_audio',
            {'enabled': enabled},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Estado real de la ruta de audio (modo, altavoz, dispositivo de llamada).
  Future<Map<String, Object?>> audioDiagnostics() async {
    try {
      final raw =
          await _channel.invokeMethod<Map<Object?, Object?>>('audio_diagnostics');
      if (raw == null) return const {};
      return raw.map((key, value) => MapEntry(key.toString(), value));
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  Future<bool> isDefaultDialer() async {
    try {
      return await _channel.invokeMethod<bool>('is_default_dialer') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestDefaultDialer() async {
    try {
      await _channel.invokeMethod('request_default_dialer');
    } on MissingPluginException {
      // Plataforma sin soporte: no hay nada que pedir.
    } on PlatformException {
      // El usuario puede rechazar el diálogo del sistema.
    }
  }

  /// ¿Nos deja el sistema filtrar llamadas?
  ///
  /// Es el permiso que de verdad decide si el agente llega a enterarse de una
  /// llamada: sin el rol de filtrado (`ROLE_CALL_SCREENING`, Android 10+, o ser
  /// el marcador predeterminado antes de eso) Android nunca invoca
  /// `AgentCallScreeningService` y ninguna llamada llega al agente.
  Future<bool> isScreeningRoleHeld() async {
    try {
      return await _channel.invokeMethod<bool>('is_screening_role_held') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Abre el diálogo del sistema para concedernos el rol de filtrado.
  ///
  /// Devuelve qué pasó, porque «no pasó nada» es un resultado posible —el
  /// dispositivo puede no ofrecer el rol— y hay que poder explicarlo en vez de
  /// dejar un botón que no reacciona.
  Future<ScreeningRoleRequest> requestScreeningRole() async {
    try {
      final status =
          await _channel.invokeMethod<String>('request_screening_role');
      return ScreeningRoleRequest.parse(status);
    } on MissingPluginException {
      return ScreeningRoleRequest.unsupported;
    } on PlatformException {
      return ScreeningRoleRequest.failed;
    }
  }

  /// Vuelve a pedir los permisos de ejecución que falten.
  Future<void> requestPermissions() => _fireAndForget('request_permissions');

  /// Ajustes de la app: la única salida si el usuario ya denegó un permiso.
  Future<void> openAppSettings() => _fireAndForget('open_app_settings');

  /// Ajustes del sistema para descargar el paquete de voz sin conexión.
  Future<void> openVoiceInputSettings() =>
      _fireAndForget('open_voice_input_settings');

  /// Android 14+: el aviso a pantalla completa se concede a mano.
  Future<void> requestFullScreenIntent() =>
      _fireAndForget('request_full_screen_intent');

  /// Estado de todos los requisitos, para no diagnosticar a ciegas.
  Future<ScreeningDiagnostics> diagnostics() async {
    try {
      final map = await _channel
          .invokeMethod<Map<Object?, Object?>>('diagnostics');

      if (map == null) return const ScreeningDiagnostics();
      return ScreeningDiagnostics.fromMap(map);
    } on MissingPluginException {
      return const ScreeningDiagnostics();
    } on PlatformException {
      return const ScreeningDiagnostics();
    }
  }

  Future<void> _fireAndForget(String method) async {
    try {
      await _channel.invokeMethod(method);
    } on MissingPluginException {
      // Plataforma sin soporte: no hay nada que pedir.
    } on PlatformException {
      // El usuario puede rechazar el diálogo del sistema.
    }
  }
}
