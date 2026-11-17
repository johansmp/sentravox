import 'package:flutter/services.dart';

/// Decide si un error de reconocimiento debe terminar la llamada.
///
/// Existe porque tratar cualquier error de STT como fatal cortaba la
/// conversación tras el primer turno: al cerrar el micrófono para que hablara el
/// agente, Android emitía ERROR_CLIENT y eso terminaba la llamada. Los errores
/// transitorios solo invalidan *un turno*; la llamada debe seguir.
class SttErrorPolicy {
  const SttErrorPolicy._();

  /// El nativo no pudo ni arrancar (sin permiso, sin motor de reconocimiento).
  static const String unavailableCode = 'stt_unavailable';

  /// Fallo durante el reconocimiento; `details` trae el código de Android.
  static const String recognitionCode = 'stt_error';

  /// Códigos de `SpeechRecognizer` que solo significan «este turno no salió».
  ///
  /// Los de red (2, 3, 4) también se reintentan: un fallo puntual de datos no
  /// debe tumbar la llamada. Si el teléfono está completamente sin red, el
  /// bucle se rinde tras [ConversationLoopController.maxConsecutiveSttErrors]
  /// intentos y lo dice, en vez de cortar al primer error.
  static const Set<int> transientCodes = {
    2, // ERROR_NETWORK
    3, // ERROR_NETWORK_TIMEOUT
    4, // ERROR_SERVER
    5, // ERROR_CLIENT — típico tras cancel()/stopListening()
    6, // ERROR_SPEECH_TIMEOUT — silencio
    7, // ERROR_NO_MATCH — no se entendió nada
    8, // ERROR_RECOGNIZER_BUSY — el motor aún se estaba liberando
  };

  static bool isFatal(Object error) {
    if (error is! PlatformException) return true;

    // Sin micrófono o sin motor no hay nada que reintentar.
    if (error.code == unavailableCode) return true;

    final details = error.details;
    if (details is int) return !transientCodes.contains(details);

    return true;
  }

  static String describe(Object error) {
    if (error is PlatformException) {
      return error.message ?? 'Error de reconocimiento (${error.code}).';
    }
    return 'Error de reconocimiento: $error';
  }
}
