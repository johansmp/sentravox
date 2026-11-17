package com.sentravox.sentravox.call

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Descuelga la llamada sin depender de que se abra la pantalla del agente.
 *
 * Antes el descolgado vivía en `AgentController.onCallStarting`, o sea que solo
 * ocurría si Android nos dejaba abrir una Activity desde segundo plano. Cuando
 * no nos deja —que es lo normal en Android 10+ sin exención— el teléfono seguía
 * sonando. Aquí se hace desde el propio proceso del servicio de filtrado, que ya
 * está vivo y no necesita permiso para abrir UI.
 *
 * Se reintenta porque hay una carrera real: `respondToCall(allow)` deja pasar la
 * llamada, pero Telecom tarda un poco en ponerla en estado RINGING y
 * `acceptRingingCall()` sobre una llamada que aún no suena no hace nada.
 *
 * Se para en cuanto la llamada deja de sonar, sea porque contestamos nosotros o
 * porque contestó el usuario.
 */
object AutoAnswer {

    private const val TAG = "SentraVoxAutoAnswer"

    /** Timbres de cortesía antes de que conteste el agente. */
    private const val INITIAL_DELAY_MS = 2_000L

    private const val RETRY_INTERVAL_MS = 800L
    private const val MAX_ATTEMPTS = 8

    /** Margen tras descolgar antes de enrutar el audio. */
    private const val AUDIO_ROUTE_DELAY_MS = 600L

    private val handler = Handler(Looper.getMainLooper())

    /** Evita dos secuencias solapadas si entran avisos repetidos. */
    private var scheduled = false

    fun schedule(context: Context) {
        val appContext = context.applicationContext

        if (!CallAudioController.canAnswerCalls(appContext)) {
            Log.w(TAG, "Sin permiso ANSWER_PHONE_CALLS: no se puede contestar sola")
            return
        }

        if (scheduled) {
            Log.i(TAG, "Ya hay un intento de contestar en curso")
            return
        }

        scheduled = true
        handler.postDelayed({ attempt(appContext, 1) }, INITIAL_DELAY_MS)
    }

    fun cancel() {
        scheduled = false
        handler.removeCallbacksAndMessages(null)
    }

    private fun attempt(context: Context, number: Int) {
        val state = CallAudioController.callState(context)

        if (state == CallAudioController.CallState.ACTIVE) {
            Log.i(TAG, "La llamada ya está contestada (intento $number)")
            finish(context, answered = true)
            return
        }

        if (state == CallAudioController.CallState.IDLE) {
            Log.i(TAG, "Ya no hay llamada que contestar (intento $number)")
            finish(context, answered = false)
            return
        }

        Log.i(TAG, "Contestando la llamada (intento $number)")
        CallAudioController.answerRingingCall(context)

        if (number >= MAX_ATTEMPTS) {
            Log.w(TAG, "Se agotaron los intentos de contestar")
            finish(context, answered = CallAudioController.callState(context) ==
                CallAudioController.CallState.ACTIVE)
            return
        }

        handler.postDelayed({ attempt(context, number + 1) }, RETRY_INTERVAL_MS)
    }

    private fun finish(context: Context, answered: Boolean) {
        scheduled = false
        if (!answered) return

        // El altavoz es lo único que acopla la voz del agente a la llamada.
        handler.postDelayed(
            { CallAudioController.setInCallAudio(context, true) },
            AUDIO_ROUTE_DELAY_MS
        )
    }
}
