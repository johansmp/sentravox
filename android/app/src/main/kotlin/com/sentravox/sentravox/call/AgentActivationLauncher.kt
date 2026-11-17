package com.sentravox.sentravox.call

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.sentravox.sentravox.MainActivity
import com.sentravox.sentravox.core.SentraVoxPrefs

/**
 * Lleva una llamada entrante hasta la pantalla del agente.
 *
 * `AgentCallScreeningService` decide, pero no puede abrir UI por sí solo: el
 * `MethodChannel` a Dart solo existe mientras hay una `MainActivity` viva y una
 * llamada entra normalmente con la app en segundo plano o cerrada. Por eso se
 * usan tres vías, de más directa a más tolerante:
 *
 * 1. **Anotar la activación** en [SentraVoxPrefs]. Dart la consume al arrancar
 *    y cada vez que la app vuelve al frente, así que la llamada llega al agente
 *    aunque no hubiera nada vivo en el momento.
 * 2. **`startActivity`**, que funciona cuando la app está en primer plano o el
 *    sistema nos exime del bloqueo de lanzamientos en segundo plano.
 * 3. **Notificación con `fullScreenIntent`** y categoría de llamada: es la vía
 *    admitida para UI de llamada entrante y, si el sistema no la muestra a
 *    pantalla completa, queda como aviso tocable.
 *
 * Ninguna es suficiente por sí sola en todas las versiones de Android; juntas
 * cubren los casos reales.
 */
object AgentActivationLauncher {

    private const val TAG = "SentraVoxActivation"

    private const val CHANNEL_ID = "sentravox_agent_calls"
    const val NOTIFICATION_ID = 4301

    /** Extras informativos: la fuente de verdad es la activación en prefs. */
    const val EXTRA_ACTIVATE_AGENT = "com.sentravox.sentravox.ACTIVATE_AGENT"
    const val EXTRA_NUMBER = "com.sentravox.sentravox.NUMBER"
    const val EXTRA_RISK = "com.sentravox.sentravox.RISK"

    fun launch(context: Context, number: String, risk: Double, timestampMillis: Long) {
        SentraVoxPrefs.setPendingActivation(context, number, risk, timestampMillis)

        val intent = agentIntent(context, number, risk)

        try {
            context.startActivity(intent)
        } catch (e: Throwable) {
            // Android 10+ bloquea los lanzamientos en segundo plano sin
            // exención. No es un error: para eso está la notificación.
            Log.i(TAG, "startActivity no permitido, se usa la notificación", e)
        }

        notifyIncoming(context, number, risk, intent)
    }

    /** Quita el aviso: la pantalla del agente ya está atendiendo la llamada. */
    fun cancelNotification(context: Context) {
        notificationManager(context)?.cancel(NOTIFICATION_ID)
    }

    private fun agentIntent(context: Context, number: String, risk: Double): Intent {
        return Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
            putExtra(EXTRA_ACTIVATE_AGENT, true)
            putExtra(EXTRA_NUMBER, number)
            putExtra(EXTRA_RISK, risk)
        }
    }

    private fun notifyIncoming(
        context: Context,
        number: String,
        risk: Double,
        intent: Intent
    ) {
        if (!canPostNotifications(context)) {
            Log.w(TAG, "Sin permiso de notificaciones: el agente solo se abrirá al volver a la app")
            return
        }

        val manager = notificationManager(context) ?: return
        ensureChannel(manager)

        val pending = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }

        val notification = builder
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setContentTitle("SentraVox está atendiendo una llamada")
            .setContentText("Llamada de $number")
            .setSubText("Riesgo estimado ${(risk * 100).toInt()}%")
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(false)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .setFullScreenIntent(pending, true)
            .build()

        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo publicar el aviso de llamada", e)
        }
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        // IMPORTANCE_HIGH es requisito para que `fullScreenIntent` se respete.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Llamadas atendidas por el agente",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Avisa cuando SentraVox contesta una llamada."
            setShowBadge(false)
        }

        manager.createNotificationChannel(channel)
    }

    private fun canPostNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true

        return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun notificationManager(context: Context): NotificationManager? {
        return context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
    }
}
