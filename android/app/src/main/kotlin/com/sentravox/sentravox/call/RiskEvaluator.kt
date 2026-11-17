package com.sentravox.sentravox.call

import com.sentravox.sentravox.core.SentraVoxPrefs

/**
 * Riesgo previo a contestar. Solo dispone del número: la transcripción todavía
 * no existe, así que esto es un filtro grueso. El análisis fino lo hace el
 * agente durante la llamada.
 *
 * Las reglas están pensadas para Colombia (el locale de la app es `es-CO`):
 * los móviles son 3XX y los fijos, desde la renumeración de 2022, empiezan por
 * 60X. La versión anterior puntuaba `60…` con 0.7 y bloqueaba, por encima del
 * umbral por defecto, **cualquier fijo colombiano marcado en formato local**.
 *
 * TODO: sigue siendo heurística; la señal real debería venir de reputación del
 * número y del historial de llamadas.
 */
object RiskEvaluator {

    const val RISK_BLOCKLISTED = 1.0
    const val RISK_HIDDEN = 0.75
    const val RISK_PREMIUM_LINE = 0.8
    const val RISK_SHORT_CODE = 0.6
    const val RISK_TOLL_FREE = 0.45
    const val RISK_UNKNOWN_CALLER = 0.45
    const val RISK_BASELINE = 0.1

    /**
     * A partir de aquí un desconocido ya no se deriva al agente: se bloquea.
     * Por debajo, el agente contesta aunque el umbral del usuario sea más bajo
     * —de lo contrario «activar el agente con los desconocidos» y el umbral se
     * anularían mutuamente y la llamada nunca llegaría al agente.
     */
    const val RISK_AGENT_CEILING = 0.7

    /** Indicativo de país de Colombia. */
    private const val COUNTRY_CODE = "57"

    fun evaluate(
        number: String,
        blocklist: Set<String> = emptySet(),
        isUnknownCaller: Boolean = false
    ): Double {
        val digits = SentraVoxPrefs.normalizeNumber(number)

        if (digits.isNotEmpty() && isBlocklisted(digits, blocklist)) {
            return RISK_BLOCKLISTED
        }

        // Número oculto o no entregado por la red.
        if (digits.isEmpty()) return RISK_HIDDEN

        val local = toLocalNumber(digits)

        val prefixRisk = when {
            // Tarificación especial (líneas 019xx): coste para quien contesta.
            local.startsWith("019") -> RISK_PREMIUM_LINE

            // Líneas gratuitas 01800: casi siempre call center comercial.
            local.startsWith("01800") -> RISK_TOLL_FREE

            // Números demasiado cortos para ser un teléfono: robocall o
            // remitente enmascarado.
            local.length < 7 -> RISK_SHORT_CODE

            else -> RISK_BASELINE
        }

        // Un desconocido sube el suelo, pero no manda por encima de una señal
        // de prefijo más fuerte.
        return if (isUnknownCaller) maxOf(prefixRisk, RISK_UNKNOWN_CALLER) else prefixRisk
    }

    fun intentFor(risk: Double): String = when {
        risk >= 0.85 -> "spam"
        risk >= 0.6 -> "sospechoso"
        else -> "desconocido"
    }

    /**
     * Compara sin que el formato decida: la lista de bloqueo guarda lo que
     * escribió el usuario (normalmente 10 dígitos) y la red entrega E.164
     * (`+57…`). Coincide si uno es sufijo del otro, con al menos 7 dígitos en
     * común para no emparejar por casualidad.
     */
    private fun isBlocklisted(digits: String, blocklist: Set<String>): Boolean {
        if (blocklist.contains(digits)) return true

        return blocklist.any { entry ->
            if (entry.length < 7 || digits.length < 7) {
                entry == digits
            } else {
                digits.endsWith(entry) || entry.endsWith(digits)
            }
        }
    }

    /** Quita el indicativo internacional para poder mirar el prefijo local. */
    private fun toLocalNumber(digits: String): String {
        var local = digits.removePrefix("00")

        if (local.startsWith(COUNTRY_CODE) && local.length > 10) {
            local = local.removePrefix(COUNTRY_CODE)
        }

        return local
    }
}
