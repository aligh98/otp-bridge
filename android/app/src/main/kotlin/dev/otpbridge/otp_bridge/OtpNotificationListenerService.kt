package dev.otpbridge.otp_bridge

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Always-on Android NotificationListenerService.
 *
 * Captures OTP codes locally from Email apps (Gmail, Outlook, Yahoo, Thunderbird,
 * K-9, Samsung Email, ProtonMail, Spark), SMS/RCS apps, and messengers without
 * ever requiring email account login or cloud access.
 */
class OtpNotificationListenerService : NotificationListenerService() {

    companion object {
        private val emailPackages = setOf(
            "com.google.android.gm",
            "com.microsoft.office.outlook",
            "com.yahoo.mobile.client.android.mail",
            "com.samsung.android.email.provider",
            "com.fsck.k9",
            "net.thunderbird.android",
            "ch.protonmail.android",
            "com.readdle.spark",
            "me.bluemail.mail",
            "ru.yandex.mail",
        )

        private val smsPackages = setOf(
            "com.google.android.apps.messaging",
            "com.samsung.android.messaging",
            "com.android.mms",
            "com.miui.mms",
            "com.oneplus.mms",
            "com.sonyericsson.conversations",
            "org.thoughtcrime.securesms",
            "com.simplemobiletools.smsmessenger",
            "org.fossify.messages",
        )

        private val messengerPackages = setOf(
            "org.telegram.messenger",
            "org.telegram.messenger.web",
            "com.whatsapp",
            "com.whatsapp.w4b",
            "ir.nasim",       // Bale
            "ir.eitaa.messenger",
            "app.rbmain.a",   // Rubika
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        // Ignore our own notifications, ongoing system alerts, and group summary rollups
        if (pkg == applicationContext.packageName) return
        if (sbn.isOngoing) return
        val notif = sbn.notification ?: return
        if ((notif.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return

        val settings = NativePrefsStore.loadSettings(applicationContext)
        if (!settings.enableNotificationCapture) return

        val extras = notif.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim()
        val textLines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.joinToString("\n") { it.toString() }

        val body = listOfNotNull(bigText, textLines, text, subText)
            .filter { it.isNotBlank() }
            .distinct()
            .joinToString("\n")

        if (body.isBlank() && title.isBlank()) return

        val parsed = NativeOtpEngine.parse(
            title = title,
            body = body,
            senderHint = title,
            sensitivity = settings.sensitivity,
        )
        if (!parsed.isOtp || parsed.code.isNullOrBlank()) return

        val source = when {
            pkg in emailPackages -> "email"
            pkg in smsPackages -> "sms"
            pkg in messengerPackages -> "messenger"
            else -> "notification"
        }

        NativeTransportSender.dispatchAsync(
            context = applicationContext,
            code = parsed.code,
            sender = parsed.sender ?: title.ifBlank { "OTP" },
            source = source,
            packageName = pkg,
            confidence = parsed.confidence,
        )
    }
}
