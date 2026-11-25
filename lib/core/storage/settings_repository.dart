import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/paired_device.dart';
import '../security/e2ee_crypto.dart';

/// Purely local on-device persistence (zero cloud sync, zero remote telemetry).
class SettingsRepository {
  SettingsRepository._(this._prefs);

  static const _kSettings = 'otpbridge_settings_v1';
  static const _kLocalDeviceId = 'otpbridge_local_device_id';
  static const _kLocalSharedKey = 'otpbridge_desktop_shared_key';
  static const _kPairedDesktop = 'otpbridge_paired_desktop_v1';

  final SharedPreferences _prefs;

  static Future<SettingsRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsRepository._(prefs);
  }

  AppSettings loadSettings() {
    final raw = _prefs.getString(_kSettings);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
  }

  /// Persistent random local device UUID (generated locally, never sent online).
  Future<String> getOrCreateDeviceId() async {
    var id = _prefs.getString(_kLocalDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _prefs.setString(_kLocalDeviceId, id);
    }
    return id;
  }

  /// Desktop's 256-bit pre-shared E2EE key (regeneratable anytime to revoke paired phones).
  Future<String> getOrCreateDesktopSharedKey() async {
    var key = _prefs.getString(_kLocalSharedKey);
    if (key == null || key.isEmpty) {
      key = E2eeCrypto.generateSharedKeyBase64();
      await _prefs.setString(_kLocalSharedKey, key);
    }
    return key;
  }

  Future<String> rotateDesktopSharedKey() async {
    final key = E2eeCrypto.generateSharedKeyBase64();
    await _prefs.setString(_kLocalSharedKey, key);
    return key;
  }

  String getLocalDeviceName() {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    } catch (_) {}
    if (Platform.isWindows) return 'Windows PC';
    if (Platform.isLinux) return 'Linux PC';
    if (Platform.isAndroid) return 'Android Phone';
    return 'OtpBridge Device';
  }

  PairedDevice? loadPairedDesktop() {
    final raw = _prefs.getString(_kPairedDesktop);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PairedDevice.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePairedDesktop(PairedDevice? device) async {
    if (device == null) {
      await _prefs.remove(_kPairedDesktop);
    } else {
      await _prefs.setString(_kPairedDesktop, device.toJsonString());
    }
  }
}
