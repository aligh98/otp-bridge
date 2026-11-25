package dev.otpbridge.otp_bridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import java.util.concurrent.atomic.AtomicInteger

/**
 * Optional direct SMS BroadcastReceiver (registered ONLY in the `foss` flavor
 * for GitHub/Bazaar/Myket; omitted from the `play` Google Play flavor).
 *
 * Uses `goAsync()` so Android does not freeze or kill the process before the
 * encrypted OTP finishes transmitting over Wi-Fi / USB / Bluetooth.
 */
class SmsBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val settings = NativePrefsStore.loadSettings(context)
        if (!settings.enableSmsCapture) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        // Group multipart SMS segments by sender address
        val bySender = LinkedHashMap<String, StringBuilder>()
        for (msg in messages) {
            val addr = msg.displayOriginatingAddress ?: msg.originatingAddress ?: ""
            val body = msg.displayMessageBody ?: msg.messageBody ?: ""
            bySender.getOrPut(addr) { StringBuilder() }.append(body)
        }

        val matches = mutableListOf<Triple<String, String, Double>>()
        for ((senderAddr, bodyBuilder) in bySender) {
            val fullBody = bodyBuilder.toString().trim()
            if (fullBody.isEmpty()) continue

            val parsed = NativeOtpEngine.parse(
                title = null,
                body = fullBody,
                senderHint = senderAddr,
                sensitivity = settings.sensitivity,
            )
            if (parsed.isOtp && !parsed.code.isNullOrBlank()) {
                matches.add(
                    Triple(
                        parsed.code,
                        parsed.sender ?: senderAddr.ifBlank { "SMS" },
                        parsed.confidence,
                    )
                )
            }
        }

        if (matches.isEmpty()) return

        val pendingResult = goAsync()
        val remaining = AtomicInteger(matches.size)
        val appCtx = context.applicationContext

        for ((code, sender, confidence) in matches) {
            NativeTransportSender.dispatchAsync(
                context = appCtx,
                code = code,
                sender = sender,
                source = "sms",
                confidence = confidence,
                onComplete = {
                    if (remaining.decrementAndGet() == 0) {
                        try {
                            pendingResult.finish()
                        } catch (_: Throwable) {
                        }
                    }
                },
            )
        }
    }
}
