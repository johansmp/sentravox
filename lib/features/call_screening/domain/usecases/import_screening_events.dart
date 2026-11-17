import 'package:sentravox/features/call_logs/domain/entities/call_log.dart';
import 'package:sentravox/features/call_logs/domain/usecases/save_call_log.dart';
import 'package:sentravox/features/call_screening/domain/entities/screening_event.dart';
import 'package:sentravox/features/call_screening/platform/call_screening_bridge.dart';

/// Pasa al historial las llamadas que el servicio nativo filtró mientras no
/// había app viva. Sin esto, toda llamada bloqueada con SentraVox cerrado
/// desaparecería del historial.
class ImportScreeningEvents {
  final CallScreeningBridge bridge;
  final SaveCallLog saveCallLog;

  const ImportScreeningEvents({
    required this.bridge,
    required this.saveCallLog,
  });

  /// Devuelve cuántos eventos se importaron.
  ///
  /// Nota de orden: hay que drenar la cola **después** de recoger la activación
  /// pendiente del agente. Al recogerla, el lado nativo retira de esta cola el
  /// evento `agent` de esa llamada, porque el registro bueno —con transcripción
  /// y resumen— lo escribe el propio agente al colgar.
  Future<int> call() async {
    final raw = await bridge.drainEvents();
    if (raw.isEmpty) return 0;

    var imported = 0;

    for (final map in raw) {
      try {
        await saveCallLog(_toEntry(ScreeningEvent.fromMap(map)));
        imported++;
      } catch (_) {
        // Un evento corrupto no debe impedir importar los demás. Ya fue
        // retirado de la cola nativa, así que no se reintenta.
      }
    }

    return imported;
  }

  CallLogEntry _toEntry(ScreeningEvent event) {
    return CallLogEntry(
      number: event.number,
      transcript: '',
      intent: event.intent,
      risk: event.risk,
      summary: event.message.isEmpty
          ? 'Llamada filtrada por SentraVox.'
          : event.message,
      timestamp: event.timestamp,
      outcome: event.outcome,
    );
  }
}
