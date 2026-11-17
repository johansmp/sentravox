# Modelo LLM local

- **Archivo:** `Qwen3.5-0.8B-Q4_K_M.gguf`
- **Tamaño:** 532.517.120 bytes (≈508 MB)
- **Origen:** https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF
- **Modelo base:** Qwen/Qwen3.5-0.8B
- **Cuantización:** Q4_K_M (Unsloth Dynamic 2.0)
- **Licencia:** Apache-2.0
- **Uso en la app:** reescribir en español la respuesta que ya calculó el guion
  local. No decide el flujo, no recibe audio y no necesita red.

El modelo se ejecuta con `llamadart` (llama.cpp) en CPU, dentro del teléfono.
La primera vez se copia desde los assets del APK al almacenamiento interno de la
app; después se carga bajo demanda y se reutiliza entre llamadas.

Si se reemplaza por otro GGUF, actualiza `assetPath`/`modelName` en
`lib/shared/services/llm/local_llm_service.dart` y la entrada de assets de
`pubspec.yaml`. Para producción conviene valorar un modelo más pequeño o una
entrega por Play Asset Delivery, porque el APK con este modelo supera los
900 MB en depuración.
