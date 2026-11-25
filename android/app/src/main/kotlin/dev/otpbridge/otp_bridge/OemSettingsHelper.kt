package dev.otpbridge.otp_bridge

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/**
 * Helper launching device-aware system settings screens (App Info for Android 13+
 * Restricted Settings, Notification Listener, Battery Optimization, and OEM Autostart).
 */
object OemSettingsHelper {

    fun isNotificationListenerEnabled(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return enabled.contains(context.packageName)
    }

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun openAppInfo(context: Context) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", context.packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun openNotificationListenerSettings(context: Context) {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun openBatteryOptimizationSettings(context: Context) {
        try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (_: Exception) {
            openAppInfo(context)
        }
    }

    fun openOemAutostartSettings(context: Context) {
        val oemIntents = listOf(
            // Xiaomi MIUI / HyperOS
            Intent().setComponent(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            ),
            // Huawei / Honor EMUI / MagicOS
            Intent().setComponent(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                )
            ),
            // Oppo / Realme ColorOS
            Intent().setComponent(
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )
            ),
            // Vivo
            Intent().setComponent(
                ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                )
            ),
        )

        for (intent in oemIntents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (context.packageManager.resolveActivity(intent, 0) != null) {
                    context.startActivity(intent)
                    return
                }
            } catch (_: Exception) {
            }
        }
        // Fallback to standard App Info
        openAppInfo(context)
    }

    fun deviceInfoMap(
        context: Context,
        smsGranted: Boolean,
        btGranted: Boolean,
    ): Map<String, Any> = mapOf(
        "manufacturer" to (Build.MANUFACTURER ?: "Android"),
        "brand" to (Build.BRAND ?: "Android"),
        "model" to (Build.MODEL ?: "Device"),
        "sdkInt" to Build.VERSION.SDK_INT,
        "notificationListenerEnabled" to isNotificationListenerEnabled(context),
        "smsPermissionGranted" to smsGranted,
        "smsFlavorSupported" to BuildConfig.SMS_CAPTURE_ENABLED,
        "batteryOptimizationIgnored" to isIgnoringBatteryOptimizations(context),
        "bluetoothPermissionGranted" to btGranted,
    )
}
