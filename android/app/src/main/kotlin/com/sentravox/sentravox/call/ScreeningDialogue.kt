package com.sentravox.sentravox.call

object ScreeningDialogue {

    fun generate(risk: Double, number: String): String {
        return when {
            risk >= 0.85 ->
                "Esta llamada presenta un riesgo extremadamente alto y será bloqueada por seguridad."

            risk >= 0.60 ->
                "La llamada desde el número $number parece sospechosa. Se recomienda precaución."

            else ->
                "Llamada desde $number. Activando agente SentraVox."
        }
    }
}
