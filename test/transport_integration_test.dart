import 'package:flutter_test/flutter_test.dart';
import 'package:otp_bridge/core/models/otp_message.dart';
import 'package:otp_bridge/core/security/e2ee_crypto.dart';
import 'package:otp_bridge/core/security/local_network_guard.dart';
import 'package:otp_bridge/core/transport/lan_client.dart';
import 'package:otp_bridge/core/transport/lan_server.dart';

void main() {
  test('end-to-end encrypted OTP transfer over local loopback socket (USB/LAN protocol)', () async {
    final sharedKey = E2eeCrypto.generateSharedKeyBase64();
    final server = DesktopLanServer(
      deviceId: 'desktop-test',
      deviceName: 'TestPC',
      getSharedKey: () => sharedKey,
      tcpPort: 0, // Ephemeral port for CI reliability
    );

    await server.start(enableLanDiscovery: false);
    addTearDown(server.dispose);

    final receivedFuture = server.onOtpReceived.first;
    final client = LocalTransportClient();

    final ok = await client.sendOtp(
      host: '127.0.0.1',
      port: server.boundPort,
      sharedKeyBase64: sharedKey,
      otp: OtpMessage(
        id: 'msg-1',
        code: '649281',
        sender: 'بانک ملت',
        source: OtpSource.sms,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    expect(ok, isTrue);
    final received = await receivedFuture.timeout(const Duration(seconds: 3));
    expect(received.code, '649281');
    expect(received.sender, 'بانک ملت');
    expect(received.transport, TransportType.usb); // Loopback maps to USB
  });

  test('client refuses to send OTP to public IP (zero-internet enforcement)', () async {
    final sharedKey = E2eeCrypto.generateSharedKeyBase64();
    final client = LocalTransportClient();

    expect(
      () => client.sendOtp(
        host: '8.8.8.8',
        port: 47831,
        sharedKeyBase64: sharedKey,
        otp: OtpMessage(
          id: 'msg-blocked',
          code: '123456',
          sender: 'Test',
          source: OtpSource.sms,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
      throwsA(isA<LocalNetworkViolationException>()),
    );
  });

  test('server rejects OTP encrypted with wrong shared key', () async {
    final serverKey = E2eeCrypto.generateSharedKeyBase64();
    final wrongKey = E2eeCrypto.generateSharedKeyBase64();
    final server = DesktopLanServer(
      deviceId: 'desktop-test-2',
      deviceName: 'TestPC',
      getSharedKey: () => serverKey,
      tcpPort: 0,
    );

    await server.start(enableLanDiscovery: false);
    addTearDown(server.dispose);

    final client = LocalTransportClient();
    final ok = await client.sendOtp(
      host: '127.0.0.1',
      port: server.boundPort,
      sharedKeyBase64: wrongKey,
      otp: OtpMessage(
        id: 'msg-bad',
        code: '000000',
        sender: 'Attacker',
        source: OtpSource.sms,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
      timeout: const Duration(milliseconds: 800),
    );

    expect(ok, isFalse);
  });
}
