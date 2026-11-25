package dev.otpbridge.otp_bridge

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.io.DataInputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Multi-transport encrypted OTP dispatcher for Android background services.
 *
 * Supports:
 *  - Local Wi-Fi (LAN) [Default] with multi-response UDP LAN IP rediscovery
 *  - USB Cable (`127.0.0.1` via Desktop `adb reverse`)
 *  - Bluetooth Classic RFCOMM SPP (UUID `8a7c4b2e-91f3-4d6a-b5e1-2c8f9a0d3e41`)
 *    with discovery cancellation and hard 4s socket timeout watchdog.
 *
 * All TCP/UDP sockets are strictly guarded by [NativeLocalNetworkGuard].
 */
object NativeTransportSender {
    private val btServiceUuid: UUID =
        UUID.fromString("8a7c4b2e-91f3-4d6a-b5e1-2c8f9a0d3e41")
    private const val DISCOVERY_PORT = 47832
    private const val DISCOVERY_MAGIC = "OTPBRIDGE_DISCOVER_V1"
    private const val DISCOVERY_RESPONSE_MAGIC = "OTPBRIDGE_HERE_V1"

    private val executor = Executors.newFixedThreadPool(3)
    private val watchdog: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    var liveEventSink: ((String) -> Unit)? = null

    data class SendOutcome(
        val ok: Boolean,
        val transport: String? = null,
        val error: String? = null,
    )

    fun dispatchAsync(
        context: Context,
        code: String,
        sender: String,
        source: String,
        packageName: String? = null,
        confidence: Double = 1.0,
        onComplete: (() -> Unit)? = null,
    ) {
        if (NativePrefsStore.isDuplicateCode(code)) {
            onComplete?.invoke()
            return
        }

        val appCtx = context.applicationContext
        executor.execute {
            try {
                sendSync(
                    context = appCtx,
                    code = code,
                    sender = sender,
                    source = source,
                    packageName = packageName,
                    confidence = confidence,
                )
            } finally {
                onComplete?.invoke()
            }
        }
    }

    fun sendSync(
        context: Context,
        code: String,
        sender: String,
        source: String,
        packageName: String? = null,
        confidence: Double = 1.0,
    ): SendOutcome {
        val desktop = NativePrefsStore.loadDesktop(context)
            ?: return SendOutcome(false, error = "No desktop paired")
        val settings = NativePrefsStore.loadSettings(context)

        val order = buildTransportOrder(settings)
        if (order.isEmpty()) {
            return SendOutcome(false, error = "All transports disabled")
        }

        val id = UUID.randomUUID().toString()
        val nowMs = System.currentTimeMillis()
        var lastError = "Desktop unreachable"

        for (mode in order) {
            val otpJson = JSONObject().apply {
                put("id", id)
                put("code", code)
                put("sender", sender)
                put("source", source)
                put("ts", nowMs)
                put("transport", mode)
                put("confidence", confidence)
                if (!packageName.isNullOrBlank()) put("pkg", packageName)
            }

            val encrypted = try {
                NativeE2eeCrypto.encryptEnvelope("otp", otpJson, desktop.sharedKey)
            } catch (e: Exception) {
                return SendOutcome(false, error = "Crypto error: ${e.message}")
            }

            val delivered = when (mode) {
                "usb" -> sendViaTcp("127.0.0.1", desktop.tcpPort, encrypted, desktop.sharedKey, 1200)
                "wifiLan" -> sendViaWifiLan(context, desktop, encrypted)
                "bluetooth" -> sendViaBluetooth(context, desktop, encrypted)
                else -> false
            }

            if (delivered) {
                val serialized = otpJson.toString()
                NativePrefsStore.recordRecentOtp(context, serialized)
                mainHandler.post { liveEventSink?.invoke(serialized) }
                return SendOutcome(true, transport = mode)
            } else {
                lastError = "Failed via $mode"
            }
        }

        return SendOutcome(false, error = lastError)
    }

    private fun buildTransportOrder(s: NativeRuntimeSettings): List<String> {
        val enabled = mutableListOf<String>()
        fun isEnabled(mode: String) = when (mode) {
            "wifiLan" -> s.enableWifiLan
            "usb" -> s.enableUsb
            "bluetooth" -> s.enableBluetooth
            else -> false
        }

        if (isEnabled(s.defaultTransport)) {
            enabled.add(s.defaultTransport)
        }
        if (s.autoFallback) {
            for (m in listOf("usb", "wifiLan", "bluetooth")) {
                if (isEnabled(m) && !enabled.contains(m)) {
                    enabled.add(m)
                }
            }
        }
        return enabled
    }

    private fun sendViaWifiLan(
        context: Context,
        desktop: NativeDesktopConfig,
        encrypted: ByteArray,
    ): Boolean {
        for (ip in desktop.lanIps) {
            if (!NativeLocalNetworkGuard.isAllowedLocalIp(ip)) continue
            if (sendViaTcp(ip, desktop.tcpPort, encrypted, desktop.sharedKey, 2000)) {
                return true
            }
        }
        // DHCP IP may have changed -> try local LAN UDP discovery
        val discoveredIp = discoverDesktopIpOnLan(desktop.deviceId)
        if (discoveredIp != null && NativeLocalNetworkGuard.isAllowedLocalIp(discoveredIp)) {
            if (sendViaTcp(discoveredIp, desktop.tcpPort, encrypted, desktop.sharedKey, 2000)) {
                NativePrefsStore.updateDesktopPrimaryIp(context, discoveredIp)
                return true
            }
        }
        return false
    }

    private fun sendViaTcp(
        host: String,
        port: Int,
        encryptedPayload: ByteArray,
        sharedKey: String,
        timeoutMs: Int,
    ): Boolean {
        val addr = try {
            NativeLocalNetworkGuard.requireAllowedAddress(host)
        } catch (_: SecurityException) {
            return false
        }

        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(addr, port), timeoutMs)
                socket.soTimeout = timeoutMs
                val out = socket.getOutputStream()
                out.write(NativeE2eeCrypto.wrapFrame(encryptedPayload))
                out.flush()

                val input = DataInputStream(socket.getInputStream())
                val replyLen = input.readInt()
                if (replyLen <= 0 || replyLen > 65536) return false
                val replyBytes = ByteArray(replyLen)
                input.readFully(replyBytes)

                val reply = NativeE2eeCrypto.decryptEnvelope(replyBytes, sharedKey)
                reply.optString("t") == "ack" &&
                    reply.optJSONObject("data")?.optBoolean("ok", false) == true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun discoverDesktopIpOnLan(targetDeviceId: String): String? {
        val deadline = System.currentTimeMillis() + 1000L
        return try {
            DatagramSocket().use { socket ->
                socket.broadcast = true
                val probe = "$DISCOVERY_MAGIC:$targetDeviceId".toByteArray(Charsets.UTF_8)
                val packet = DatagramPacket(
                    probe,
                    probe.size,
                    InetAddress.getByName("255.255.255.255"),
                    DISCOVERY_PORT,
                )
                socket.send(packet)

                val buf = ByteArray(1024)
                while (true) {
                    val remaining = (deadline - System.currentTimeMillis()).toInt()
                    if (remaining <= 0) break
                    socket.soTimeout = remaining
                    val resp = DatagramPacket(buf, buf.size)
                    socket.receive(resp)
                    if (!NativeLocalNetworkGuard.isAllowedAddress(resp.address)) continue
                    val text = String(resp.data, 0, resp.length, Charsets.UTF_8)
                    val obj = try {
                        JSONObject(text)
                    } catch (_: Exception) {
                        continue
                    }
                    if (obj.optString("magic") == DISCOVERY_RESPONSE_MAGIC &&
                        obj.optString("id") == targetDeviceId
                    ) {
                        return resp.address.hostAddress
                    }
                }
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    @SuppressLint("MissingPermission")
    private fun sendViaBluetooth(
        context: Context,
        desktop: NativeDesktopConfig,
        encryptedPayload: ByteArray,
    ): Boolean {
        val btAddr = desktop.bluetoothAddress ?: return false
        return try {
            val mgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = mgr?.adapter ?: return false
            if (!adapter.isEnabled) return false

            try {
                if (adapter.isDiscovering) adapter.cancelDiscovery()
            } catch (_: SecurityException) {
            }

            val device = adapter.getRemoteDevice(btAddr)
            val btSocket = device.createRfcommSocketToServiceRecord(btServiceUuid)

            // Guard against blocking indefinitely if the paired PC is out of range
            val killer = watchdog.schedule({
                try {
                    btSocket.close()
                } catch (_: Exception) {
                }
            }, 4, TimeUnit.SECONDS)

            try {
                btSocket.use { sock ->
                    sock.connect()
                    val out = sock.outputStream
                    out.write(NativeE2eeCrypto.wrapFrame(encryptedPayload))
                    out.flush()

                    val input = DataInputStream(sock.inputStream)
                    val replyLen = input.readInt()
                    if (replyLen <= 0 || replyLen > 65536) return false
                    val replyBytes = ByteArray(replyLen)
                    input.readFully(replyBytes)
                    val reply = NativeE2eeCrypto.decryptEnvelope(replyBytes, desktop.sharedKey)
                    reply.optString("t") == "ack" &&
                        reply.optJSONObject("data")?.optBoolean("ok", false) == true
                }
            } finally {
                killer.cancel(false)
            }
        } catch (_: Exception) {
            false
        }
    }
}
