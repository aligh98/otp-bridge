import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../constants.dart';
import '../models/otp_message.dart';
import '../security/e2ee_crypto.dart';
import '../security/frame_codec.dart';
import '../security/local_network_guard.dart';

/// Desktop local-only encrypted TCP receiver + UDP LAN discovery responder.
///
/// Serves BOTH:
/// - **Local Wi-Fi (LAN)** connections from paired Android devices on RFC1918 subnets
/// - **USB Cable (ADB reverse)** connections arriving on loopback `127.0.0.1`
///
/// Security hardening:
/// - When `allowWifiLan` is false, binds strictly to `127.0.0.1` (USB-only).
/// - Every accepted connection is validated by [LocalNetworkGuard].
/// - Enforces max concurrent sockets (`16`) and per-socket idle timeout (`10s`).
class DesktopLanServer {
  DesktopLanServer({
    required this.deviceId,
    required this.deviceName,
    required this.getSharedKey,
    this.tcpPort = AppConstants.defaultTcpPort,
    this.discoveryUdpPort = AppConstants.discoveryUdpPort,
    E2eeCrypto? crypto,
  }) : _crypto = crypto ?? E2eeCrypto();

  static const int _maxConcurrentClients = 16;
  static const Duration _clientIdleTimeout = Duration(seconds: 10);

  final String deviceId;
  final String deviceName;
  final String Function() getSharedKey;
  final int tcpPort;
  final int discoveryUdpPort;
  final E2eeCrypto _crypto;

  ServerSocket? _tcpServer;
  RawDatagramSocket? _udpSocket;
  final Set<Socket> _activeClients = {};
  final StreamController<OtpMessage> _otpController =
      StreamController<OtpMessage>.broadcast();
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  bool _running = false;
  int _boundPort = 0;

  bool get isRunning => _running;
  int get boundPort => _boundPort;
  Stream<OtpMessage> get onOtpReceived => _otpController.stream;
  Stream<String> get onStatusLog => _statusController.stream;

  Future<void> start({
    bool enableLanDiscovery = true,
    bool allowWifiLan = true,
  }) async {
    if (_running) return;

    // Bind strictly to loopback if Wi-Fi LAN is disabled (USB-only mode).
    final bindAddr =
        allowWifiLan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4;
    _tcpServer = await ServerSocket.bind(
      bindAddr,
      tcpPort,
      shared: true,
    );
    _boundPort = _tcpServer!.port;
    _running = true;
    _log(
      allowWifiLan
          ? 'Encrypted local receiver listening on LAN+USB port $_boundPort'
          : 'Encrypted receiver bound strictly to 127.0.0.1:$_boundPort (USB only)',
    );

    _tcpServer!.listen(
      _handleClientSocket,
      onError: (e) => _log('TCP server error: $e'),
    );

    if (allowWifiLan && enableLanDiscovery) {
      await _startUdpDiscovery();
    }
  }

  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryUdpPort,
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _udpSocket?.receive();
        if (datagram == null) return;

        // Enforce strictly local LAN peer!
        if (!LocalNetworkGuard.isAllowedInternetAddress(datagram.address)) {
          return;
        }

        final msg = utf8.decode(datagram.data, allowMalformed: true).trim();
        if (!msg.startsWith(AppConstants.discoveryMagic)) return;

        // Optional filter by target deviceId (`OTPBRIDGE_DISCOVER_V1:<deviceId>`)
        final parts = msg.split(':');
        if (parts.length >= 2 &&
            parts[1].isNotEmpty &&
            parts[1] != '*' &&
            parts[1] != deviceId) {
          return;
        }

        final response = jsonEncode({
          'magic': AppConstants.discoveryResponseMagic,
          'id': deviceId,
          'name': deviceName,
          'port': _boundPort,
        });
        _udpSocket?.send(
          utf8.encode(response),
          datagram.address,
          datagram.port,
        );
      });
      _log('LAN UDP discovery active on port $discoveryUdpPort');
    } catch (e) {
      _log('LAN UDP discovery unavailable (port busy): $e');
    }
  }

  void _handleClientSocket(Socket socket) {
    final remote = socket.remoteAddress;

    // Security Gate 1: strictly allow ONLY RFC1918 LAN or Loopback (USB adb reverse)
    if (!LocalNetworkGuard.isAllowedInternetAddress(remote)) {
      _log('SECURITY: Rejected non-local TCP connection from ${remote.address}');
      socket.destroy();
      return;
    }

    // Security Gate 2: cap concurrent connections to prevent resource exhaustion
    if (_activeClients.length >= _maxConcurrentClients) {
      _log('Rejected connection: max concurrent clients reached');
      socket.destroy();
      return;
    }

    _activeClients.add(socket);
    final isLoopback = remote.isLoopback;
    final decoder = FrameStreamDecoder();

    Timer? idleTimer;
    void resetIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(_clientIdleTimeout, () {
        _activeClients.remove(socket);
        socket.destroy();
      });
    }

    void cleanup() {
      idleTimer?.cancel();
      _activeClients.remove(socket);
    }

    resetIdleTimer();

    socket.listen(
      (chunk) async {
        resetIdleTimer();
        try {
          final frames = decoder.addChunk(chunk);
          for (final frame in frames) {
            await _processEncryptedFrame(
              frame: frame,
              socket: socket,
              transport: isLoopback ? TransportType.usb : TransportType.wifiLan,
            );
          }
        } catch (e) {
          _log('Dropped invalid frame from ${remote.address}: $e');
          cleanup();
          socket.destroy();
        }
      },
      onDone: cleanup,
      onError: (_) {
        cleanup();
        socket.destroy();
      },
      cancelOnError: true,
    );
  }

  /// Processes an encrypted frame received over TCP LAN, USB, or Bluetooth.
  Future<Uint8List?> processExternalEncryptedFrame(
    Uint8List encryptedFrame, {
    required TransportType transport,
  }) async {
    final key = getSharedKey();
    final envelope = await _crypto.decryptEnvelope(
      encryptedBytes: encryptedFrame,
      sharedKeyBase64: key,
    );

    if (envelope.type == 'otp') {
      final otp = OtpMessage.fromJson(envelope.data).copyWith(
        transport: transport,
      );
      if (otp.code.isNotEmpty && !_otpController.isClosed) {
        _otpController.add(otp);
        _log('Received OTP from ${otp.sender} via ${transport.name}');
      }
      return _crypto.encryptEnvelope(
        type: 'ack',
        data: {'ok': true, 'id': otp.id, 'deviceName': deviceName},
        sharedKeyBase64: key,
      );
    }

    if (envelope.type == 'ping') {
      return _crypto.encryptEnvelope(
        type: 'pong',
        data: {'ok': true, 'id': deviceId, 'deviceName': deviceName},
        sharedKeyBase64: key,
      );
    }

    return null;
  }

  Future<void> _processEncryptedFrame({
    required Uint8List frame,
    required Socket socket,
    required TransportType transport,
  }) async {
    try {
      final replyEncrypted = await processExternalEncryptedFrame(
        frame,
        transport: transport,
      );
      if (replyEncrypted != null) {
        socket.add(FrameCodec.encode(replyEncrypted));
        await socket.flush();
      }
    } on E2eeException catch (e) {
      _log('E2EE rejected packet from ${socket.remoteAddress.address}: ${e.message}');
    } catch (_) {
      // Peer closed socket before receiving ACK.
    }
  }

  void _log(String message) {
    if (!_statusController.isClosed) {
      _statusController.add(message);
    }
  }

  Future<void> stop() async {
    _running = false;
    for (final s in _activeClients.toList()) {
      s.destroy();
    }
    _activeClients.clear();
    _udpSocket?.close();
    _udpSocket = null;
    await _tcpServer?.close();
    _tcpServer = null;
  }

  Future<void> dispose() async {
    await stop();
    if (!_otpController.isClosed) await _otpController.close();
    if (!_statusController.isClosed) await _statusController.close();
  }
}
