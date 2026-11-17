# IA local — modelo, evaluación y límites

## Decisión actual
La app empaqueta **Qwen3.5-0.8B-Q4_K_M** (GGUF, ≈508 MB, Apache-2.0) y lo ejecuta
con `llamadart`/llama.cpp en CPU. El modelo solo **reescribe** la respuesta que
ya calculó el guion local; no decide el flujo, no recibe audio y no usa red.

La razón es la latencia: en una llamada, el agente no puede quedarse callado
varios segundos. El guion local aporta la inteligencia de screening (huecos,
riesgo, cierres); el modelo aporta naturalidad.

## Modelos evaluados

| Modelo | Tamaño | Carga (PC) | Generación (PC) | Resultado |
|---|---:|---:|---:|---|
| SmolLM2-135M-Instruct Q2_K | 88 MB | ~1 s | <1 s | Español incoherente; descartado. |
| **Qwen3.5-0.8B Q4_K_M** | **533 MB** | **2,7 s** | **0,8–1,0 s** | Español coherente y respuestas breves correctas. **Elegido.** |
| Qwen3.5-2B Q4_K_M | 1,28 GB | 4,3 s | 1,8–2,2 s | Coherente, pero ~2,2× más lento y no mejoró las respuestas de reescritura. Descartado para empaquetar. |

Medición en el emulador Pixel 10 (API 37, CPU): Qwen3.5-0.8B con prompt
compacto ≈ **4,0 s por turno** y 64 tokens de salida. En un teléfono moderno
debería ser más rápido. Si el turno supera **4 s**, el agente usa el guion local.

## Por qué no un 2B/4B empaquetado
- El APK ya pesa ≈930 MB en depuración con el 0.8B. Un 2B lo llevaría a
  ≈1,7 GB y un 4B a más de 3 GB.
- La latencia en CPU crece casi linealmente con los parámetros. Un 2B/4B puede
  tardar 5–15 s por turno en un teléfono de gama media, demasiado para una
  conversación telefónica.
- Para esta tarea acotada (reescribir una frase y conservar una pregunta), el
  0.8B es suficiente; el 2B no mostró una mejora clara.

## Cómo cambiar de modelo
1. Copia el GGUF a `assets/models/`.
2. Ajusta `LocalLlmService.assetPath` y `modelName` en
   `lib/shared/services/llm/local_llm_service.dart`.
3. Añade el asset en `pubspec.yaml`.
4. Recompila. El copiador nativo lo llevará al almacenamiento interno la
   primera vez.
5. Ajusta `maxTokens` y el timeout si el modelo es más lento.

`tool/llm_smoke.dart` permite probar un GGUF en escritorio:

```powershell
dart run tool/llm_smoke.dart "C:\ruta\modelo.gguf"
```

## STT sin conexión
El reconocimiento usa `RecognizerIntent.EXTRA_PREFER_OFFLINE`. Si el teléfono
no tiene el paquete de español, el servicio nativo reintenta una vez en línea;
si tampoco hay red, la simulación pasa automáticamente a **modo texto** y la
llamada real termina con un aviso claro.

En **Configuración → Voz sin conexión** hay un acceso a los ajustes de entrada
de voz de Android para descargar el paquete de español. Sin ese paquete, el
reconocimiento offline no puede funcionar.

## Voces neuronales offline (Piper/Sherpa-ONNX)

La voz del agente ya no depende del TTS robótico del sistema. Se empaquetaron
dos voces Piper en español y se generan WAV con Sherpa-ONNX:

| Voz | Modelo | Tamaño | Licencia |
|---|---|---:|---|
| Femenina (es-MX) | `vits-piper-es_MX-claude-high-int8` | 18 MB | Apache-2.0 |
| Masculina (es-ES) | `vits-piper-es_ES-davefx-medium-int8` | 18 MB | Apache-2.0 |

- Los modelos están en `assets/tts/es_female/` y `assets/tts/es_male/`.
- `piper_phonemize` convierte el texto a fonemas espeak-ng; `sherpa_onnx`
  sintetiza el WAV en el teléfono.
- El WAV se reproduce por el mismo canal nativo que la llamada
  (`AudioTrack`/`MediaPlayer` con `USAGE_VOICE_COMMUNICATION`), así que la ruta
  acústica/directa sigue funcionando.
- **Cinco perfiles** en Configuración: Femenina natural, Femenina cálida,
  Masculina natural, Masculina serena y Neutra profesional. Cambian voz y
  velocidad; no son la voz del sistema.
- Si el modelo tarda o falla, se cae al TTS del sistema sin cortar la llamada.
- En el emulador, la generación de una frase de ~9 s tardó ~2,5 s y la
  reproducción se completó correctamente. En un teléfono moderno debería ser
  más rápido.
- **Licencia:** `piper_phonemize` es GPL-3.0 por espeak-ng. Para una
  distribución comercial hay que revisar ese punto o usar un lexicon/otro
  fonemizador. Los modelos Piper son Apache-2.0.

## Límites que siguen existiendo
- El modelo local no sustituye al guion: es un pulido de redacción.
- La inferencia es CPU; no se ha activado Vulkan/GPU porque es experimental y
  depende del fabricante.
- La primera copia del modelo tarda; el botón **Preparar modelo** permite
  hacerlo antes de una llamada.
- La memoria del modelo se mantiene mientras la app está abierta; se libera al
  desactivar la IA o cerrar la app.
