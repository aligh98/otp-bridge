package dev.otpbridge.otp_bridge

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class NativeDesktopConfig(
    val deviceId: String,
    val deviceName: String,
    val sharedKey: String,
    val lanIps: List<String>,
    val tcpPort: Int,
    val bluetoothAddress: String?,
)

data class NativeRuntimeSettings(
    val defaultTransport: String = "wifiLan",
    val enableWifiLan: Boolean = true,
    val enableUsb: Boolean = true,
    val enableBluetooth: Boolean = true,
    val autoFallback: Boolean = true,
    val enableSmsCapture: Boolean = true,
    val enableNotificationCapture: Boolean = true,
    val sendSnippet: Boolean = false,
    val sensitivity: String = "balanced",
)

/**
 * Local SharedPreferences store accessible directly from Android background
 * services (NotificationListenerService & SmsBroadcastReceiver) even when the
 * Flutter UI process is closed.
 */
object NativePrefsStore {
    private const val PREFS = "otpbridge_native_state"
    private const val KEY_DESKTOP = "desktop_json"
    private const val KEY_SETTINGS = "settings_json"
    private const val KEY_RECENT_OTPS = "recent_otps_json"

    // In-memory 15-second dedup map (code -> timestampMs)
    private val recentDedup = HashMap<String, Long>()

    @Synchronized
    fun isDuplicateCode(code: String, windowMs: Long = 15_000L): Boolean {
        val now = System.currentTimeMillis()
        val it = recentDedup.entries.iterator()
        while (it.hasNext()) {
            if (now - it.next().value > windowMs) it.remove()
        }
        val key = code.trim().uppercase()
        val prev = recentDedup[key]
        if (prev != null && (now - prev) <= windowMs) {
            return true
        }
        recentDedup[key] = now
        return false
    }

    fun saveConfig(
        context: Context,
        desktopJson: String,
        settings: NativeRuntimeSettings,
    ) {
        val sObj = JSONObject().apply {
            put("defaultTransport", settings.defaultTransport)
            put("enableWifiLan", settings.enableWifiLan)
            put("enableUsb", settings.enableUsb)
            put("enableBluetooth", settings.enableBluetooth)
            put("autoFallback", settings.autoFallback)
            put("enableSmsCapture", settings.enableSmsCapture)
            put("enableNotificationCapture", settings.enableNotificationCapture)
            put("sendSnippet", settings.sendSnippet)
            put("sensitivity", settings.sensitivity)
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DESKTOP, desktopJson)
            .putString(KEY_SETTINGS, sObj.toString())
            .apply()
    }

    fun loadDesktop(context: Context): NativeDesktopConfig? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_DESKTOP, "") ?: ""
        if (raw.isBlank()) return null
        return try {
            val obj = JSONObject(raw)
            val key = obj.optString("key", "")
            val id = obj.optString("id", "")
            if (key.isBlank() || id.isBlank()) return null
            val ipsArr = obj.optJSONArray("ips") ?: JSONArray()
            val ips = mutableListOf<String>()
            for (i in 0 until ipsArr.length()) {
                val ip = ipsArr.optString(i, "")
                if (ip.isNotBlank()) ips.add(ip)
            }
            NativeDesktopConfig(
                deviceId = id,
                deviceName = obj.optString("name", "Desktop"),
                sharedKey = key,
                lanIps = ips,
                tcpPort = obj.optInt("port", 47831),
                bluetoothAddress = obj.optString("btAddr", "").ifBlank { null },
            )
        } catch (_: Exception) {
            null
        }
    }

    fun updateDesktopPrimaryIp(context: Context, newIp: String) {
        if (!NativeLocalNetworkGuard.isAllowedLocalIp(newIp)) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_DESKTOP, "") ?: ""
        if (raw.isBlank()) return
        try {
            val obj = JSONObject(raw)
            val oldIps = obj.optJSONArray("ips") ?: JSONArray()
            val merged = JSONArray().apply { put(newIp) }
            for (i in 0 until oldIps.length()) {
                val ip = oldIps.optString(i, "")
                if (ip.isNotBlank() && ip != newIp) merged.put(ip)
            }
            obj.put("ips", merged)
            prefs.edit().putString(KEY_DESKTOP, obj.toString()).apply()
        } catch (_: Exception) {
        }
    }

    fun loadSettings(context: Context): NativeRuntimeSettings {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SETTINGS, "") ?: ""
        if (raw.isBlank()) return NativeRuntimeSettings()
        return try {
            val obj = JSONObject(raw)
            NativeRuntimeSettings(
                defaultTransport = obj.optString("defaultTransport", "wifiLan"),
                enableWifiLan = obj.optBoolean("enableWifiLan", true),
                enableUsb = obj.optBoolean("enableUsb", true),
                enableBluetooth = obj.optBoolean("enableBluetooth", true),
                autoFallback = obj.optBoolean("autoFallback", true),
                enableSmsCapture = obj.optBoolean("enableSmsCapture", true),
                enableNotificationCapture = obj.optBoolean("enableNotificationCapture", true),
                sendSnippet = obj.optBoolean("sendSnippet", false),
                sensitivity = obj.optString("sensitivity", "balanced"),
            )
        } catch (_: Exception) {
            NativeRuntimeSettings()
        }
    }

    @Synchronized
    fun recordRecentOtp(context: Context, otpJson: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = try {
            JSONArray(prefs.getString(KEY_RECENT_OTPS, "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        val next = JSONArray()
        next.put(otpJson)
        val limit = minOf(arr.length(), 24)
        for (i in 0 until limit) {
            next.put(arr.getString(i))
        }
        prefs.edit().putString(KEY_RECENT_OTPS, next.toString()).apply()
    }

    @Synchronized
    fun getRecentOtps(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_RECENT_OTPS, "[]") ?: "[]"
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
