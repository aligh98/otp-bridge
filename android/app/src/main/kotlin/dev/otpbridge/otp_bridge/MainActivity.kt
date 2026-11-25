package dev.otpbridge.otp_bridge

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "dev.otpbridge/android"
        private const val EVENT_CHANNEL = "dev.otpbridge/android_events"
        private const val REQ_SMS = 4001
        private const val REQ_BT = 4002
    }

    private val bgExecutor = Executors.newSingleThreadExecutor()
    private var pendingSmsResult: MethodChannel.Result? = null
    private var pendingBtResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NativeTransportSender.liveEventSink = { json ->
                        events?.success(json)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    NativeTransportSender.liveEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceStatus" -> {
                        result.success(
                            OemSettingsHelper.deviceInfoMap(
                                context = this,
                                smsGranted = hasSmsPermission(),
                                btGranted = hasBluetoothConnectPermission(),
                            )
                        )
                    }

                    "syncConfig" -> {
                        val desktopJson = call.argument<String>("desktopJson") ?: ""
                        val settings = NativeRuntimeSettings(
                            defaultTransport = call.argument<String>("defaultTransport") ?: "wifiLan",
                            enableWifiLan = call.argument<Boolean>("enableWifiLan") ?: true,
                            enableUsb = call.argument<Boolean>("enableUsb") ?: true,
                            enableBluetooth = call.argument<Boolean>("enableBluetooth") ?: true,
                            autoFallback = call.argument<Boolean>("autoFallback") ?: true,
                            enableSmsCapture = call.argument<Boolean>("enableSmsCapture") ?: true,
                            enableNotificationCapture = call.argument<Boolean>("enableNotificationCapture") ?: true,
                            sendSnippet = call.argument<Boolean>("sendSnippet") ?: false,
                            sensitivity = call.argument<String>("sensitivity") ?: "balanced",
                        )
                        NativePrefsStore.saveConfig(applicationContext, desktopJson, settings)
                        result.success(null)
                    }

                    "getRecentOtps" -> {
                        result.success(NativePrefsStore.getRecentOtps(applicationContext))
                    }

                    "sendTestOtp" -> {
                        val code = call.argument<String>("code") ?: "591028"
                        val sender = call.argument<String>("sender") ?: "OtpBridge Test"
                        bgExecutor.execute {
                            val outcome = NativeTransportSender.sendSync(
                                context = applicationContext,
                                code = code,
                                sender = sender,
                                source = "manualTest",
                            )
                            runOnUiThread {
                                result.success(
                                    mapOf(
                                        "ok" to outcome.ok,
                                        "transport" to (outcome.transport ?: ""),
                                        "error" to (outcome.error ?: ""),
                                    )
                                )
                            }
                        }
                    }

                    "getBondedBluetoothDevices" -> {
                        result.success(listBondedBluetoothDevices())
                    }

                    "openAppInfo" -> {
                        OemSettingsHelper.openAppInfo(this)
                        result.success(null)
                    }

                    "openNotificationListenerSettings" -> {
                        OemSettingsHelper.openNotificationListenerSettings(this)
                        result.success(null)
                    }

                    "openBatteryOptimizationSettings" -> {
                        OemSettingsHelper.openBatteryOptimizationSettings(this)
                        result.success(null)
                    }

                    "openOemAutostartSettings" -> {
                        OemSettingsHelper.openOemAutostartSettings(this)
                        result.success(null)
                    }

                    "requestSmsPermission" -> {
                        if (!BuildConfig.SMS_CAPTURE_ENABLED) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        if (hasSmsPermission()) {
                            result.success(true)
                        } else {
                            pendingSmsResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.RECEIVE_SMS),
                                REQ_SMS,
                            )
                        }
                    }

                    "requestBluetoothPermission" -> {
                        if (hasBluetoothConnectPermission()) {
                            result.success(true)
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            pendingBtResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                                REQ_BT,
                            )
                        } else {
                            result.success(true)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun hasSmsPermission(): Boolean {
        if (!BuildConfig.SMS_CAPTURE_ENABLED) return false
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECEIVE_SMS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }

    @SuppressLint("MissingPermission")
    private fun listBondedBluetoothDevices(): List<Map<String, String>> {
        if (!hasBluetoothConnectPermission()) return emptyList()
        return try {
            val mgr = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = mgr?.adapter ?: return emptyList()
            adapter.bondedDevices.orEmpty().map { d ->
                mapOf(
                    "name" to (d.name ?: "Bluetooth Device"),
                    "address" to (d.address ?: ""),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            REQ_SMS -> {
                pendingSmsResult?.success(granted)
                pendingSmsResult = null
            }
            REQ_BT -> {
                pendingBtResult?.success(granted)
                pendingBtResult = null
            }
        }
    }

    override fun onDestroy() {
        NativeTransportSender.liveEventSink = null
        pendingSmsResult = null
        pendingBtResult = null
        bgExecutor.shutdownNow()
        super.onDestroy()
    }
}
