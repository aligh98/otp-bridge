import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otp_bridge/core/models/otp_message.dart';
import 'package:otp_bridge/core/security/e2ee_crypto.dart';
import 'package:otp_bridge/core/security/frame_codec.dart';
import 'package:otp_bridge/core/security/local_network_guard.dart';

void main() {
  group('LocalNetworkGuard (Strict Zero-Internet Enforcement)', () {
    test('allows RFC1918 private LAN, link-local, and loopback IPs', () {
      expect(LocalNetworkGuard.isAllowedLocalAddress('127.0.0.1'), isTrue);
      expect(LocalNetworkGuard.isAllowedLocalAddress('::1'), isTrue);
      expect(LocalNetworkGuard.isAllowedLocalAddress('192.168.1.42'), isTrue);
      expect(LocalNetworkGuard.isAllowedLocalAddress('10.0.0.5'), isTrue);
      expect(LocalNetworkGuard.isAllowedLocalAddress('172.16.0.1'), isTrue);
      expect(LocalNetworkGuard.isAllowedLocalAddress('172.31.255.254'), isTrue);
      expect(LocalNetworkGuard.isAllowedLocalAddress('169.254.10.20'), isTrue);
      expect(LocalNetworkGuard.isAllowedLocalAddress('::ffff:192.168.1.5'), isTrue);
      expect(LocalNetworkGuard.isAllowedLocalAddress('::ffff:127.0.0.1'), isTrue);
    });

    test('blocks ALL public IPs and ALL domain names (zero DNS leakage)', () {
      expect(LocalNetworkGuard.isAllowedLocalAddress('8.8.8.8'), isFalse);
      expect(LocalNetworkGuard.isAllowedLocalAddress('1.1.1.1'), isFalse);
      expect(LocalNetworkGuard.isAllowedLocalAddress('::ffff:8.8.8.8'), isFalse);
      expect(LocalNetworkGuard.isAllowedLocalAddress('172.15.0.1'), isFalse);
      expect(LocalNetworkGuard.isAllowedLocalAddress('172.32.0.1'), isFalse);
      expect(LocalNetworkGuard.isAllowedLocalAddress('192.169.1.1'), isFalse);
      expect(LocalNetworkGuard.isAllowedLocalAddress('192.168.1.999'), isFalse);
      expect(LocalNetworkGuard.isAllowedLocalAddress('google.com'), isFalse);
      expect(LocalNetworkGuard.isAllowedLocalAddress('google.com:80'), isFalse);
      expect(LocalNetworkGuard.isAllowedLocalAddress('localhost'), isFalse);
      expect(LocalNetworkGuard.isAllowedLocalAddress(''), isFalse);

      expect(
        () => LocalNetworkGuard.assertAllowedHost('8.8.8.8'),
        throwsA(isA<LocalNetworkViolationException>()),
      );
      expect(
        () => LocalNetworkGuard.assertAllowedHost('example.com'),
        throwsA(isA<LocalNetworkViolationException>()),
      );
    });
  });

  group('E2eeCrypto (AES-256-GCM + Replay Protection)', () {
    test('encrypts and decrypts envelope roundtrip', () async {
      final crypto = E2eeCrypto();
      final key = E2eeCrypto.generateSharedKeyBase64();

      final encrypted = await crypto.encryptEnvelope(
        type: 'otp',
        data: {'code': '649281', 'sender': 'بانک ملت'},
        sharedKeyBase64: key,
      );

      final decrypted = await crypto.decryptEnvelope(
        encryptedBytes: encrypted,
        sharedKeyBase64: key,
      );

      expect(decrypted.type, 'otp');
      expect(decrypted.data['code'], '649281');
      expect(decrypted.data['sender'], 'بانک ملت');
    });

    test('rejects wrong key and tampered ciphertext', () async {
      final crypto = E2eeCrypto();
      final key1 = E2eeCrypto.generateSharedKeyBase64();
      final key2 = E2eeCrypto.generateSharedKeyBase64();

      final encrypted = await crypto.encryptEnvelope(
        type: 'otp',
        data: {'code': '123456'},
        sharedKeyBase64: key1,
      );

      expect(
        () => crypto.decryptEnvelope(
          encryptedBytes: encrypted,
          sharedKeyBase64: key2,
        ),
        throwsA(isA<E2eeException>()),
      );

      // Flip a single bit in ciphertext
      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 5] ^= 0x01;
      expect(
        () => crypto.decryptEnvelope(
          encryptedBytes: tampered,
          sharedKeyBase64: key1,
        ),
        throwsA(isA<E2eeException>()),
      );
    });

    test('rejects replayed packet with duplicate nonce and stale timestamp', () async {
      final crypto = E2eeCrypto(maxReplayWindowSeconds: 60);
      final key = E2eeCrypto.generateSharedKeyBase64();

      final encrypted = await crypto.encryptEnvelope(
        type: 'otp',
        data: {'code': '998877'},
        sharedKeyBase64: key,
      );

      // First delivery succeeds
      await crypto.decryptEnvelope(
        encryptedBytes: encrypted,
        sharedKeyBase64: key,
      );

      // Exact replay rejected
      expect(
        () => crypto.decryptEnvelope(
          encryptedBytes: encrypted,
          sharedKeyBase64: key,
        ),
        throwsA(isA<E2eeException>()),
      );

      // Stale timestamp (>60s old) rejected
      final oldPacket = await crypto.encryptEnvelope(
        type: 'otp',
        data: {'code': '112233'},
        sharedKeyBase64: key,
        timestampMs: DateTime.now().millisecondsSinceEpoch - 180 * 1000,
      );
      expect(
        () => crypto.decryptEnvelope(
          encryptedBytes: oldPacket,
          sharedKeyBase64: key,
        ),
        throwsA(isA<E2eeException>()),
      );
    });
  });

  group('PairingPayload & FrameCodec', () {
    test('roundtrips compact QR URI', () {
      final key = E2eeCrypto.generateSharedKeyBase64();
      final payload = PairingPayload(
        version: 1,
        deviceId: 'pc-1',
        deviceName: 'MyLinuxPC',
        sharedKeyBase64: key,
        lanIps: ['192.168.1.15'],
        tcpPort: 47831,
        bluetoothAddress: 'AA:BB:CC:DD:EE:FF',
      );

      final uri = payload.toUriString();
      expect(uri.startsWith('otpbridge://pair?d='), isTrue);

      final parsed = PairingPayload.tryParse(uri);
      expect(parsed, isNotNull);
      expect(parsed!.deviceId, 'pc-1');
      expect(parsed.deviceName, 'MyLinuxPC');
      expect(parsed.sharedKeyBase64, key);
      expect(parsed.lanIps, ['192.168.1.15']);
      expect(parsed.bluetoothAddress, 'AA:BB:CC:DD:EE:FF');
    });

    test('decodes fragmented multi-chunk frames cleanly', () {
      final decoder = FrameStreamDecoder();
      final raw = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7]);
      final framed = FrameCodec.encode(raw);

      // Feed 2 bytes at a time
      final out = <Uint8List>[];
      for (var i = 0; i < framed.length; i += 2) {
        final end = (i + 2 > framed.length) ? framed.length : i + 2;
        out.addAll(decoder.addChunk(framed.sublist(i, end)));
      }
      expect(out.length, 1);
      expect(out.first, raw);
    });
  });
}
