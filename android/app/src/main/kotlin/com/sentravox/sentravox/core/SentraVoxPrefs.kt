package com.sentravox.sentravox.core

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Fuente de verdad compartida entre Dart y el lado nativo.
 *
 * `AgentCallScreeningService` puede ejecutarse sin que haya un FlutterEngine
 * vivo (la llamada entra con la app cerrada), así que no puede consultar la
 * configuración por MethodChannel ni escribir en la base sqflite de Dart. Por
 * eso los ajustes, la lista de bloqueo y los eventos de screening pendientes
 * viven en SharedPreferences: ambos lados los leen sin depender del otro.
 *
 * Dart escribe los ajustes y drena los eventos pendientes al arrancar; el
 * servicio nativo solo lee ajustes y encola eventos.
 */
object SentraVoxPrefs {

    private const val FILE = "sentravox_prefs"

    const val KEY_SECURITY_ENABLED = "security_enabled"
    const val KEY_AUTO_ACTIVATE_AGENT = "auto_activate_agent"
    const val KEY_AGENT_ALL_CALLS = "agent_all_calls"
    const val KEY_AUTO_ANSWER = "auto_answer"
    const val KEY_BLOCK_UNKNOWN = "block_unknown"
    const val KEY_BLOCK_THRESHOLD = "block_threshold"

    const val KEY_AGENT_NAME = "agent_name"
    const val KEY_AGENT_COMPANY = "agent_company"
    const val KEY_AGENT_ROLE = "agent_role"
    const val KEY_AGENT_PERSONALITY = "agent_personality"
    const val KEY_OWNER_NAME = "owner_name"
    const val KEY_OWNER_TITLE = "owner_title"
    const val KEY_VOICE_GENDER = "voice_gender"
    const val KEY_VOICE_ID = "voice_id"
    const val KEY_VOICE_PROFILE = "voice_profile"
    const val KEY_SPEECH_RATE = "speech_rate"
    const val KEY_VOICE_PITCH = "voice_pitch"
    const val KEY_VOICE_FORMALITY = "voice_formality"
    const val KEY_IN_CALL_AUDIO_MODE = "in_call_audio_mode"
    const val KEY_LLM_ENABLED = "llm_enabled"
    const val KEY_LLM_ENDPOINT = "llm_endpoint"
    const val KEY_LLM_MODEL = "llm_model"
    const val KEY_LLM_API_KEY = "llm_api_key"

    private const val KEY_BLOCKLIST = "blocklist"
    private const val KEY_PENDING_EVENTS = "pending_events"
    private const val KEY_PENDING_AGENT = "pending_agent"
    private const val KEY_LAST_SCREENING = "last_screening"

    private const val DEFAULT_THRESHOLD = 0.6f
    private const val MAX_PENDING_EVENTS = 200

    private val lock = Any()

    private fun prefs(context: Context) =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    // ---------------------------------------------------------------------
    // Ajustes
    // ---------------------------------------------------------------------

    fun securityEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_SECURITY_ENABLED, true)

    fun autoActivateAgent(context: Context): Boolean =
        prefs(context).getBoolean(KEY_AUTO_ACTIVATE_AGENT, true)

    fun agentAllCalls(context: Context): Boolean =
        prefs(context).getBoolean(KEY_AGENT_ALL_CALLS, false)

    fun autoAnswer(context: Context): Boolean =
        prefs(context).getBoolean(KEY_AUTO_ANSWER, true)

    fun blockUnknown(context: Context): Boolean =
        prefs(context).getBoolean(KEY_BLOCK_UNKNOWN, false)

    fun blockThreshold(context: Context): Double =
        prefs(context).getFloat(KEY_BLOCK_THRESHOLD, DEFAULT_THRESHOLD).toDouble()

    fun snapshot(context: Context): Map<String, Any> = mapOf(
        KEY_SECURITY_ENABLED to securityEnabled(context),
        KEY_AUTO_ACTIVATE_AGENT to autoActivateAgent(context),
        KEY_AGENT_ALL_CALLS to agentAllCalls(context),
        KEY_AUTO_ANSWER to autoAnswer(context),
        KEY_BLOCK_UNKNOWN to blockUnknown(context),
        KEY_BLOCK_THRESHOLD to blockThreshold(context),
        KEY_AGENT_NAME to (prefs(context).getString(KEY_AGENT_NAME, "SentraVox") ?: "SentraVox"),
        KEY_AGENT_COMPANY to (prefs(context).getString(KEY_AGENT_COMPANY, "") ?: ""),
        KEY_AGENT_ROLE to (prefs(context).getString(KEY_AGENT_ROLE, "recepcionista") ?: "recepcionista"),
        KEY_AGENT_PERSONALITY to (prefs(context).getString(KEY_AGENT_PERSONALITY, "profesional, amable y eficiente") ?: "profesional, amable y eficiente"),
        KEY_OWNER_NAME to (prefs(context).getString(KEY_OWNER_NAME, "") ?: ""),
        KEY_OWNER_TITLE to (prefs(context).getString(KEY_OWNER_TITLE, "") ?: ""),
        KEY_VOICE_PROFILE to voiceProfile(context),
        KEY_VOICE_GENDER to voiceGenderForProfile(voiceProfile(context)),
        KEY_VOICE_ID to (prefs(context).getString(KEY_VOICE_ID, "") ?: ""),
        KEY_SPEECH_RATE to speechRateForProfile(voiceProfile(context)).toDouble(),
        KEY_VOICE_PITCH to pitchForProfile(voiceProfile(context)).toDouble(),
        KEY_VOICE_FORMALITY to (prefs(context).getString(KEY_VOICE_FORMALITY, "profesional") ?: "profesional"),
        KEY_IN_CALL_AUDIO_MODE to (prefs(context).getString(KEY_IN_CALL_AUDIO_MODE, "acoustic") ?: "acoustic"),
        KEY_LLM_ENABLED to prefs(context).getBoolean(KEY_LLM_ENABLED, true),
        KEY_LLM_ENDPOINT to (prefs(context).getString(KEY_LLM_ENDPOINT, "https://api.openai.com/v1/chat/completions") ?: ""),
        KEY_LLM_MODEL to (prefs(context).getString(KEY_LLM_MODEL, "gpt-4o-mini") ?: "gpt-4o-mini"),
        KEY_LLM_API_KEY to (prefs(context).getString(KEY_LLM_API_KEY, "") ?: "")
    )

    // ---------------------------------------------------------------------
    // Perfiles de voz (5 opciones cerradas)
    // ---------------------------------------------------------------------

    fun voiceProfile(context: Context): String =
        prefs(context).getString(KEY_VOICE_PROFILE, "femenina_natural")
            ?: "femenina_natural"

    fun voiceGenderForProfile(profile: String): String = when (profile) {
        "masculina_natural", "masculina_serena" -> "masculina"
        else -> "femenina"
    }

    fun speechRateForProfile(profile: String): Float = when (profile) {
        "femenina_calida", "masculina_serena" -> 0.82f
        "neutra_profesional" -> 0.90f
        else -> 0.88f
    }

    fun pitchForProfile(profile: String): Float = when (profile) {
        "femenina_calida" -> 1.05f
        "masculina_natural" -> 0.92f
        "masculina_serena" -> 0.95f
        else -> 1.0f
    }

    fun setBoolean(context: Context, key: String, value: Boolean) {
        prefs(context).edit().putBoolean(key, value).apply()
    }

    fun setDouble(context: Context, key: String, value: Double) {
        prefs(context).edit().putFloat(key, value.toFloat()).apply()
    }

    fun setString(context: Context, key: String, value: String) {
        prefs(context).edit().putString(key, value).apply()
    }

    // ---------------------------------------------------------------------
    // Lista de bloqueo
    // ---------------------------------------------------------------------

    fun blocklist(context: Context): Set<String> {
        val raw = prefs(context).getString(KEY_BLOCKLIST, "") ?: ""
        if (raw.isEmpty()) return emptySet()
        return raw.split('\n').filter { it.isNotBlank() }.toSet()
    }

    fun setBlocklist(context: Context, numbers: List<String>) {
        val cleaned = numbers.map { normalizeNumber(it) }.filter { it.isNotEmpty() }.distinct()
        prefs(context).edit().putString(KEY_BLOCKLIST, cleaned.joinToString("\n")).apply()
    }

    /** Solo dígitos, para que el formato del marcado no afecte la comparación. */
    fun normalizeNumber(number: String): String = number.filter { it.isDigit() }

    // ---------------------------------------------------------------------
    // Rastro para diagnóstico
    // ---------------------------------------------------------------------

    /**
     * Última decisión de filtrado, **sin borrarse al leerla**.
     *
     * La cola de eventos se vacía al importarla al historial, así que no sirve
     * para responder a la pregunta que importa cuando algo no funciona: ¿llegó
     * Android a invocar el servicio de filtrado? Si aquí no hay nada, el
     * problema es el permiso de filtrado y no el agente.
     */
    fun recordLastScreening(
        context: Context,
        number: String,
        risk: Double,
        outcome: String,
        timestampMillis: Long
    ) {
        val json = JSONObject().apply {
            put("number", number)
            put("risk", risk)
            put("outcome", outcome)
            put("timestamp", timestampMillis)
        }
        prefs(context).edit().putString(KEY_LAST_SCREENING, json.toString()).commit()
    }

    fun lastScreening(context: Context): Map<String, Any?>? {
        val raw = prefs(context).getString(KEY_LAST_SCREENING, null) ?: return null

        return try {
            val item = JSONObject(raw)
            mapOf(
                "number" to item.optString("number"),
                "risk" to item.optDouble("risk", 0.0),
                "outcome" to item.optString("outcome"),
                "timestamp" to item.optLong("timestamp")
            )
        } catch (e: Exception) {
            null
        }
    }

    // ---------------------------------------------------------------------
    // Activación pendiente del agente
    // ---------------------------------------------------------------------

    /**
     * Deja anotado que una llamada debe atenderla el agente.
     *
     * El `MethodChannel` solo llega a Dart si hay UI viva, y una llamada entra
     * casi siempre con la app en segundo plano o cerrada. Anotarlo aquí es lo
     * que permite que la pantalla del agente se abra igualmente en cuanto la UI
     * arranca o vuelve al frente.
     */
    fun setPendingActivation(
        context: Context,
        number: String,
        risk: Double,
        timestampMillis: Long
    ) {
        synchronized(lock) {
            val json = JSONObject().apply {
                put("number", number)
                put("risk", risk)
                put("timestamp", timestampMillis)
            }
            // commit() y no apply(): el proceso puede morir en cuanto termina
            // onScreenCall y una escritura asíncrona se perdería.
            prefs(context).edit().putString(KEY_PENDING_AGENT, json.toString()).commit()
        }
    }

    /**
     * Lee y limpia: la pantalla del agente se abre una sola vez por llamada.
     *
     * Retira además el evento `agent` correspondiente de la cola de historial:
     * si el agente atiende la llamada será él quien la registre, con
     * transcripción y resumen, y si no se retirara aquí la misma llamada
     * aparecería dos veces en el historial —una de ellas vacía—.
     */
    fun consumePendingActivation(context: Context): Map<String, Any?>? {
        synchronized(lock) {
            val store = prefs(context)
            val raw = store.getString(KEY_PENDING_AGENT, null) ?: return null
            store.edit().remove(KEY_PENDING_AGENT).commit()

            return try {
                val item = JSONObject(raw)
                val number = item.optString("number")
                val timestamp = item.optLong("timestamp")

                dropAgentEvent(store, number, timestamp)

                mapOf(
                    "number" to number,
                    "risk" to item.optDouble("risk", 0.0),
                    "timestamp" to timestamp
                )
            } catch (e: Exception) {
                null
            }
        }
    }

    /** Quita de la cola el evento de derivación al agente ya atendido. */
    private fun dropAgentEvent(
        store: android.content.SharedPreferences,
        number: String,
        timestampMillis: Long
    ) {
        val array = readArray(store)
        if (array.length() == 0) return

        val kept = JSONArray()
        var dropped = false

        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue

            val sameCall = !dropped &&
                item.optString("outcome") == "agent" &&
                item.optString("number") == number &&
                kotlin.math.abs(item.optLong("timestamp") - timestampMillis) < 5_000

            if (sameCall) {
                dropped = true
                continue
            }

            kept.put(item)
        }

        if (dropped) {
            store.edit().putString(KEY_PENDING_EVENTS, kept.toString()).commit()
        }
    }

    // ---------------------------------------------------------------------
    // Cola de eventos de screening
    // ---------------------------------------------------------------------

    fun recordEvent(
        context: Context,
        number: String,
        risk: Double,
        intent: String,
        outcome: String,
        message: String,
        timestampMillis: Long
    ) {
        synchronized(lock) {
            val store = prefs(context)
            val array = readArray(store)

            array.put(
                JSONObject().apply {
                    put("number", number)
                    put("risk", risk)
                    put("intent", intent)
                    put("outcome", outcome)
                    put("message", message)
                    put("timestamp", timestampMillis)
                }
            )

            // Cota superior: si Dart nunca arranca, no crecer sin límite.
            val trimmed = if (array.length() > MAX_PENDING_EVENTS) {
                JSONArray().also { out ->
                    for (i in (array.length() - MAX_PENDING_EVENTS) until array.length()) {
                        out.put(array.get(i))
                    }
                }
            } else {
                array
            }

            store.edit().putString(KEY_PENDING_EVENTS, trimmed.toString()).apply()
        }
    }

    /** Lee y limpia de forma atómica: Dart no puede importar duplicados. */
    fun drainEvents(context: Context): List<Map<String, Any?>> {
        synchronized(lock) {
            val store = prefs(context)
            val array = readArray(store)
            store.edit().remove(KEY_PENDING_EVENTS).apply()

            val events = mutableListOf<Map<String, Any?>>()
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                events.add(
                    mapOf(
                        "number" to item.optString("number"),
                        "risk" to item.optDouble("risk", 0.0),
                        "intent" to item.optString("intent"),
                        "outcome" to item.optString("outcome"),
                        "message" to item.optString("message"),
                        "timestamp" to item.optLong("timestamp")
                    )
                )
            }
            return events
        }
    }

    private fun readArray(store: android.content.SharedPreferences): JSONArray {
        val raw = store.getString(KEY_PENDING_EVENTS, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (e: Exception) {
            JSONArray()
        }
    }
}
