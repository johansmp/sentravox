# Arquitectura Final — SentraVox

## Capas
- `lib/features/<feature>/{domain,data,presentation}` (Clean Architecture)
- `lib/ui/` pantallas reales
- `lib/shared/services/` wrappers de MethodChannel y servicios opcionales (LLM)
- `android/...` servicios nativos (STT, TTS, NLP, screening, audio)

## Módulos clave
- call_agent: FSM, DialogueEngine, ConversationLoopController, memoria,
  clasificador híbrido y cliente LLM opcional.
- call_logs: persistencia y estadísticas.
- call_screening: diagnósticos, eventos, bridges.
- settings: AppSettings (protección, agente, voz, audio, LLM). Incluye
  `agentAllCalls` para que el agente atienda también contactos conocidos: el
  usuario no necesita hablar con nadie.

## Componentes de esta iteración
- `AgentPersona`: reúne nombre, empresa, rol, personalidad, propietario y
  formalidad. El guion usa todos esos datos; antes solo usaba nombre y empresa.
- `DialogueTemplates` con variantes por formalidad y cierre que nombra al
  propietario.
- `HybridClassifierRepositoryImpl`: combina opcionalmente un modelo nativo con
  las reglas en español. **El modelo ONNX de marcador de posición se retiró**;
  la app usa `RulesClassifierRepositoryImpl` (reglas + riesgo) y no necesita
  ONNX Runtime para clasificar.
- `FactExtractor` mejorado: teléfonos dictados con palabras, «el mismo número»,
  empresas con «de parte de», nombres de hasta 5 palabras, «con Carlos…» y
  rechazo de «sí»/«no»/muletillas como nombre o motivo.
- `LocalLlmService` + `LocalLlmResponder`: **IA local** con Qwen3.5 0.8B GGUF y
  `llamadart`/llama.cpp. El modelo va empaquetado en `assets/models/`, se copia
  al almacenamiento interno mediante un canal nativo y se ejecuta en CPU. Solo
  reformula respuestas normales; cierres y temas sensibles usan el guion local.
  Si tarda más de 4 s o falla, se ignora sin cortar la llamada.
- `LocalModelAssets` (Kotlin): copia en streaming del asset de 508 MB al
  almacenamiento interno, sin cargarlo entero en memoria.
- `NeuralTtsService`: **voces neuronales Piper** offline (femenina es-MX y
  masculina es-ES) con `piper_phonemize` + `sherpa_onnx`. Genera WAV y lo
  reproduce por la misma ruta de audio de la llamada. `HybridTtsService` cae al
  TTS del sistema si el modelo no está listo. Cinco perfiles de voz.
- STT robusto: intenta el paquete offline de `es-CO`; si falta, reintenta una
  vez en línea. Los errores de red/servidor se reintentan. La simulación pasa a
  **modo texto** si el micrófono no está disponible, con un campo para inyectar
  turnos.
- `AgentController.checkCallStateOnce`: al detectar que la llamada quedó IDLE,
  detiene el agente y persiste el historial. Antes una llamada entrante podía
  quedar en 0 interacciones y no guardarse si el interlocutor colgaba.
- Clasificación de nombres: se quita la presentación («me llamo/me llamó X»)
  antes de buscar palabras clave, para que un apellido como «Mora» no dispare
  la regla de cobranza.
- Gestor de voces real:
  - cinco perfiles cerrados con voz neuronal Piper (femenina/masculina) y
    respaldo al TTS del sistema;
  - velocidad natural por perfil (0,88–1,0) y selección automática de la voz
    del sistema si la neuronal no está lista.
- Audio en llamada:
  - `acoustic`: altavoz + `MediaPlayer` con `USAGE_VOICE_COMMUNICATION`;
  - `direct`: `AudioTrack` con WAV PCM decodificado (experimental);
  - `auto`: directa con respaldo acústico;
  - diagnóstico de ruta real desde Configuración.
- `SettingsPage` reescrita: controladores estables (sin saltos de cursor),
  selectores de voz y audio, prueba de voz, prueba de LLM y lista de bloqueo.

## Flujo de llamada
1. Screening (nativo) decide allow/block/agent.
2. Activación (prefs + notificación + startActivity).
3. AgentPage crea AgentController con el perfil completo y, si está activado,
   el responder LLM.
4. onCallStarting: seed memoria, auto-answer, audio route.
5. Bucle: STT final → stop mic → analyze híbrido → reply → TTS → resume.
6. onCallFinished: hang up, restore audio, persistir log.

## Métricas de calidad
- `flutter analyze`: 0 issues.
- `flutter test`: 147/147.
- `flutter build apk --debug`: OK (≈1,04 GB con LLM + voces Piper).
- Probado en emulador Pixel 10 (API 37):
  - llamada entrante contestada y guardada en el historial;
  - cierre automático al colgar el interlocutor;
  - el inicio actualiza «2 llamadas analizadas hoy» al volver de la llamada,
    sin abrir el historial;
  - detalle del historial con la conversación completa (`Agente: …`);
  - voz neuronal femenina y masculina generada/reproducida (`NeuralTts` con
    197.940 muestras a 22.050 Hz, reproducción completada);
  - nombre «con Carlos Andrés Ramírez Gomez» reconocido sin repetir la
    pregunta;
  - simulación en modo texto cuando falta el paquete offline de STT.
