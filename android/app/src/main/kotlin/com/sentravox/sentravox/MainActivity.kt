package com.sentravox.sentravox

import android.Manifest
import android.app.NotificationManager
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.telecom.TelecomManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.sentravox.sentravox.call.AgentActivationLauncher
import com.sentravox.sentravox.call.AgentCallScreeningService
import com.sentravox.sentravox.call.CallAudioController
import com.sentravox.sentravox.core.SentraVoxPrefs
import com.sentravox.sentravox.llm.LocalModelAssets
import com.sentravox.sentravox.stt.OfflineSttService
import com.sentravox.sentravox.tts.OfflineTtsService

class MainActivity : FlutterActivity() {

    private companion object {
        const val TAG = "SentraVoxMain"

        const val STT_METHOD_CHANNEL = "sentravox/stt"
        const val STT_EVENT_CHANNEL = "sentravox/stt_stream"
        const val TTS_METHOD_CHANNEL = "sentravox/tts"
        const val DIALER_METHOD_CHANNEL = "sentravox/dialer"
        const val SETTINGS_METHOD_CHANNEL = "sentravox/settings"
        const val SCREENING_METHOD_CHANNEL = "sentravox/call_screening"

        const val REQUEST_PERMISSIONS = 4201
        const val REQUEST_SCREENING_ROLE = 4202
    }

    // Se conservan las referencias: si se dejan como temporales el GC puede
    // recolectar los handlers y los canales dejan de responder.
    private var sttService: OfflineSttService? = null
    private var ttsService: OfflineTtsService? = null
    private var localModelAssets: LocalModelAssets? = null
    private var screeningChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestRequiredPermissions()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // STT: MethodChannel para start/stop + EventChannel para transcripciones
        sttService = OfflineSttService(
            this,
            MethodChannel(messenger, STT_METHOD_CHANNEL),
            EventChannel(messenger, STT_EVENT_CHANNEL)
        )

        // TTS
        ttsService = OfflineTtsService(
            this,
            MethodChannel(messenger, TTS_METHOD_CHANNEL)
        )

        // NLP (ONNX) se retiró; el clasificador vive en Dart.
        configureDialerChannel(messenger)
        configureSettingsChannel(messenger)
        configureScreeningChannel(messenger)

        // Copia del modelo LLM empaquetado al almacenamiento interno.
        localModelAssets = LocalModelAssets(this, messenger)
    }

    // -------------------------------------------------------------------------
    // Canales
    // -------------------------------------------------------------------------

    private fun configureDialerChannel(
        messenger: io.flutter.plugin.common.BinaryMessenger
    ) {
        MethodChannel(messenger, DIALER_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "request_default_dialer" -> {
                    requestDefaultDialer()
                    result.success(true)
                }
                "is_default_dialer" -> result.success(isDefaultDialer())
                "end_call" -> result.success(endCurrentCall())

                // Contestar de verdad la llamada: el servicio de screening solo
                // la deja pasar, no descuelga.
                "answer_call" -> result.success(CallAudioController.answerRingingCall(this))
                "can_answer_calls" -> result.success(CallAudioController.canAnswerCalls(this))
                "call_state" -> result.success(CallAudioController.callState(this).name)

                // Altavoz + voz del agente por la ruta de la llamada.
                "set_in_call_audio" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    ttsService?.setInCallAudio(enabled)
                    result.success(CallAudioController.setInCallAudio(this, enabled))
                }
                "audio_diagnostics" ->
                    result.success(CallAudioController.audioDiagnostics(this))

                // Sin el rol de filtrado Android nunca invoca
                // AgentCallScreeningService: ninguna llamada llega al agente.
                "is_screening_role_held" -> result.success(isScreeningRoleHeld())
                "diagnostics" -> result.success(diagnostics())
                // Devuelve un estado, no un booleano: si el rol no está
                // disponible hay que poder decírselo al usuario en vez de que
                // el botón no haga nada.
                "request_screening_role" -> result.success(requestScreeningRole())
                "request_permissions" -> {
                    requestRequiredPermissions()
                    result.success(true)
                }
                "open_app_settings" -> {
                    openAppSettings()
                    result.success(true)
                }
                "open_voice_input_settings" -> {
                    openVoiceInputSettings()
                    result.success(true)
                }
                "request_full_screen_intent" -> {
                    requestFullScreenIntentAccess()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun configureSettingsChannel(
        messenger: io.flutter.plugin.common.BinaryMessenger
    ) {
        MethodChannel(messenger, SETTINGS_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAll" -> result.success(SentraVoxPrefs.snapshot(this))

                "setBoolean" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<Boolean>("value")
                    if (key == null || value == null) {
                        result.error("bad_args", "Se requieren 'key' y 'value'.", null)
                    } else {
                        SentraVoxPrefs.setBoolean(this, key, value)
                        result.success(null)
                    }
                }

                "setDouble" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<Double>("value")
                    if (key == null || value == null) {
                        result.error("bad_args", "Se requieren 'key' y 'value'.", null)
                    } else {
                        SentraVoxPrefs.setDouble(this, key, value)
                        result.success(null)
                    }
                }

                "setString" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<String>("value")
                    if (key == null || value == null) {
                        result.error("bad_args", "Se requieren 'key' y 'value'.", null)
                    } else {
                        SentraVoxPrefs.setString(this, key, value)
                        result.success(null)
                    }
                }

                "getBlocklist" -> result.success(SentraVoxPrefs.blocklist(this).toList())

                "setBlocklist" -> {
                    val numbers = call.argument<List<String>>("numbers") ?: emptyList()
                    SentraVoxPrefs.setBlocklist(this, numbers)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun configureScreeningChannel(
        messenger: io.flutter.plugin.common.BinaryMessenger
    ) {
        val channel = MethodChannel(messenger, SCREENING_METHOD_CHANNEL)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "drainEvents" -> result.success(SentraVoxPrefs.drainEvents(this))

                // Activación anotada por el servicio de screening cuando no
                // había UI viva para recibir `activate_agent`. Dart la pide al
                // arrancar y cada vez que vuelve al primer plano.
                "consumePendingActivation" -> {
                    val pending = SentraVoxPrefs.consumePendingActivation(this)
                    if (pending != null) AgentActivationLauncher.cancelNotification(this)
                    result.success(pending)
                }

                else -> result.notImplemented()
            }
        }

        // Habilita el sentido nativo → Dart (activate_agent / screening_message).
        screeningChannel = channel
        AgentCallScreeningService.flutterChannel = channel
    }

    override fun onDestroy() {
        // Sin esto el servicio de screening retendría un canal de un engine
        // muerto y las invocaciones se perderían en silencio.
        if (AgentCallScreeningService.flutterChannel === screeningChannel) {
            AgentCallScreeningService.flutterChannel = null
        }
        screeningChannel = null

        sttService?.dispose()
        ttsService?.shutdown()
        localModelAssets?.dispose()
        sttService = null
        ttsService = null
        localModelAssets = null
        super.onDestroy()
    }

    // -------------------------------------------------------------------------
    // Permisos y telefonía
    // -------------------------------------------------------------------------

    private fun requestRequiredPermissions() {
        val wanted = mutableListOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.ANSWER_PHONE_CALLS,
            // Para distinguir un desconocido de un contacto guardado.
            Manifest.permission.READ_CONTACTS
        )

        // Sin este permiso el aviso a pantalla completa no se publica y, con la
        // app en segundo plano, la llamada no llega a abrir el agente.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            wanted.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        val needed = wanted.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }

        if (needed.isNotEmpty()) {
            requestPermissions(needed.toTypedArray(), REQUEST_PERMISSIONS)
        }
    }

    /**
     * ¿Tenemos permiso del sistema para filtrar llamadas?
     *
     * En API 29+ es el rol `ROLE_CALL_SCREENING`, que se puede pedir sin
     * convertirse en marcador. Antes de API 29 no existe ese rol: el sistema
     * solo enlaza el `CallScreeningService` de la app de teléfono
     * predeterminada.
     */
    private fun isScreeningRoleHeld(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return isDefaultDialer()

        val roleManager = getSystemService(RoleManager::class.java) ?: return false

        return roleManager.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) &&
            roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
    }

    /**
     * Todas las puertas que tiene que atravesar una llamada, en un solo mapa.
     *
     * Cuando «no contesta» hay media docena de motivos posibles y desde la app
     * no se distinguen; esto los separa para no diagnosticar a ciegas.
     */
    private fun diagnostics(): Map<String, Any?> {
        val notificationManager =
            getSystemService(NotificationManager::class.java)

        return mapOf(
            "screening_role" to isScreeningRoleHeld(),
            "role_available" to isScreeningRoleAvailable(),
            "default_dialer" to isDefaultDialer(),
            "answer_calls" to granted(Manifest.permission.ANSWER_PHONE_CALLS),
            "record_audio" to granted(Manifest.permission.RECORD_AUDIO),
            "read_phone_state" to granted(Manifest.permission.READ_PHONE_STATE),
            "read_contacts" to granted(Manifest.permission.READ_CONTACTS),
            "notifications" to
                (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                    granted(Manifest.permission.POST_NOTIFICATIONS)),
            // Android 14+ solo lo concede de oficio a apps de llamadas.
            "full_screen_intent" to
                (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
                    notificationManager?.canUseFullScreenIntent() == true),
            "sdk_int" to Build.VERSION.SDK_INT,
            "last_screening" to SentraVoxPrefs.lastScreening(this)
        )
    }

    /** Para permisos que el usuario ya denegó: el diálogo no vuelve a salir. */
    private fun openAppSettings() {
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                }
            )
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo abrir los ajustes de la app", e)
        }
    }

    /** Android 14+: el aviso a pantalla completa se concede a mano. */
    private fun requestFullScreenIntentAccess() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            openAppSettings()
            return
        }

        try {
            startActivity(
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                    data = Uri.fromParts("package", packageName, null)
                }
            )
        } catch (e: Throwable) {
            openAppSettings()
        }
    }

    /**
     * Ajustes de entrada de voz del sistema: ahí se descarga el paquete de
     * español para que el reconocimiento funcione sin conexión.
     */
    private fun openVoiceInputSettings() {
        try {
            startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo abrir los ajustes de entrada de voz", e)
            openAppSettings()
        }
    }

    private fun granted(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun isScreeningRoleAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false

        val roleManager = getSystemService(RoleManager::class.java) ?: return false
        return roleManager.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING)
    }

    /**
     * Pide el rol de filtrado. Devuelve qué ocurrió, porque «no pasó nada» es
     * un resultado posible y el usuario tiene derecho a saber por qué.
     */
    private fun requestScreeningRole(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Antes de API 29 no hay rol: el sistema solo enlaza el servicio de
            // filtrado de la app de teléfono predeterminada.
            requestDefaultDialer()
            return "legacy_dialer_requested"
        }

        val roleManager = getSystemService(RoleManager::class.java)
            ?: return "no_role_manager"

        if (!roleManager.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING)) {
            Log.w(TAG, "El dispositivo no ofrece el rol de filtrado de llamadas")
            return "role_unavailable"
        }
        if (roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) {
            return "already_held"
        }

        return try {
            startActivityForResult(
                roleManager.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING),
                REQUEST_SCREENING_ROLE
            )
            "requested"
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo abrir el diálogo del rol de filtrado", e)
            "request_failed"
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_SCREENING_ROLE) {
            Log.i(
                TAG,
                "Rol de filtrado: ${if (resultCode == RESULT_OK) "concedido" else "rechazado"}"
            )
        }
    }

    private fun isDefaultDialer(): Boolean {
        val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
        return telecomManager.defaultDialerPackage == applicationContext.packageName
    }

    private fun requestDefaultDialer() {
        if (isDefaultDialer()) return

        val intent = Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER)
        intent.putExtra(
            TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME,
            applicationContext.packageName
        )
        startActivity(intent)
    }

    /**
     * Corta la llamada en curso. Requiere API 28+ y el permiso
     * ANSWER_PHONE_CALLS; en la práctica el sistema solo lo concede a la app
     * marcador predeterminada. Devuelve false si no se pudo.
     */
    private fun endCurrentCall(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false

        if (checkSelfPermission(Manifest.permission.ANSWER_PHONE_CALLS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
        return try {
            @Suppress("DEPRECATION")
            telecomManager.endCall()
        } catch (e: SecurityException) {
            Log.w(TAG, "endCall() denegado", e)
            false
        }
    }
}
