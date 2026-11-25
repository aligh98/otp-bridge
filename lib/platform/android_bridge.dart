import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../core/models/app_settings.dart';
import '../core/models/otp_message.dart';
import '../core/models/paired_device.dart';

class AndroidDeviceStatus {
  const AndroidDeviceStatus({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.sdkInt,
    required this.notificationListenerEnabled,
    required this.smsPermissionGranted,
    required this.smsFlavorSupported,
    required this.batteryOptimizationIgnored,
    required this.bluetoothPermissionGranted,
  });

  final String manufacturer;
  final String brand;
  final String model;
  final int sdkInt;
  final bool notificationListenerEnabled;
  final bool smsPermissionGranted;
  final bool smsFlavorSupported;
  final bool batteryOptimizationIgnored;
  final bool bluetoothPermissionGranted;

  factory AndroidDeviceStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const AndroidDeviceStatus(
        manufacturer: 'Android',
        brand: 'Android',
        model: 'Device',
        sdkInt: 34,
        notificationListenerEnabled: false,
        smsPermissionGranted: false,
        smsFlavorSupported: true,
        batteryOptimizationIgnored: false,
        bluetoothPermissionGranted: false,
      );
    }
    return AndroidDeviceStatus(
      manufacturer: (map['manufacturer'] as String?) ?? 'Android',
      brand: (map['brand'] as String?) ?? 'Android',
      model: (map['model'] as String?) ?? 'Device',
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 34,
      notificationListenerEnabled:
          (map['notificationListenerEnabled'] as bool?) ?? false,
      smsPermissionGranted: (map['smsPermissionGranted'] as bool?) ?? false,
      smsFlavorSupported: (map['smsFlavorSupported'] as bool?) ?? true,
      batteryOptimizationIgnored:
          (map['batteryOptimizationIgnored'] as bool?) ?? false,
      bluetoothPermissionGranted:
          (map['bluetoothPermissionGranted'] as bool?) ?? false,
    );
  }
}

class BondedBluetoothDevice {
  const BondedBluetoothDevice({required this.name, required this.address});
  final String name;
  final String address;
}

/// Bridge between Flutter UI and Android native Kotlin background OTP services.
///
/// Syncs paired desktop credentials & settings into native Android SharedPreferences
/// so `OtpNotificationListenerService` and `SmsBroadcastReceiver` keep detecting
/// and forwarding OTPs with AES-256-GCM even when the Flutter UI is closed.
class AndroidNativeBridge {
  AndroidNativeBridge._();

  static const MethodChannel _method =
      MethodChannel(AppConstants.androidMethodChannel);
  static const EventChannel _events =
      EventChannel(AppConstants.androidEventChannel);

  static Stream<OtpMessage>? _otpStream;

  static Stream<OtpMessage> get liveOtpStream {
    if (!Platform.isAndroid) return const Stream.empty();
    _otpStream ??= _events.receiveBroadcastStream().map((raw) {
      if (raw is String) {
        return OtpMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
      if (raw is Map) {
        return OtpMessage.fromJson(Map<String, dynamic>.from(raw));
      }
      throw const FormatException('Unexpected event payload');
    });
    return _otpStream!;
  }

  static Future<AndroidDeviceStatus> getDeviceStatus() async {
    if (!Platform.isAndroid) return AndroidDeviceStatus.fromMap(null);
    try {
      final map = await _method.invokeMapMethod<String, dynamic>('getDeviceStatus');
      return AndroidDeviceStatus.fromMap(map);
    } catch (_) {
      return AndroidDeviceStatus.fromMap(null);
    }
  }

  /// Syncs paired desktop and settings into native Kotlin background storage.
  static Future<void> syncNativeConfig({
    required PairedDevice? desktop,
    required AppSettings settings,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _method.invokeMethod<void>('syncConfig', {
        'desktopJson': desktop?.toJsonString() ?? '',
        'defaultTransport': settings.defaultTransport.wireValue,
        'enableWifiLan': settings.enableWifiLan,
        'enableUsb': settings.enableUsb,
        'enableBluetooth': settings.enableBluetooth,
        'autoFallback': settings.autoFallbackTransports,
        'enableSmsCapture': settings.enableSmsCapture,
        'enableNotificationCapture': settings.enableNotificationCapture,
        'sendSnippet': settings.sendSnippet,
        'sensitivity': settings.sensitivity.name,
      });
    } catch (_) {}
  }

  /// Fetches recent OTPs captured while Flutter UI was closed.
  static Future<List<OtpMessage>> fetchRecentNativeOtps() async {
    if (!Platform.isAndroid) return const [];
    try {
      final list = await _method.invokeListMethod<String>('getRecentOtps');
      if (list == null) return const [];
      return list
          .map((s) => OtpMessage.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Sends a test OTP through the exact native Kotlin pipeline (LAN / USB / Bluetooth).
  static Future<Map<String, dynamic>> sendTestOtpViaNative({
    required String code,
    required String sender,
  }) async {
    if (!Platform.isAndroid) return {'ok': false, 'error': 'Not Android'};
    try {
      final res = await _method.invokeMapMethod<String, dynamic>(
        'sendTestOtp',
        {'code': code, 'sender': sender},
      );
      return res ?? {'ok': false};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static Future<List<BondedBluetoothDevice>> getBondedBluetoothDevices() async {
    if (!Platform.isAndroid) return const [];
    try {
      final list = await _method.invokeListMethod<Map<dynamic, dynamic>>(
        'getBondedBluetoothDevices',
      );
      if (list == null) return const [];
      return list
          .map((m) => BondedBluetoothDevice(
                name: (m['name'] as String?) ?? 'Unknown',
                address: (m['address'] as String?) ?? '',
              ))
          .where((d) => d.address.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> openAppInfo() async {
    if (!Platform.isAndroid) return;
    await _method.invokeMethod<void>('openAppInfo');
  }

  static Future<void> openNotificationListenerSettings() async {
    if (!Platform.isAndroid) return;
    await _method.invokeMethod<void>('openNotificationListenerSettings');
  }

  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    await _method.invokeMethod<void>('openBatteryOptimizationSettings');
  }

  static Future<void> openOemAutostartSettings() async {
    if (!Platform.isAndroid) return;
    await _method.invokeMethod<void>('openOemAutostartSettings');
  }

  static Future<bool> requestSmsPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _method.invokeMethod<bool>('requestSmsPermission')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestBluetoothPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _method.invokeMethod<bool>('requestBluetoothPermission')) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
