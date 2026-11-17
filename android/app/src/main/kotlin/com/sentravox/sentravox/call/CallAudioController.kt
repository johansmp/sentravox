package com.sentravox.sentravox.call

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.util.Log

/**
 * Contestar la llamada y poner el audio donde el agente pueda usarlo.
 *
 * `CallScreeningService` solo decide si una llamada pasa o se bloquea: **nunca
 * la contesta**. Por eso el agente se abría pero el teléfono seguía sonando.
 * Descolgar es cosa de `TelecomManager.acceptRingingCall()`, que necesita
 * `ANSWER_PHONE_CALLS` (API 26+) y, como `endCall()`, devuelve el control sin
 * excepciones si el sistema lo deniega.
 *
 * Sobre el audio, y conviene tenerlo claro: Android no ofrece ninguna API para
 * inyectar audio en el canal de subida de una llamada telefónica. Lo único
 * posible sin privilegios de sistema es poner la llamada en altavoz y hablar
 * por él, de modo que el micrófono recoja la voz del agente y la transmita —y
 * de paso recoja al interlocutor para el reconocimiento—. Funciona, pero
 * depende del hardware: la cancelación de eco del terminal puede atenuar
 * bastante lo que oye la otra parte.
 */
object CallAudioController {

    private const val TAG = "SentraVoxCallAudio"

    /** Estado previo del altavoz, para devolverlo al terminar. */
    private var previousSpeakerOn: Boolean? = null

    /** Modo de audio previo, para restaurarlo al colgar. */
    private var previousMode: Int? = null

    /** Estado de la llamada, sin exponer las constantes de TelephonyManager. */
    enum class CallState { IDLE, RINGING, ACTIVE, UNKNOWN }

    fun callState(context: Context): CallState {
        if (context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return CallState.UNKNOWN
        }

        val telephonyManager =
            context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                ?: return CallState.UNKNOWN

        return try {
            @Suppress("DEPRECATION")
            when (telephonyManager.callState) {
                TelephonyManager.CALL_STATE_IDLE -> CallState.IDLE
                TelephonyManager.CALL_STATE_RINGING -> CallState.RINGING
                TelephonyManager.CALL_STATE_OFFHOOK -> CallState.ACTIVE
                else -> CallState.UNKNOWN
            }
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo leer el estado de la llamada", e)
            CallState.UNKNOWN
        }
    }

    fun canAnswerCalls(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false

        return context.checkSelfPermission(Manifest.permission.ANSWER_PHONE_CALLS) ==
            PackageManager.PERMISSION_GRANTED
    }

    /** Descuelga la llamada que está sonando. false si el sistema no deja. */
    fun answerRingingCall(context: Context): Boolean {
        if (!canAnswerCalls(context)) {
            Log.w(TAG, "Sin permiso ANSWER_PHONE_CALLS: no se puede contestar")
            return false
        }

        // Ya está contestada (por el lado nativo o por el usuario): no hay nada
        // que hacer, y decir que sí evita un aviso de error engañoso en la UI.
        if (callState(context) == CallState.ACTIVE) return true

        val telecomManager =
            context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return false

        return try {
            telecomManager.acceptRingingCall()
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "acceptRingingCall() denegado", e)
            false
        } catch (e: Throwable) {
            Log.w(TAG, "acceptRingingCall() falló", e)
            false
        }
    }

    /**
     * Enciende (o apaga) el altavoz para que el agente y el interlocutor se
     * oigan. Es la única vía de acoplar el TTS al canal de la llamada.
     */
    fun setInCallAudio(context: Context, enabled: Boolean): Boolean {
        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false

        return try {
            if (enabled) {
                if (previousSpeakerOn == null) {
                    previousSpeakerOn = isSpeakerOn(audioManager)
                }
                if (previousMode == null) {
                    previousMode = audioManager.mode
                }
                // El modo se elige según la ruta: la inyección directa usa el
                // modo de comunicación (VoIP); la acústica usa el modo de
                // llamada, que es donde el altavoz y el micrófono se acoplan.
                val prefs = context.getSharedPreferences(
                    "sentravox_prefs",
                    Context.MODE_PRIVATE
                )
                val injection = prefs.getString("in_call_audio_mode", "acoustic")
                audioManager.mode = if (injection == "direct" || injection == "auto") {
                    AudioManager.MODE_IN_COMMUNICATION
                } else {
                    AudioManager.MODE_IN_CALL
                }
                // Intento de desactivar la cancelación de eco y la supresión de
                // ruido del terminal. No es API pública garantizada, pero en los
                // dispositivos que lo aceptan mejora mucho que el TTS llegue al
                // otro lado. Si no lo aceptan, se ignora silenciosamente.
                try {
                    audioManager.setParameters("echo_cancellation=0")
                    audioManager.setParameters("noise_suppression=0")
                    audioManager.setParameters("aec=0")
                } catch (e: Throwable) {
                    Log.w(TAG, "No se pudieron ajustar parámetros de audio", e)
                }
                route(audioManager, speaker = true)
            } else {
                route(audioManager, speaker = previousSpeakerOn ?: false)
                previousMode?.let { audioManager.mode = it }
                previousMode = null
                previousSpeakerOn = null
            }
            true
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo cambiar la ruta de audio", e)
            false
        }
    }

    private fun route(audioManager: AudioManager, speaker: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!speaker) {
                audioManager.clearCommunicationDevice()
                return
            }

            val device = audioManager.availableCommunicationDevices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            }

            if (device != null && audioManager.setCommunicationDevice(device)) return
        }

        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = speaker
    }

    private fun isSpeakerOn(audioManager: AudioManager): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return audioManager.communicationDevice?.type ==
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        }

        @Suppress("DEPRECATION")
        return audioManager.isSpeakerphoneOn
    }

    /**
     * Estado de la ruta de audio, para que Configuración pueda decir qué se
     * está usando de verdad y no solo qué se configuró.
     */
    fun audioDiagnostics(context: Context): Map<String, Any?> {
        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

        val deviceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager?.communicationDevice?.type
        } else {
            null
        }

        return mapOf(
            "mode" to audioManager?.mode,
            "speaker_on" to (audioManager?.let { isSpeakerOn(it) } ?: false),
            "communication_device" to deviceType,
            "call_state" to callState(context).name,
            "can_answer" to canAnswerCalls(context)
        )
    }
}
