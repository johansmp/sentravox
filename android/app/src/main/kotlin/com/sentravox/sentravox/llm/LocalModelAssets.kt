package com.sentravox.sentravox.llm

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Copia el modelo LLM empaquetado en los assets del APK al almacenamiento
 * interno de la app.
 *
 * `llamadart` (llama.cpp) necesita una ruta de archivo real, no una clave de
 * asset. El modelo pesa cientos de MB, así que se copia en streaming en un hilo
 * de trabajo: cargarlo entero en memoria con `rootBundle` podría tumbar la app.
 */
class LocalModelAssets(
    private val activity: Activity,
    messenger: BinaryMessenger
) {

    private companion object {
        const val TAG = "SentraVoxLocalLlm"
        const val CHANNEL = "sentravox/local_llm"
        const val DEFAULT_ASSET = "assets/models/Qwen3.5-0.8B-Q4_K_M.gguf"
        const val DEFAULT_NAME = "Qwen3.5-0.8B-Q4_K_M.gguf"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareModel" -> {
                    val asset = call.argument<String>("asset") ?: DEFAULT_ASSET
                    val name = call.argument<String>("name") ?: DEFAULT_NAME
                    prepare(asset, name, result)
                }
                "modelStatus" -> {
                    val name = call.argument<String>("name") ?: DEFAULT_NAME
                    result.success(status(name))
                }
                "deleteModel" -> {
                    val name = call.argument<String>("name") ?: DEFAULT_NAME
                    val file = modelFile(name)
                    val deleted = !file.exists() || file.delete()
                    result.success(deleted)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun modelFile(name: String): File {
        val dir = File(activity.filesDir, "local_llm")
        if (!dir.exists()) dir.mkdirs()
        return File(dir, name)
    }

    private fun prepare(asset: String, name: String, result: MethodChannel.Result) {
        executor.execute {
            try {
                val output = modelFile(name)
                if (output.exists() && output.length() > 0L) {
                    mainHandler.post { result.success(status(name)) }
                    return@execute
                }

                val candidates = listOf(
                    "flutter_assets/$asset",
                    asset,
                    "assets/$asset"
                )

                val opened = candidates.firstNotNullOfOrNull { path ->
                    try {
                        activity.assets.open(path).use { input ->
                            output.parentFile?.mkdirs()
                            val temp = File(output.parentFile, "${output.name}.tmp")
                            FileOutputStream(temp).use { out ->
                                input.copyTo(out, 1 shl 20)
                            }
                            if (output.exists()) output.delete()
                            if (!temp.renameTo(output)) {
                                temp.delete()
                                throw IllegalStateException("No se pudo mover el modelo temporal")
                            }
                            path
                        }
                    } catch (e: Throwable) {
                        Log.w(TAG, "Asset no encontrado en $path", e)
                        null
                    }
                }

                if (opened == null) {
                    mainHandler.post {
                        result.error(
                            "model_asset_missing",
                            "No se encontró el modelo en assets. Rutas probadas: $candidates",
                            null
                        )
                    }
                    return@execute
                }

                Log.i(TAG, "Modelo copiado desde $opened a ${output.absolutePath} (${output.length()} bytes)")
                mainHandler.post { result.success(status(name)) }
            } catch (e: Throwable) {
                Log.e(TAG, "No se pudo preparar el modelo local", e)
                mainHandler.post {
                    result.error("model_copy_failed", e.message ?: "Error copiando el modelo", null)
                }
            }
        }
    }

    private fun status(name: String): Map<String, Any?> {
        val file = modelFile(name)
        return mapOf(
            "name" to name,
            "path" to file.absolutePath,
            "exists" to file.exists(),
            "size" to if (file.exists()) file.length() else 0L
        )
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }
}
