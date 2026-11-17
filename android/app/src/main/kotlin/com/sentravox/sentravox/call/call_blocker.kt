package com.sentravox.sentravox.call

import android.telecom.CallScreeningService
import android.telecom.Call

object CallBlocker {

    fun allow(): CallScreeningService.CallResponse {
        return CallScreeningService.CallResponse.Builder()
            .setDisallowCall(false)
            .setSilenceCall(false)
            .setSkipCallLog(false)
            .setSkipNotification(false)
            .build()
    }

    fun blockSilently(): CallScreeningService.CallResponse {
        return CallScreeningService.CallResponse.Builder()
            .setDisallowCall(true)
            .setSilenceCall(true)
            .setSkipCallLog(true)
            .setSkipNotification(true)
            .build()
    }

    fun blockAndNotify(): CallScreeningService.CallResponse {
        return CallScreeningService.CallResponse.Builder()
            .setDisallowCall(true)
            .setSilenceCall(false)
            .setSkipCallLog(false)
            .setSkipNotification(false)
            .build()
    }
}
