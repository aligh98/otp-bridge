import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import '../models/otp_message.dart';
import '../models/paired_device.dart';
import '../security/e2ee_crypto.dart';
import '../security/frame_codec.dart';
import '../security/local_network_guard.dart';

class DiscoveredDesktop {
  const DiscoveredDesktop({
    required this.deviceId,
    required this.deviceName,
    required this.ip,
    required this.port,
  });

  final String deviceId;
  final String deviceName;
  final String ip;
  final int port;
}

/// Encrypted local-only TCP/UDP client used by Android UI (test/ping/discovery)
/// and integration tests. All sockets pass through [LocalNetworkGuard].
class LocalTransportClient {
  LocalTransportClient({E2eeCrypto? crypto}) : _crypto = crypto ?? E2eeCrypto();

  final E2eeCrypto _crypto;

  /// Sends an encrypted OTP frame to a strictly local IP (LAN or 127.0.0.1 USB)
  /// and verifies the encrypted ACK from Desktop.
  Future<bool> sendOtp({
    required String host,
    required int port,
    required String sharedKeyBase64,
    required OtpMessage otp,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    return _sendEnvelope(
      host: host,
      port: port,
      sharedKeyBase64: sharedKeyBase64,
      type: 'otp',
      data: otp.toJson(),
      expectedReplyType: 'ack',
      timeout: timeout,
    );
  }

  /// Sends an encrypted ping to test connectivity & E2EE key match.
  Future<bool> ping({
    required String host,
    required int port,
    required String sharedKeyBase64,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    return _sendEnvelope(
      host: host,
      port: port,
      sharedKeyBase64: sharedKeyBase64,
      type: 'ping',
      data: {'ts': DateTime.now().millisecondsSinceEpoch},
      expectedReplyType: 'pong',
      timeout: timeout,
    );
  }

  Future<bool> _sendEnvelope({
    required String host,
    required int port,
    required String sharedKeyBase64,
    required String type,
    required Map<String, dynamic> data,
    required String expectedReplyType,
    required Duration timeout,
  }) async {
    // Hard security enforcement: NEVER allow public IP or DNS resolution.
    final allowedAddress = LocalNetworkGuard.assertAllowedHost(host);

    Socket? socket;
    try {
      socket = await Socket.connect(allowedAddress, port, timeout: timeout);
      final encrypted = await _crypto.encryptEnvelope(
        type: type,
        data: data,
        sharedKeyBase64: sharedKeyBase64,
      );
      socket.add(FrameCodec.encode(encrypted));
      await socket.flush();

      final completer = Completer<bool>();
      final decoder = FrameStreamDecoder();

      final sub = socket.listen(
        (chunk) async {
          try {
            final frames = decoder.addChunk(chunk);
            if (frames.isEmpty) return;
            final reply = await _crypto.decryptEnvelope(
              encryptedBytes: frames.first,
              sharedKeyBase64: sharedKeyBase64,
            );
            if (!completer.isCompleted) {
              completer.complete(
                reply.type == expectedReplyType && reply.data['ok'] == true,
              );
            }
          } catch (_) {
            if (!completer.isCompleted) completer.complete(false);
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => false,
      );
      await sub.cancel();
      return result;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Broadcasts a local UDP discovery probe on the LAN to locate a paired
  /// desktop whose DHCP IP may have changed.
  Future<List<DiscoveredDesktop>> discoverOnLan({
    String? targetDeviceId,
    int discoveryPort = AppConstants.discoveryUdpPort,
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final found = <String, DiscoveredDesktop>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final probe = targetDeviceId != null
          ? '${AppConstants.discoveryMagic}:$targetDeviceId'
          : '${AppConstants.discoveryMagic}:*';
      final bytes = utf8.encode(probe);

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket?.receive();
        if (dg == null) return;
        if (!LocalNetworkGuard.isAllowedInternetAddress(dg.address)) return;

        try {
          final map =
              jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          if (map['magic'] != AppConstants.discoveryResponseMagic) return;
          final id = (map['id'] as String?) ?? '';
          if (id.isEmpty) return;
          if (targetDeviceId != null && id != targetDeviceId) return;
          found[id] = DiscoveredDesktop(
            deviceId: id,
            deviceName: (map['name'] as String?) ?? 'Desktop',
            ip: dg.address.address,
            port: (map['port'] as num?)?.toInt() ?? AppConstants.defaultTcpPort,
          );
        } catch (_) {}
      });

      // Broadcast on local /24 subnets + global LAN broadcast for router compatibility
      final targets = <String>{'255.255.255.255'};
      final localIps = await LocalNetworkGuard.getLocalPrivateIpv4Addresses();
      for (final ip in localIps) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
      for (final target in targets) {
        try {
          socket.send(bytes, InternetAddress(target), discoveryPort);
        } catch (_) {}
      }
      await Future<void>.delayed(timeout);
    } catch (_) {
      // Ignore broadcast errors on restricted networks.
    } finally {
      socket?.close();
    }
    return found.values.toList();
  }

  /// Tries sending OTP via enabled local TCP paths (USB 127.0.0.1 and LAN IPs).
  Future<TransportType?> sendToPairedDesktop({
    required PairedDevice desktop,
    required OtpMessage otp,
    required TransportType preferred,
    required bool allowWifiLan,
    required bool allowUsb,
    required bool allowFallback,
  }) async {
    final attempts = <TransportType>[];
    if (preferred == TransportType.usb && allowUsb) {
      attempts.add(TransportType.usb);
    } else if (preferred == TransportType.wifiLan && allowWifiLan) {
      attempts.add(TransportType.wifiLan);
    }

    if (allowFallback) {
      if (allowUsb && !attempts.contains(TransportType.usb)) {
        attempts.add(TransportType.usb);
      }
      if (allowWifiLan && !attempts.contains(TransportType.wifiLan)) {
        attempts.add(TransportType.wifiLan);
      }
    }

    for (final mode in attempts) {
      if (mode == TransportType.usb) {
        final ok = await sendOtp(
          host: '127.0.0.1',
          port: desktop.tcpPort,
          sharedKeyBase64: desktop.sharedKeyBase64,
          otp: otp.copyWith(transport: TransportType.usb),
          timeout: const Duration(milliseconds: 1200),
        );
        if (ok) return TransportType.usb;
      } else if (mode == TransportType.wifiLan) {
        for (final ip in desktop.lanIps) {
          if (!LocalNetworkGuard.isAllowedLocalAddress(ip)) continue;
          final ok = await sendOtp(
            host: ip,
            port: desktop.tcpPort,
            sharedKeyBase64: desktop.sharedKeyBase64,
            otp: otp.copyWith(transport: TransportType.wifiLan),
            timeout: const Duration(milliseconds: 2200),
          );
          if (ok) return TransportType.wifiLan;
        }
      }
    }
    return null;
  }
}
