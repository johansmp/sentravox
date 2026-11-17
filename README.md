# SentraVox

[![Flutter](https://img.shields.io/badge/Flutter-3.44%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-10%2B-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![Offline](https://img.shields.io/badge/100%25_offline-sin_red-success)](#)
[![Tests](https://img.shields.io/badge/tests-147_passing-brightgreen)](#)

Agente de voz para filtrar llamadas entrantes en Android. Contesta, escucha al
interlocutor, clasifica la intención y el riesgo, responde con una voz neuronal
offline y guarda un resumen en el historial. El usuario **no tiene que hablar**
ni grabar su voz: el agente usa siempre una voz sintética incluida en la app.

## Qué hace

- **Filtrado previo**: `CallScreeningService` decide si una llamada se bloquea,
  se deja pasar o la atiende el agente. Por defecto el agente atiende
  desconocidos; con «Atender también contactos conocidos» atiende cualquier
  llamada que pase el filtro, y el usuario no habla con nadie.
- **Contestación automática**: descuelga con `TelecomManager` y activa la ruta de
  audio (altavoz o inyección directa experimental).
- **Conversación con guion**: pide nombre, motivo y número de devolución; corta
  llamadas comerciales, bancarias o de riesgo; nunca recita la transcripción.
- **Clasificador sin conexión**: reglas en español + heurística de riesgo. No
  depende de un modelo nativo que pueda faltar: la llamada sigue funcionando
  aunque el teléfono no tenga red.
- **Memoria por número**: recuerda nombre, empresa y teléfono de contacto entre
  llamadas.
- **Historial**: guarda transcripción, intención dominante, riesgo, resumen,
  sentimiento y puntuación de lead.
- **Voz configurable**: 5 perfiles neuronales offline (Piper/Sherpa-ONNX),
  femenina/masculina y velocidad natural. Si el modelo de voz no está listo, se
  usa el TTS del sistema como respaldo.
- **IA local incluida**: modelo Qwen3.5 0.8B (GGUF, ≈508 MB) empaquetado en la
  app y ejecutado con llama.cpp en el teléfono. Reformula las respuestas del
  guion sin enviar texto ni audio a ningún servidor; funciona en modo avión.
  Si no está listo o tarda, se usa el guion local sin cortar la llamada.

## Requisitos

- Flutter 3.44+ / Dart 3.12+
- Android 10+ para el rol de filtrado de llamadas (`ROLE_CALL_SCREENING`).
- Permisos: micrófono, teléfono, responder llamadas, contactos y notificaciones.

## Ejecutar

Los modelos pesados no se versionan en Git (GitHub rechaza archivos de más de
100 MB). Antes de compilar hay que descargarlos:

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File tool/fetch_models.ps1
```

```bash
# macOS / Linux
bash tool/fetch_models.sh
```

Descarga `assets/models/Qwen3.5-0.8B-Q4_K_M.gguf` (≈508 MB) y las dos voces
Piper en `assets/tts/` (≈36 MB). Sin ellos `flutter build apk` falla porque
`pubspec.yaml` los declara como assets. Si ya los tienes, el script no vuelve a
descargarlos.

Después:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Para compilar el APK de depuración:

```powershell
flutter build apk --debug
```

## Configuración importante

En **Configuración → Permiso para filtrar llamadas** hay que conceder el rol de
filtrado; sin él Android no invoca el servicio y ninguna llamada llega al
agente. En **Diagnóstico** se ve, en orden, qué requisito falta.

La ruta de audio se elige en **Configuración → Ruta de audio en llamada**:

- `Altavoz (compatible)`: la voz sale por el altavoz y el micrófono la
  transmite. Es la ruta recomendada.
- `Inyección directa (experimental)`: intenta enviar la voz por `AudioTrack`;
  depende del fabricante y cae al altavoz si no puede.
- `Automática`: prueba la directa y usa la acústica como respaldo.

Android no permite a una app normal escribir en el uplink de una llamada PSTN.
La única vía con garantía total es un relay VoIP/SIP; está documentado en
[`docs/UPLINK_INJECTION.md`](docs/UPLINK_INJECTION.md).

## IA local

El modelo Qwen3.5 0.8B Q4_K_M va empaquetado en `assets/models/` y se ejecuta
con `llamadart`/llama.cpp en CPU. La primera vez se copia al almacenamiento
interno; después se carga bajo demanda y se reutiliza entre llamadas. No hay
peticiones de red, API keys ni telemetría.

- En **Configuración → IA local** puedes preparar el modelo, probarlo y
  desactivarlo.
- El agente solo lo usa para reescribir la respuesta que ya calculó el guion.
  Los cierres y los temas sensibles (banco, fraude, amenaza) no pasan por el
  modelo.
- Si el modelo tarda más de 4 s o falla, el agente responde con el guion local.
- El APK de depuración con el modelo ronda los **1,04 GB** (LLM + dos voces
  neuronales + librerías nativas). Para producción conviene Play Asset Delivery
  o un modelo más pequeño. La licencia y la fuente están en
  [`assets/models/NOTICE.md`](assets/models/NOTICE.md) y
  [`docs/LOCAL_LLM.md`](docs/LOCAL_LLM.md).
- Se evaluó también Qwen3.5 2B Q4 (1,28 GB): no mejoró la reescritura y fue
  ~2,2× más lento. La comparativa completa está en
  [`docs/LOCAL_LLM.md`](docs/LOCAL_LLM.md).

## Si el micrófono falla
El reconocimiento intenta primero el paquete offline de español y, si falta,
reintenta una vez en línea. En **Configuración → Voz sin conexión** puedes abrir
los ajustes de Android para descargar el paquete de español.

En la **simulación**, si el STT falla, la pantalla pasa automáticamente a
**modo texto** y permite escribir el turno del interlocutor. Así se puede
probar el guion y la IA local aunque el emulador no tenga micrófono o paquete de
voz offline.

## Historial de llamadas entrantes
`AgentController` vigila el estado de la llamada cada 2 s. Cuando el
interlocutor cuelga, el agente se detiene y guarda el registro con
transcripción, intención, riesgo y resumen. Antes solo se guardaba si se
pulsaba «Finalizar llamada»; por eso una llamada podía quedar en 0
interacciones y no aparecer en el historial.

La transcripción guardada incluye **ambos lados** (`Agente: …` /
`Interlocutor: …`). Si el interlocutor nunca habló —por ejemplo, una llamada de
prueba del emulador sin audio— el detalle muestra el saludo del agente en lugar
de una transcripción vacía que parecía una llamada filtrada.

Al volver de la pantalla de la llamada, el inicio **recarga los contadores**
(`RouteObserver` + `didPopNext`). Antes solo los cargaba al arrancar y al abrir
el historial, así que la tarjeta seguía diciendo «Sin llamadas analizadas hoy»
aunque la llamada ya estuviera guardada.

## Estructura

- `lib/features/call_agent/`: guion, clasificador, memoria y controladores.
- `lib/features/call_logs/`: persistencia y estadísticas.
- `lib/features/call_screening/`: puentes y diagnósticos del filtrado.
- `lib/features/settings/`: ajustes compartidos con Kotlin.
- `lib/ui/`: pantallas.
- `android/app/src/main/kotlin/...`: STT, TTS, NLP, screening y audio nativo.

Más detalle en [`CLAUDE.md`](CLAUDE.md) y
[`docs/ARCHITECTURE_FINAL.md`](docs/ARCHITECTURE_FINAL.md).
