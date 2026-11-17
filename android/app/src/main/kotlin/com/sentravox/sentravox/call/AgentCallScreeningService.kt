package com.sentravox.sentravox.call

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.telecom.Call.Details
import android.telecom.CallScreeningService
import android.util.Log
import com.sentravox.sentravox.core.SentraVoxPrefs
import io.flutter.plugin.common.MethodChannel

/**
 * Filtra las llamadas entrantes antes de que suenen.
 *
 * Este servicio puede ejecutarse con la app cerrada, así que no asume que haya
 * un FlutterEngine: los ajustes se leen de [SentraVoxPrefs] y **todos** los
 * eventos se encolan ahí para que Dart los importe al historial en el próximo
 * arranque. Si además hay UI viva, se avisa por [flutterChannel] para reaccionar
 * en el momento.
 *
 * Ojo: para que Android llegue a invocar [onScreenCall] la app tiene que tener
 * el rol de filtrado de llamadas (`ROLE_CALL_SCREENING`, API 29+) o ser el
 * marcador predeterminado en versiones anteriores. Sin ese rol este código
 * nunca se ejecuta y la llamada no llega al agente: se pide desde
 * Configuración.
 */
class AgentCallScreeningService : CallScreeningService() {

    companion object {
        private const val TAG = "SentraVoxScreening"

        /** Lo asigna MainActivity mientras hay UI; null con la app cerrada. */
        var flutterChannel: MethodChannel? = null

        const val OUTCOME_BLOCKED_SILENT = "blocked_silent"
        const val OUTCOME_BLOCKED_NOTIFIED = "blocked_notified"
        const val OUTCOME_AGENT = "agent"
        const val OUTCOME_ALLOWED = "allowed"
        const val OUTCOME_SKIPPED = "skipped_disabled"
    }

    override fun onScreenCall(call: Details) {
        // Solo interesan las entrantes: desde API 29 las salientes también pasan
        // por aquí y filtrarlas dejaría al usuario sin poder llamar.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            call.callDirection != Details.DIRECTION_INCOMING
        ) {
            respondToCall(call, allowCall())
            return
        }

        val rawNumber = call.handle?.schemeSpecificPart ?: ""
        val number = rawNumber.ifEmpty { "desconocido" }
        val isUnknownCaller = isUnknownCaller(call, rawNumber)
        val now = System.currentTimeMillis()

        Log.i(TAG, "Llamada entrante de $number (desconocido=$isUnknownCaller)")

        // Protección desactivada: no se filtra nada, pero se registra el paso
        // para que el historial no tenga huecos.
        if (!SentraVoxPrefs.securityEnabled(this)) {
            record(number, 0.0, "sin_analizar", OUTCOME_SKIPPED, "Protección desactivada.", now)
            respondToCall(call, allowCall())
            return
        }

        val blocklist = SentraVoxPrefs.blocklist(this)
        val risk = RiskEvaluator.evaluate(
            number = rawNumber,
            blocklist = blocklist,
            isUnknownCaller = isUnknownCaller
        )
        val intent = RiskEvaluator.intentFor(risk)
        val message = ScreeningDialogue.generate(risk, number)

        notifyFlutter(
            "screening_message",
            mapOf("number" to number, "risk" to risk, "message" to message)
        )

        val threshold = SentraVoxPrefs.blockThreshold(this)

        // 1. Bloqueo por riesgo alto o lista de bloqueo.
        if (risk >= 0.85) {
            record(number, risk, intent, OUTCOME_BLOCKED_SILENT, message, now)
            respondToCall(call, CallBlocker.blockSilently())
            return
        }

        // 2. Bloqueo opcional de cualquier número desconocido. Va antes del
        //    umbral porque es una decisión explícita del usuario.
        if (isUnknownCaller && SentraVoxPrefs.blockUnknown(this)) {
            record(number, risk, intent, OUTCOME_BLOCKED_NOTIFIED, message, now)
            respondToCall(call, CallBlocker.blockAndNotify())
            return
        }

        // 3. Desconocido que debe atender el agente. Se comprueba antes del
        //    umbral de bloqueo: si el usuario quiere que el agente conteste a
        //    los desconocidos, bloquearlos por el riesgo genérico de «número
        //    sin identificar» vaciaría de sentido la función.
        if (isUnknownCaller &&
            SentraVoxPrefs.autoActivateAgent(this) &&
            risk < RiskEvaluator.RISK_AGENT_CEILING
        ) {
            record(number, risk, intent, OUTCOME_AGENT, message, now)
            notifyFlutter("activate_agent", mapOf("number" to number, "risk" to risk))
            AgentActivationLauncher.launch(this, number, risk, now)

            // Dejar pasar la llamada primero: `acceptRingingCall()` no puede
            // contestar algo que Telecom todavía no ha puesto a sonar.
            respondToCall(call, allowCall())

            // Y descolgar desde aquí, no desde la pantalla del agente: si
            // Android no nos deja abrir la Activity en segundo plano —lo
            // habitual—, la llamada se quedaba sonando sin que nadie la
            // contestara.
            if (SentraVoxPrefs.autoAnswer(this)) {
                AutoAnswer.schedule(this)
            }
            return
        }

        // 4. Riesgo por encima del umbral del usuario.
        if (risk >= threshold) {
            record(number, risk, intent, OUTCOME_BLOCKED_NOTIFIED, message, now)
            respondToCall(call, CallBlocker.blockAndNotify())
            return
        }

        // 5. Contacto conocido con «atender todas las llamadas»: también pasa
        //    al agente. Va después del umbral para que un contacto con riesgo
        //    alto siga bloqueándose.
        if (!isUnknownCaller &&
            SentraVoxPrefs.autoActivateAgent(this) &&
            SentraVoxPrefs.agentAllCalls(this) &&
            risk < RiskEvaluator.RISK_AGENT_CEILING
        ) {
            record(number, risk, intent, OUTCOME_AGENT, message, now)
            notifyFlutter("activate_agent", mapOf("number" to number, "risk" to risk))
            AgentActivationLauncher.launch(this, number, risk, now)
            respondToCall(call, allowCall())

            if (SentraVoxPrefs.autoAnswer(this)) {
                AutoAnswer.schedule(this)
            }
            return
        }

        // 6. Contacto conocido: pasa sin intervención.
        record(number, risk, intent, OUTCOME_ALLOWED, message, now)
        respondToCall(call, allowCall())
    }

    /**
     * Un desconocido es quien no está en los contactos.
     *
     * `callerDisplayName` solo trae algo cuando la red envía el nombre (CNAP),
     * que en la práctica casi nunca ocurre, así que usarlo como única señal
     * daba un «desconocido» poco fiable. La consulta a contactos requiere
     * READ_CONTACTS; sin ese permiso se cae al comportamiento anterior.
     */
    private fun isUnknownCaller(call: Details, rawNumber: String): Boolean {
        return when (contactExists(rawNumber)) {
            true -> false
            false -> true
            null -> call.callerDisplayName.isNullOrBlank()
        }
    }

    /** true/false si se pudo consultar; null si no hay permiso o falló. */
    private fun contactExists(rawNumber: String): Boolean? {
        // Número oculto: no hay nada que buscar y desde luego no es un contacto.
        if (rawNumber.isBlank()) return false

        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }

        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(rawNumber)
        )

        return try {
            contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup._ID),
                null,
                null,
                null
            )?.use { cursor -> cursor.moveToFirst() } ?: false
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo consultar contactos", e)
            null
        }
    }

    private fun record(
        number: String,
        risk: Double,
        intent: String,
        outcome: String,
        message: String,
        timestamp: Long
    ) {
        try {
            SentraVoxPrefs.recordEvent(
                context = this,
                number = number,
                risk = risk,
                intent = intent,
                outcome = outcome,
                message = message,
                timestampMillis = timestamp
            )

            // Rastro que no se borra al importar: es la prueba de que Android
            // sí invocó el servicio de filtrado.
            SentraVoxPrefs.recordLastScreening(
                context = this,
                number = number,
                risk = risk,
                outcome = outcome,
                timestampMillis = timestamp
            )
        } catch (e: Throwable) {
            // Nunca dejar que el registro tumbe el screening.
            Log.e(TAG, "No se pudo encolar el evento de screening", e)
        }
    }

    private fun notifyFlutter(method: String, arguments: Map<String, Any?>) {
        val channel = flutterChannel ?: return
        try {
            channel.invokeMethod(method, arguments)
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo notificar a Flutter ($method)", e)
        }
    }

    private fun allowCall(): CallResponse {
        return CallResponse.Builder()
            .setDisallowCall(false)
            .setSilenceCall(false)
            .setSkipCallLog(false)
            .setSkipNotification(false)
            .build()
    }
}
