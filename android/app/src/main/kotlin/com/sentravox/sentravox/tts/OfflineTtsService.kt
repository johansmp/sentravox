package com.sentravox.sentravox.tts

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import com.sentravox.sentravox.core.SentraVoxPrefs
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale

/**
 * Puente TTS.
 *
 * `speak` no responde al invocarse: la respuesta del MethodChannel se aplaza
 * hasta que el motor termina de hablar (`onDone`), devolviendo `true`, o hasta
 * que se interrumpe (`onStop`) o falla (`onError`), devolviendo `false`.
 *
 * Esto es lo que permite el turno de palabra: Dart puede esperar a que el
 * agente calle antes de volver a abrir el micrófono, en lugar de reabrirlo de
 * inmediato y transcribir la propia voz del agente.
 *
 * Durante una llamada hay dos rutas:
 * - `acoustic` (por defecto): se sintetiza a un WAV y se reproduce con
 *   `MediaPlayer` por el altavoz. El micrófono del teléfono recoge la voz y la
 *   transmite. Es la ruta que funciona en más dispositivos.
 * - `direct` (experimental): el mismo WAV se decodifica y se envía a un
 *   `AudioTrack` con `USAGE_VOICE_COMMUNICATION`. Algunos HAL de fabricante
 *   mezclan esa pista en la llamada; Android no lo garantiza. Si falla, se cae
 *   automáticamente a la ruta acústica.
 */
class OfflineTtsService(
    private val activity: Activity,
    private val methodChannel: MethodChannel
) : TextToSpeech.OnInitListener {

    private companion object {
        const val TAG = "SentraVoxTts"
        const val PREF = "sentravox_prefs"
        const val GOOGLE_ENGINE = "com.google.android.tts"

        // Nombres que los motores suelen usar para marcar el género de la voz.
        val FEMALE_HINTS = listOf(
            "female", "femenina", "mujer", "#f", "-f-", "ela", "laura", "sara",
            "sofia", "carmela", "monica", "paula", "maria", "isabela", "salome",
            "ximena", "valentina", "camila", "lucia", "ana", "luz", "diana"
        )
        val MALE_HINTS = listOf(
            "male", "masculina", "hombre", "#m", "-m-", "jorge", "carlos",
            "diego", "andres", "santiago", "pablo", "javier", "miguel", "alvaro",
            "juan", "pedro", "luis", "ricardo", "felipe", "sebastian"
        )
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager =
        activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    private var tts: TextToSpeech? = null
    private var isReady: Boolean = false
    private var initFailed: Boolean = false
    private var triedFallbackEngine: Boolean = false

    private var utteranceCounter: Int = 0
    private var currentUtteranceId: String? = null
    private var pendingResult: MethodChannel.Result? = null

    /** Si true, el TTS se está usando dentro de una llamada telefónica. */
    private var inCall: Boolean = false
    private var injectionMode: String = "acoustic"

    /** Síntesis a archivo en curso (ruta de inyección). */
    private var synthesizingIntoCall: Boolean = false
    private var pendingIntoCallFile: File? = null
    private var mediaPlayer: MediaPlayer? = null
    private var audioTrack: AudioTrack? = null
    private var audioTrackThread: Thread? = null

    private var selectedVoice: String = ""

    /** El motor tarda en inicializarse; si llega un speak() antes, se encola. */
    private var queuedText: String? = null
    private var queuedResult: MethodChannel.Result? = null

    init {
        createEngine(GOOGLE_ENGINE)

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> speak(call.argument<String>("text") ?: "", result)
                "speakWav" -> speakWav(call.argument<String>("path") ?: "", result)
                "stop" -> {
                    stop()
                    result.success(null)
                }
                "isSpeaking" -> result.success(isSpeaking())
                "voices" -> result.success(voices())
                "audioDiagnostics" -> result.success(audioDiagnostics())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Crea el motor. Se prefiere Google (voces neuronales) y, si no está o
     * falla al inicializar, se reintenta con el motor por defecto del sistema.
     */
    private fun createEngine(engineName: String?) {
        try {
            tts?.shutdown()
        } catch (_: Throwable) {
        }

        tts = if (engineName != null) {
            try {
                TextToSpeech(activity, this, engineName)
            } catch (e: Throwable) {
                Log.w(TAG, "No se pudo crear el motor $engineName", e)
                null
            }
        } else {
            null
        }

        if (tts == null) {
            tts = try {
                TextToSpeech(activity, this)
            } catch (e: Throwable) {
                Log.e(TAG, "No se pudo crear ningún motor TTS", e)
                initFailed = true
                null
            }
        }
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            Log.e(TAG, "No se pudo inicializar TextToSpeech (status=$status)")

            // El motor de Google puede estar instalado pero sin datos. Se
            // reintenta una vez con el motor por defecto antes de rendirse.
            if (!triedFallbackEngine) {
                triedFallbackEngine = true
                Log.i(TAG, "Reintentando con el motor TTS por defecto")
                createEngine(null)
                return
            }

            initFailed = true
            drainQueue(failure = "El motor de voz no está disponible.")
            return
        }

        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}

            override fun onDone(utteranceId: String?) {
                if (synthesizingIntoCall &&
                    (utteranceId == null || utteranceId == currentUtteranceId)
                ) {
                    synthesizingIntoCall = false
                    val file = pendingIntoCallFile
                    pendingIntoCallFile = null
                    if (file != null && file.exists()) {
                        playIntoCall(file, utteranceId)
                        return
                    }
                }
                settleOnMain(utteranceId, completed = true)
            }

            @Suppress("OVERRIDE_DEPRECATION")
            override fun onError(utteranceId: String?) {
                settleOnMain(utteranceId, completed = false)
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                settleOnMain(utteranceId, completed = false)
            }

            override fun onStop(utteranceId: String?, interrupted: Boolean) {
                settleOnMain(utteranceId, completed = false)
            }
        })

        val colombian = Locale("es", "CO")
        val available = tts?.isLanguageAvailable(colombian)
        tts?.language = if (available == TextToSpeech.LANG_AVAILABLE ||
            available == TextToSpeech.LANG_COUNTRY_AVAILABLE ||
            available == TextToSpeech.LANG_COUNTRY_VAR_AVAILABLE
        ) {
            colombian
        } else {
            Locale("es")
        }

        isReady = true
        applyVoiceSettings()

        val text = queuedText
        val result = queuedResult
        queuedText = null
        queuedResult = null
        if (text != null && result != null) {
            doSpeak(text, result)
        }
    }

    /**
     * Manda la voz del agente por la ruta de comunicación (la de la llamada) o
     * la devuelve a multimedia.
     *
     * Sin esto el TTS sale por el altavoz de multimedia, que durante una
     * llamada queda atenuado y no llega al interlocutor.
     */
    fun setInCallAudio(enabled: Boolean) {
        inCall = enabled
        injectionMode = activity
            .getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .getString("in_call_audio_mode", "acoustic") ?: "acoustic"

        val attributes = AudioAttributes.Builder()
            .setUsage(
                if (enabled) {
                    AudioAttributes.USAGE_VOICE_COMMUNICATION
                } else {
                    AudioAttributes.USAGE_ASSISTANT
                }
            )
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

        try {
            tts?.setAudioAttributes(attributes)
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo fijar la ruta de audio del TTS", e)
        }
    }

    private fun speak(text: String, result: MethodChannel.Result) {
        if (text.isEmpty()) {
            result.success(true)
            return
        }

        applyVoiceSettings()

        if (inCall) {
            speakIntoCall(text, result)
            return
        }

        if (initFailed) {
            result.error("tts_unavailable", "El motor de voz no está disponible.", null)
            return
        }

        if (!isReady) {
            // Solo se guarda el último: un speak nuevo reemplaza al encolado.
            queuedResult?.success(false)
            queuedText = text
            queuedResult = result
            return
        }

        doSpeak(text, result)
    }

    private fun doSpeak(text: String, result: MethodChannel.Result) {
        // QUEUE_FLUSH corta lo anterior: se cierra su Future como no completado.
        settle(completed = false)

        val id = "sentravox_${++utteranceCounter}"
        currentUtteranceId = id
        pendingResult = result

        val status = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
        if (status != TextToSpeech.SUCCESS) {
            currentUtteranceId = null
            pendingResult = null
            result.error("tts_error", "TextToSpeech.speak falló (status=$status).", null)
        }
    }

    // -------------------------------------------------------------------------
    // Voz: selección real de la voz configurada
    // -------------------------------------------------------------------------

    private fun applyVoiceSettings() {
        val prefs = activity.getSharedPreferences(PREF, Context.MODE_PRIVATE)

        val profile = SentraVoxPrefs.voiceProfile(activity)
        try {
            tts?.setSpeechRate(SentraVoxPrefs.speechRateForProfile(profile))
            tts?.setPitch(SentraVoxPrefs.pitchForProfile(profile))
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudieron aplicar los ajustes de ritmo/tono", e)
        }

        try {
            val voices = tts?.voices ?: emptySet()
            if (voices.isEmpty()) return

            val wantedId = prefs.getString("voice_id", "") ?: ""
            val gender = SentraVoxPrefs.voiceGenderForProfile(profile)

            // Si la voz guardada ya no existe en este motor (otro teléfono,
            // otra versión del TTS), se elige automáticamente por género.
            val explicit = if (wantedId.isNotEmpty()) {
                voices.firstOrNull { it.name == wantedId }
            } else {
                null
            }
            val chosen = explicit ?: pickVoice(voices, gender)

            if (chosen != null) {
                tts?.voice = chosen
                selectedVoice = chosen.name
                Log.i(
                    TAG,
                    "Voz seleccionada: ${chosen.name} " +
                        "(calidad ${chosen.quality}, red ${chosen.isNetworkConnectionRequired})"
                )
            } else {
                Log.w(TAG, "No se encontró una voz en español; se usa la del motor")
            }
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo seleccionar la voz", e)
        }
    }

    /**
     * Elige la mejor voz española que case con el género configurado.
     *
     * Android no expone el género como API: se usa el nombre de la voz como
     * pista y, si no hay coincidencia, se prioriza una voz local de calidad.
     */
    private fun pickVoice(voices: Set<Voice>, gender: String): Voice? {
        val spanish = voices.filter { it.locale.language == "es" }
        if (spanish.isEmpty()) return null

        val local = spanish.filter { !it.isNetworkConnectionRequired }
        val pool = if (local.isNotEmpty()) local else spanish

        val gendered = pool.filter { matchesGender(it, gender) }
        val candidates = if (gendered.isNotEmpty()) gendered else pool

        return candidates.maxWithOrNull(
            compareBy<Voice> { if (it.locale.country == "CO") 1 else 0 }
                .thenBy { it.quality }
                .thenBy { if (!it.isNetworkConnectionRequired) 1 else 0 }
        )
    }

    private fun matchesGender(voice: Voice, gender: String): Boolean {
        val name = voice.name.lowercase(Locale.ROOT)
        if (gender == "masculina") {
            // «female» contiene «male»: hay que descartarlo antes de buscar.
            if (name.contains("female") || name.contains("femenina")) return false
            return MALE_HINTS.any { name.contains(it) }
        }
        return FEMALE_HINTS.any { name.contains(it) }
    }

    private fun voices(): List<Map<String, Any?>> {
        val all = tts?.voices ?: emptySet()
        return all
            .filter { it.locale.language == "es" }
            .sortedWith(
                compareByDescending<Voice> { it.locale.country == "CO" }
                    .thenByDescending { it.quality }
                    .thenBy { it.name }
            )
            .map { voice ->
                mapOf(
                    "name" to voice.name,
                    "locale" to voice.locale.toLanguageTag(),
                    "quality" to voice.quality,
                    "network" to voice.isNetworkConnectionRequired,
                    "gender" to when {
                        matchesGender(voice, "masculina") -> "masculina"
                        matchesGender(voice, "femenina") -> "femenina"
                        else -> "desconocida"
                    }
                )
            }
    }

    private fun audioDiagnostics(): Map<String, Any?> {
        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager?.communicationDevice?.type
        } else {
            null
        }

        return mapOf(
            "ready" to isReady,
            "in_call" to inCall,
            "injection_mode" to injectionMode,
            "voice" to selectedVoice,
            "engine" to tts?.engines?.firstOrNull()?.name,
            "mode" to audioManager?.mode,
            "speaker_on" to audioManager?.isSpeakerphoneOn,
            "communication_device" to device
        )
    }

    private fun isSpeaking(): Boolean {
        return (tts?.isSpeaking ?: false) ||
            (mediaPlayer?.isPlaying ?: false) ||
            (audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING)
    }

    // -------------------------------------------------------------------------
    // Ruta dentro de la llamada
    // -------------------------------------------------------------------------

    /**
     * Reproduce un WAV ya sintetizado (TTS neuronal local).
     *
     * Usa la misma ruta que el TTS del sistema: si estamos en llamada, sale por
     * `AudioTrack`/`MediaPlayer` con `USAGE_VOICE_COMMUNICATION`; fuera de la
     * llamada, por el altavoz multimedia. La respuesta se aplaza hasta que
     * termina la reproducción, igual que `speak`.
     */
    private fun speakWav(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists() || file.length() == 0L) {
            result.error("tts_wav_missing", "No se encontró el WAV: $path", null)
            return
        }

        settle(completed = false)
        releasePlayback()

        val id = "sentravox_wav_${++utteranceCounter}"
        currentUtteranceId = id
        pendingResult = result

        if (inCall) {
            playIntoCall(file, id)
        } else {
            playWithMediaPlayer(file, id, forCall = false)
        }
    }

    private fun speakIntoCall(text: String, result: MethodChannel.Result) {        applyVoiceSettings()

        // La ruta pudo cambiar desde el inicio de la llamada: se relee para que
        // el selector de Configuración tenga efecto en el siguiente turno.
        injectionMode = activity
            .getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .getString("in_call_audio_mode", "acoustic") ?: "acoustic"

        if (initFailed) {
            result.error("tts_unavailable", "El motor de voz no está disponible.", null)
            return
        }
        if (!isReady) {
            queuedResult?.success(false)
            queuedText = text
            queuedResult = result
            return
        }

        // Cancela cualquier locución anterior.
        settle(completed = false)
        releasePlayback()

        val id = "sentravox_${++utteranceCounter}"
        currentUtteranceId = id
        pendingResult = result
        synthesizingIntoCall = true
        val file = File(activity.cacheDir, "sv_tts_$id.wav")
        pendingIntoCallFile = file
        if (file.exists()) file.delete()

        val status = tts?.synthesizeToFile(text, null, file, id)
        if (status != TextToSpeech.SUCCESS) {
            synthesizingIntoCall = false
            pendingIntoCallFile = null
            currentUtteranceId = null
            pendingResult = null
            doSpeak(text, result)
        }
    }

    private fun playIntoCall(file: File, utteranceId: String?) {
        mainHandler.post {
            if (utteranceId != null && utteranceId != currentUtteranceId) {
                file.delete()
                return@post
            }

            if (injectionMode == "direct" || injectionMode == "auto") {
                val started = startAudioTrack(file, utteranceId)
                if (started) return@post

                Log.w(
                    TAG,
                    "AudioTrack no pudo reproducir el WAV; se usa MediaPlayer"
                )
            }

            playWithMediaPlayer(file, utteranceId, forCall = true)
        }
    }

    /**
     * Intento de inyección directa con AudioTrack.
     *
     * Se reproduce con USAGE_VOICE_COMMUNICATION y el dispositivo de
     * comunicación actual. En los equipos cuyo HAL mezcla esa pista en la
     * llamada, el interlocutor la oye sin depender del micrófono; en el resto
     * suena por el altavoz como la ruta acústica. No es una API garantizada.
     */
    private fun startAudioTrack(file: File, utteranceId: String?): Boolean {
        // AudioTrack.Builder existe desde API 23. En versiones anteriores se
        // usa directamente la ruta acústica.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false

        val format = parseWav(file) ?: return false

        return try {
            val channelMask = if (format.channels == 1) {
                AudioFormat.CHANNEL_OUT_MONO
            } else {
                AudioFormat.CHANNEL_OUT_STEREO
            }

            val minBuffer = AudioTrack.getMinBufferSize(
                format.sampleRate,
                channelMask,
                AudioFormat.ENCODING_PCM_16BIT
            )
            if (minBuffer <= 0) return false

            val builder = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(format.sampleRate)
                        .setChannelMask(channelMask)
                        .build()
                )
                .setBufferSizeInBytes(minBuffer * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)

            val track = builder.build()
            if (track.state != AudioTrack.STATE_INITIALIZED) {
                track.release()
                return false
            }

            // Enrutar al dispositivo de comunicación actual (altavoz durante
            // una llamada). Si el sistema no lo permite, se ignora.
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    audioManager?.communicationDevice?.let { track.preferredDevice = it }
                }
            } catch (e: Throwable) {
                Log.w(TAG, "No se pudo fijar el dispositivo del AudioTrack", e)
            }

            audioTrack = track
            track.play()

            val data = file.readBytes()
            val payload = data.copyOfRange(
                format.dataOffset,
                (format.dataOffset + format.dataSize).coerceAtMost(data.size)
            )
            file.delete()

            audioTrackThread = Thread {
                var completed = true
                try {
                    var offset = 0
                    while (offset < payload.size && !Thread.currentThread().isInterrupted) {
                        val written = track.write(payload, offset, payload.size - offset)
                        if (written < 0) throw IllegalStateException("AudioTrack.write=$written")
                        offset += written
                    }

                    if (!Thread.currentThread().isInterrupted) {
                        // El último bloque sigue en el búfer: esperar su
                        // duración antes de darlo por terminado, o la voz se
                        // cortaría al final de cada frase.
                        val bytesPerSecond =
                            format.sampleRate * format.channels * 2
                        val bufferMs = if (bytesPerSecond > 0) {
                            (minBuffer * 1000L / bytesPerSecond)
                                .coerceIn(80L, 600L)
                        } else {
                            150L
                        }
                        Thread.sleep(bufferMs + 80)
                    }
                } catch (e: Throwable) {
                    completed = false
                    Log.w(TAG, "Fallo reproduciendo el AudioTrack", e)
                } finally {
                    try {
                        track.stop()
                    } catch (_: Throwable) {
                    }
                    try {
                        track.release()
                    } catch (_: Throwable) {
                    }
                    if (audioTrack === track) audioTrack = null
                    settleOnMain(utteranceId, completed = completed)
                }
            }.also { it.start() }

            true
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo iniciar AudioTrack", e)
            audioTrack?.release()
            audioTrack = null
            false
        }
    }

    private fun playWithMediaPlayer(
        file: File,
        utteranceId: String?,
        forCall: Boolean = true
    ) {
        try {
            mediaPlayer?.release()
            val mp = MediaPlayer()
            mediaPlayer = mp
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(
                        if (forCall) {
                            AudioAttributes.USAGE_VOICE_COMMUNICATION
                        } else {
                            AudioAttributes.USAGE_ASSISTANT
                        }
                    )
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            mp.setDataSource(file.absolutePath)
            mp.setOnCompletionListener {
                file.delete()
                settleOnMain(utteranceId, completed = true)
                it.release()
                if (mediaPlayer === it) mediaPlayer = null
            }
            mp.setOnErrorListener { mpErr, _, _ ->
                file.delete()
                settleOnMain(utteranceId, completed = false)
                mpErr.release()
                if (mediaPlayer === mpErr) mediaPlayer = null
                true
            }
            mp.prepare()
            mp.start()
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo reproducir el audio en la llamada", e)
            file.delete()
            settleOnMain(utteranceId, completed = false)
        }
    }

    /** Formato PCM de un WAV generado por `synthesizeToFile`. */
    private data class WavFormat(
        val sampleRate: Int,
        val channels: Int,
        val bitsPerSample: Int,
        val dataOffset: Int,
        val dataSize: Int
    )

    private fun parseWav(file: File): WavFormat? {
        return try {
            val bytes = file.readBytes()
            if (bytes.size < 44) return null
            if (String(bytes, 0, 4, Charsets.US_ASCII) != "RIFF") return null
            if (String(bytes, 8, 4, Charsets.US_ASCII) != "WAVE") return null

            var sampleRate = 0
            var channels = 0
            var bits = 0
            var dataOffset = -1
            var dataSize = 0

            var offset = 12
            while (offset + 8 <= bytes.size) {
                val id = String(bytes, offset, 4, Charsets.US_ASCII)
                val size = ByteBuffer.wrap(bytes, offset + 4, 4)
                    .order(ByteOrder.LITTLE_ENDIAN)
                    .int

                if (size < 0) return null
                val body = offset + 8

                when (id) {
                    "fmt " -> {
                        if (body + 16 > bytes.size) return null
                        val buffer = ByteBuffer.wrap(bytes, body, 16)
                            .order(ByteOrder.LITTLE_ENDIAN)
                        val audioFormat = buffer.short.toInt()
                        if (audioFormat != 1) return null // PCM lineal
                        channels = buffer.short.toInt()
                        sampleRate = buffer.int
                        buffer.int // byte rate
                        buffer.short // block align
                        bits = buffer.short.toInt()
                    }

                    "data" -> {
                        dataOffset = body
                        dataSize = if (size <= 0 || body + size > bytes.size) {
                            bytes.size - body
                        } else {
                            size
                        }
                    }
                }

                if (dataOffset >= 0 && sampleRate > 0) break
                offset = body + size + (size % 2)
            }

            if (sampleRate <= 0 || channels <= 0 || bits != 16 || dataOffset < 0) {
                return null
            }

            WavFormat(
                sampleRate = sampleRate,
                channels = channels,
                bitsPerSample = bits,
                dataOffset = dataOffset,
                dataSize = dataSize
            )
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo leer el WAV sintetizado", e)
            null
        }
    }

    private fun releasePlayback() {
        try {
            audioTrackThread?.interrupt()
        } catch (_: Throwable) {
        }
        audioTrackThread = null

        try {
            audioTrack?.pause()
            audioTrack?.flush()
        } catch (_: Throwable) {
        }
        try {
            audioTrack?.release()
        } catch (_: Throwable) {
        }
        audioTrack = null

        try {
            mediaPlayer?.stop()
        } catch (_: Throwable) {
        }
        try {
            mediaPlayer?.release()
        } catch (_: Throwable) {
        }
        mediaPlayer = null
    }

    private fun stop() {
        queuedText = null
        queuedResult?.success(false)
        queuedResult = null
        synthesizingIntoCall = false
        pendingIntoCallFile?.delete()
        pendingIntoCallFile = null
        releasePlayback()
        try {
            tts?.stop()
        } catch (_: Throwable) {
        }
        settle(completed = false)
    }

    /** Los callbacks de UtteranceProgressListener no llegan en el hilo principal. */
    private fun settleOnMain(utteranceId: String?, completed: Boolean) {
        mainHandler.post {
            if (utteranceId == null || utteranceId == currentUtteranceId) {
                settle(completed)
            }
        }
    }

    private fun settle(completed: Boolean) {
        val result = pendingResult ?: return
        pendingResult = null
        currentUtteranceId = null
        result.success(completed)
    }

    private fun drainQueue(failure: String) {
        val result = queuedResult
        queuedText = null
        queuedResult = null
        result?.error("tts_unavailable", failure, null)
        pendingResult?.error("tts_unavailable", failure, null)
        pendingResult = null
        currentUtteranceId = null
    }

    fun shutdown() {
        methodChannel.setMethodCallHandler(null)
        mainHandler.removeCallbacksAndMessages(null)
        queuedText = null
        queuedResult?.success(false)
        queuedResult = null
        settle(completed = false)
        synthesizingIntoCall = false
        pendingIntoCallFile?.delete()
        pendingIntoCallFile = null
        releasePlayback()
        isReady = false
        try {
            tts?.stop()
        } catch (_: Throwable) {
        }
        tts?.shutdown()
        tts = null
    }
}
