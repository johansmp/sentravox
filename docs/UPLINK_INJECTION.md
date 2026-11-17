# Uplink Injection — Alternativas implementadas

## Objetivo
Que la IA hable durante una llamada real sin que el usuario tenga que hablar y
sin clonar su voz. La app usa siempre una voz sintética del motor TTS del
teléfono; nunca graba la voz del usuario para imitarla.

## Restricción de Android
Una app normal **no puede escribir en el canal de subida (uplink) de una llamada
PSTN**. `AudioTrack`, `MediaPlayer`, `AAudio`, `ConnectionService` o
`InCallService` no cambian eso: el audio de la app va al downlink o al altavoz,
no al micrófono de la llamada. La inyección real requiere privilegios de sistema
o controlar la llamada de extremo a extremo (VoIP). Por eso la app implementa
varias rutas con degradación automática.

## Rutas implementadas

| Modo | Qué hace | Garantía |
|---|---|---|
| `acoustic` (por defecto) | Contesta con `TelecomManager`, pone la llamada en altavoz y reproduce el TTS con `USAGE_VOICE_COMMUNICATION`. El micrófono del teléfono recoge la voz sintética y la transmite. | La más compatible. Depende de la cancelación de eco del terminal. |
| `direct` (experimental) | Sintetiza a WAV, decodifica el PCM y lo reproduce con `AudioTrack` + `USAGE_VOICE_COMMUNICATION`, enrutado al dispositivo de comunicación. Algunos HAL de fabricante mezclan esa pista en la llamada. | Depende del fabricante. Si falla, cae a `acoustic`. |
| `auto` | Intenta `direct` y cae a `acoustic` si `AudioTrack` no puede preparar el WAV. | Igual que `acoustic` como mínimo. |

La ruta se elige en **Configuración → Gestor de voces → Ruta de audio en
llamada**. El botón **Ver ruta de audio** muestra el modo real de
`AudioManager`, el altavoz, el dispositivo de comunicación y el estado del motor
TTS, para no diagnosticar a ciegas.

## Cadena completa de una llamada
1. `AgentCallScreeningService` decide si la llamada pasa al agente.
2. `AutoAnswer` descuelga desde el proceso del servicio, sin depender de que se
   abra la UI, y enciende el altavoz.
3. `AgentController` saluda con TTS, cierra el micrófono mientras habla y lo
   reabre después. El bucle evita transcribir la propia voz del agente.
4. Al colgar, se restaura la ruta de audio y se guarda el registro.

## Limitaciones que siguen existiendo
- La cancelación de eco del teléfono puede atenuar la voz del agente en la
  ruta acústica. Se intenta desactivar con `AudioManager.setParameters`, pero no
  es una API pública garantizada.
- La captura de micrófono durante una llamada también depende del fabricante.
- `direct` no es una API soportada: es un intento razonable, no una promesa.
- El aviso a pantalla completa y la apertura de la UI en segundo plano siguen
  siendo best-effort en Android 10+.

## Alternativa 100 % funcional: relay VoIP
La única forma de controlar ambos canales de audio sin privilegios de sistema es
que la llamada termine en un endpoint VoIP propio:

1. El carrier, la PBX o un desvío condicionado redirige la llamada entrante a un
   número SIP/WebRTC del agente.
2. El agente (cliente SIP/WebRTC en el dispositivo o un servidor) atiende con
   audio bidireccional completo.
3. Se mantiene el historial, la memoria por número y el análisis de riesgo.

Esto **no está implementado** en este repositorio porque requiere un número
VoIP, un servidor SIP/PBX y credenciales. Es la ruta recomendada para producción
si se necesita garantía absoluta de audición en ambos sentidos.

## Privacidad de la voz y de los datos
- El agente habla con una voz sintética elegida del motor del sistema.
- No hay clonación de voz ni se pide al usuario que grabe muestras.
- El STT solo transcribe al interlocutor para entender la llamada; no se usa
  para sintetizar su voz.
- La IA avanzada es **local**: el modelo Qwen3.5 0.8B va en el APK y se ejecuta
  con llama.cpp en el teléfono. No se envía texto ni audio a ningún servidor y
  funciona sin Wi-Fi ni datos. El cliente remoto compatible con OpenAI queda
  como código heredado y no se usa desde la UI.
