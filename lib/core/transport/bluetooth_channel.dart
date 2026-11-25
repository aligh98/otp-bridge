import 'dart:async';

import 'package:flutter/services.dart';

import '../constants.dart';

class BluetoothServerStatus {
  const BluetoothServerStatus({
    required this.supported,
    required this.running,
    this.adapterAddress,
    this.message = '',
  });

  final bool supported;
  final bool running;
  final String? adapterAddress;
  final String message;
}

/// Cross-platform native Bluetooth Classic RFCOMM bridge for Desktop (Windows & Linux).
///
/// The native C++ runner listens on custom SPP UUID [AppConstants.bluetoothServiceUuid],
/// forwards incoming encrypted binary frames to Dart via MethodChannel, and writes back
/// encrypted ACK frames.
class DesktopBluetoothBridge {
  DesktopBluetoothBridge({
    required this.onEncryptedFrame,
  }) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const MethodChannel _channel =
      MethodChannel(AppConstants.desktopBluetoothChannel);

  /// Callback that decrypts an incoming RFCOMM frame and returns an encrypted ACK frame.
  final Future<Uint8List?> Function(Uint8List frame) onEncryptedFrame;

  final StreamController<BluetoothServerStatus> _statusController =
      StreamController<BluetoothServerStatus>.broadcast();

  BluetoothServerStatus _status = const BluetoothServerStatus(
    supported: false,
    running: false,
    message: 'Bluetooth server idle',
  );

  BluetoothServerStatus get currentStatus => _status;
  Stream<BluetoothServerStatus> get onStatusChanged => _statusController.stream;

  Future<BluetoothServerStatus> startServer() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'startServer',
        {
          'uuid': AppConstants.bluetoothServiceUuid,
          'serviceName': AppConstants.bluetoothServiceName,
        },
      );
      final status = BluetoothServerStatus(
        supported: (res?['supported'] as bool?) ?? false,
        running: (res?['running'] as bool?) ?? false,
        adapterAddress: res?['address'] as String?,
        message: (res?['message'] as String?) ?? '',
      );
      _emit(status);
      return status;
    } on MissingPluginException {
      const status = BluetoothServerStatus(
        supported: false,
        running: false,
        message: 'Bluetooth RFCOMM channel unavailable on this platform',
      );
      _emit(status);
      return status;
    } catch (e) {
      final status = BluetoothServerStatus(
        supported: false,
        running: false,
        message: 'Bluetooth error: $e',
      );
      _emit(status);
      return status;
    }
  }

  Future<void> stopServer() async {
    try {
      await _channel.invokeMethod<void>('stopServer');
    } catch (_) {}
    _emit(BluetoothServerStatus(
      supported: _status.supported,
      running: false,
      adapterAddress: _status.adapterAddress,
      message: 'Bluetooth server stopped',
    ));
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onFrame') {
      final args = call.arguments;
      if (args is Uint8List) {
        return await onEncryptedFrame(args);
      }
    }
    return null;
  }

  void _emit(BluetoothServerStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  Future<void> dispose() async {
    await stopServer();
    await _statusController.close();
  }
}
