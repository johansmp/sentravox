package com.sentravox.sentravox.stt

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Puente entre el SpeechRecognizer de Android y Flutter.
 *
 * Contrato del EventChannel: cada evento es un Map
 *   { "text": String, "isFinal": Boolean }
 *
 * `isFinal = false` son hipótesis parciales (llegan primero y cambian);
 * `isFinal = true` es el resultado definitivo. Los errores se envían por
 * `EventSink.error` para que el Future de Dart falle en lugar de colgarse.
 *
 * Modo continuo: el SpeechRecognizer de Android termina su sesión en cada
 * enunciado, así que para una conversación hay que rearrancarlo. Con
 * `continuous = true` el servicio se rearranca solo tras los errores de
 * silencio (NO_MATCH / SPEECH_TIMEOUT), que en una llamada real son normales y
 * no deben mostrarse como fallo. Tras un resultado definitivo NO se rearranca:
 * ahí manda Dart, que necesita cerrar el micrófono mientras habla el agente
 * para no transcribir su propia voz (TTS).
 */
class OfflineSttService(
    private val activity: Activity,
    private val methodChannel: MethodChannel,
    private val eventChannel: EventChannel
) : RecognitionListener {

    private companion object {
        const val TAG = "SentraVoxStt"

        const val RESTART_DELAY_MS = 250L
        const val BUSY_RESTART_DELAY_MS = 1000L
        const val MAX_CONSECUTIVE_ERRORS = 6

        const val SILENCE_MS = 1500L
        const val MIN_UTTERANCE_MS = 1000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private var speechRecognizer: SpeechRecognizer? = null
    private var isListening: Boolean = false
    private var continuous: Boolean = false
    private var disposed: Boolean = false
    private var consecutiveErrors: Int = 0
    private var eventSink: EventChannel.EventSink? = null

    /**
     * Se intenta primero el modelo en el dispositivo. Si el teléfono no tiene
     * el paquete de español, se reintenta una vez con el servicio en línea.
     */
    private var preferOffline: Boolean = true

    /**
     * `stopListening()` provoca un `onError` asíncrono (normalmente
     * ERROR_CLIENT, a veces ERROR_NO_MATCH) que es consecuencia de nuestra
     * propia parada, no un fallo. Reenviarlo a Dart hacía que la conversación
     * se cortara tras el primer turno: el agente cerraba el micrófono para
     * hablar y el error resultante terminaba la llamada.
     */
    private var suppressNextError: Boolean = false

    init {
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    continuous = call.argument<Boolean>("continuous") ?: false
                    consecutiveErrors = 0
                    suppressNextError = false
                    val error = startRecognition()
                    if (error == null) {
                        result.success(null)
                    } else {
                        continuous = false
                        result.error("stt_unavailable", error, null)
                    }
                }
                "stopListening" -> {
                    continuous = false
                    mainHandler.removeCallbacksAndMessages(null)
                    // Solo hay que silenciar el error si de verdad estábamos
                    // escuchando: si no, la bandera quedaría armada y se
                    // comería un error real posterior.
                    suppressNextError = isListening
                    stopListening()
                    result.success(null)
                }
                "isAvailable" -> {
                    result.success(SpeechRecognizer.isRecognitionAvailable(activity))
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Devuelve null si arrancó bien, o el mensaje de error si no pudo. */
    private fun startRecognition(): String? {
        if (disposed) return "El servicio de reconocimiento ya fue liberado."
        if (isListening) return null

        if (!hasMicPermission()) {
            return "Falta el permiso de micrófono (RECORD_AUDIO)."
        }

        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            return "No hay servicio de reconocimiento de voz disponible en el dispositivo."
        }

        if (speechRecognizer == null) {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(activity)
                ?.also { it.setRecognitionListener(this) }
                ?: return "No se pudo crear el SpeechRecognizer."
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "es-CO")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            // Preferir el modelo en el dispositivo. Si el paquete de español
            // no está instalado, onError() reintenta una vez sin esta marca.
            if (preferOffline) {
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            }
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.packageName)
            // Pistas de corte de turno (el motor puede ignorarlas).
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                SILENCE_MS
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                SILENCE_MS
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                MIN_UTTERANCE_MS
            )
        }

        isListening = true
        speechRecognizer?.startListening(intent)
        return null
    }

    private fun stopListening() {
        isListening = false
        speechRecognizer?.stopListening()
    }

    fun dispose() {
        disposed = true
        continuous = false
        isListening = false
        mainHandler.removeCallbacksAndMessages(null)
        eventSink = null
        eventChannel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
        speechRecognizer?.destroy()
        speechRecognizer = null
    }

    private fun hasMicPermission(): Boolean =
        activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun emit(text: String, isFinal: Boolean) {
        eventSink?.success(
            mapOf(
                "text" to text,
                "isFinal" to isFinal
            )
        )
    }

    private fun scheduleRestart(delayMs: Long) {
        if (!continuous || disposed) return
        mainHandler.postDelayed({
            if (continuous && !disposed && !isListening) {
                val error = startRecognition()
                if (error != null) {
                    continuous = false
                    eventSink?.error("stt_unavailable", error, null)
                }
            }
        }, delayMs)
    }

    /** Silencios y reintentos: normales en escucha continua, no son fallos. */
    private fun isRecoverable(error: Int): Boolean = when (error) {
        SpeechRecognizer.ERROR_NO_MATCH,
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
        SpeechRecognizer.ERROR_CLIENT -> true
        else -> false
    }

    override fun onReadyForSpeech(params: Bundle?) {}

    override fun onBeginningOfSpeech() {}

    override fun onRmsChanged(rmsdB: Float) {}

    override fun onBufferReceived(buffer: ByteArray?) {}

    override fun onEndOfSpeech() {
        isListening = false
    }

    override fun onError(error: Int) {
        isListening = false

        if (suppressNextError) {
            suppressNextError = false
            return
        }

        // 12/13/14: el paquete offline de es-CO no está instalado o el motor no
        // puede comprobarlo. Se reintenta una vez con el servicio en línea; si
        // tampoco hay red, Dart decidirá si es transitorio o fatal.
        if (continuous && preferOffline &&
            (error == 12 || error == 13 || error == 14)
        ) {
            preferOffline = false
            Log.i(
                TAG,
                "Paquete de voz offline no disponible (error $error); " +
                    "reintentando en línea"
            )
            scheduleRestart(RESTART_DELAY_MS)
            return
        }

        if (continuous && isRecoverable(error)) {
            consecutiveErrors++
            if (consecutiveErrors <= MAX_CONSECUTIVE_ERRORS) {
                val delay = if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY) {
                    BUSY_RESTART_DELAY_MS
                } else {
                    RESTART_DELAY_MS
                }
                scheduleRestart(delay)
                return
            }
        }

        // Sin esto el stream se queda callado y el await de Dart no termina nunca.
        continuous = false
        consecutiveErrors = 0
        eventSink?.error("stt_error", describeError(error), error)
    }

    override fun onResults(results: Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        // El primer elemento es la hipótesis de mayor confianza, no la concatenación.
        val text = matches?.firstOrNull() ?: ""
        isListening = false
        consecutiveErrors = 0
        // Ya hubo resultado: cualquier error posterior sería de la sesión nueva.
        suppressNextError = false
        emit(text, true)
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val text = matches?.firstOrNull() ?: ""
        if (text.isNotEmpty()) {
            consecutiveErrors = 0
            emit(text, false)
        }
    }

    override fun onEvent(eventType: Int, params: Bundle?) {}

    private fun describeError(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "Error de grabación de audio."
        SpeechRecognizer.ERROR_CLIENT -> "Error del cliente de reconocimiento."
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
            "Permiso de micrófono denegado."
        SpeechRecognizer.ERROR_NETWORK -> "Error de red."
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Tiempo de espera de red agotado."
        SpeechRecognizer.ERROR_NO_MATCH -> "No se reconoció ninguna frase."
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "El reconocedor está ocupado."
        SpeechRecognizer.ERROR_SERVER -> "Error del servidor de reconocimiento."
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No se detectó voz."
        else -> "Error de reconocimiento desconocido ($error)."
    }
}
