import 'dart:async';
import 'dart:io';

import '../constants.dart';

class UsbBridgeStatus {
  const UsbBridgeStatus({
    required this.adbAvailable,
    required this.connectedDeviceSerials,
    required this.reverseActive,
    this.adbBinaryPath,
    this.message = '',
  });

  final bool adbAvailable;
  final List<String> connectedDeviceSerials;
  final bool reverseActive;
  final String? adbBinaryPath;
  final String message;

  bool get isConnected =>
      adbAvailable && connectedDeviceSerials.isNotEmpty && reverseActive;
}

/// Desktop USB Cable Bridge using `adb reverse tcp:<port> tcp:<port>`.
///
/// Works 100% offline, bypasses Wi-Fi and Desktop VPNs completely, and tunnels
/// the same AES-256-GCM encrypted protocol over `127.0.0.1`.
class UsbBridgeService {
  UsbBridgeService({
    this.tcpPort = AppConstants.defaultTcpPort,
    this.customAdbPath = '',
  });

  final int tcpPort;
  String customAdbPath;

  Timer? _pollTimer;
  bool _enabled = false;
  final Set<String> _reversedSerials = {};
  UsbBridgeStatus _lastStatus = const UsbBridgeStatus(
    adbAvailable: false,
    connectedDeviceSerials: [],
    reverseActive: false,
    message: 'USB bridge stopped',
  );

  final StreamController<UsbBridgeStatus> _statusController =
      StreamController<UsbBridgeStatus>.broadcast();

  UsbBridgeStatus get currentStatus => _lastStatus;
  Stream<UsbBridgeStatus> get onStatusChanged => _statusController.stream;

  Future<void> start({String? customPath}) async {
    if (customPath != null) customAdbPath = customPath;
    _enabled = true;
    _reversedSerials.clear();
    await refreshNow();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => refreshNow(),
    );
  }

  Future<void> stop() async {
    _enabled = false;
    _reversedSerials.clear();
    _pollTimer?.cancel();
    _pollTimer = null;
    _emit(const UsbBridgeStatus(
      adbAvailable: false,
      connectedDeviceSerials: [],
      reverseActive: false,
      message: 'USB bridge disabled',
    ));
  }

  Future<UsbBridgeStatus> refreshNow({bool forceRebind = false}) async {
    if (!_enabled) return _lastStatus;
    final adb = await _resolveAdbExecutable();
    if (adb == null) {
      _reversedSerials.clear();
      return _emit(const UsbBridgeStatus(
        adbAvailable: false,
        connectedDeviceSerials: [],
        reverseActive: false,
        message: 'ADB not found in PATH (install Android Platform Tools for USB mode)',
      ));
    }

    try {
      final devicesRes = await Process.run(adb, const ['devices']);
      if (devicesRes.exitCode != 0) {
        _reversedSerials.clear();
        return _emit(UsbBridgeStatus(
          adbAvailable: true,
          connectedDeviceSerials: const [],
          reverseActive: false,
          adbBinaryPath: adb,
          message: 'adb devices failed: ${devicesRes.stderr}',
        ));
      }

      final lines = (devicesRes.stdout as String).split('\n');
      final serials = <String>[];
      var hasUnauthorized = false;

      for (final rawLine in lines.skip(1)) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          if (parts[1] == 'device') {
            serials.add(parts[0]);
          } else if (parts[1] == 'unauthorized') {
            hasUnauthorized = true;
          }
        }
      }

      // Drop disconnected devices from cache so reconnect re-applies adb reverse
      _reversedSerials.removeWhere((s) => !serials.contains(s));

      if (serials.isEmpty) {
        return _emit(UsbBridgeStatus(
          adbAvailable: true,
          connectedDeviceSerials: const [],
          reverseActive: false,
          adbBinaryPath: adb,
          message: hasUnauthorized
              ? 'Please accept the "Allow USB Debugging" prompt on your Android phone'
              : 'Waiting for Android phone over USB cable...',
        ));
      }

      // Only run `adb reverse` for newly attached devices (or forced refresh)
      for (final serial in serials) {
        if (forceRebind || !_reversedSerials.contains(serial)) {
          final rev = await Process.run(
            adb,
            ['-s', serial, 'reverse', 'tcp:$tcpPort', 'tcp:$tcpPort'],
          );
          if (rev.exitCode == 0) {
            _reversedSerials.add(serial);
          }
        }
      }

      final anyOk = _reversedSerials.isNotEmpty;
      return _emit(UsbBridgeStatus(
        adbAvailable: true,
        connectedDeviceSerials: serials,
        reverseActive: anyOk,
        adbBinaryPath: adb,
        message: anyOk
            ? 'USB tunnel active (${serials.length} device${serials.length > 1 ? "s" : ""})'
            : 'Failed to setup adb reverse tunnel',
      ));
    } catch (e) {
      return _emit(UsbBridgeStatus(
        adbAvailable: true,
        connectedDeviceSerials: const [],
        reverseActive: false,
        adbBinaryPath: adb,
        message: 'USB bridge error: $e',
      ));
    }
  }

  Future<String?> _resolveAdbExecutable() async {
    final candidates = <String>[
      if (customAdbPath.trim().isNotEmpty) customAdbPath.trim(),
      if (Platform.isWindows) 'adb.exe',
      'adb',
      if (Platform.isLinux) '/usr/bin/adb',
      if (Platform.isLinux) '/opt/android-sdk/platform-tools/adb',
      if (Platform.isWindows)
        '${Platform.environment['LOCALAPPDATA'] ?? ''}\\Android\\Sdk\\platform-tools\\adb.exe',
    ];

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      try {
        final res = await Process.run(candidate, const ['version']);
        if (res.exitCode == 0) return candidate;
      } catch (_) {}
    }
    return null;
  }

  UsbBridgeStatus _emit(UsbBridgeStatus status) {
    _lastStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
    return status;
  }

  Future<void> dispose() async {
    await stop();
    await _statusController.close();
  }
}
