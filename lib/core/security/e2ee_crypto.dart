import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../constants.dart';

/// End-to-End Encryption (E2EE) using AES-256-GCM with replay protection.
///
/// Binary envelope layout (100% compatible with Android Kotlin `NativeE2eeCrypto`):
///   [0]       : Protocol version byte (0x01)
///   [1..12]   : 12-byte random GCM IV/nonce
///   [13..N-17]: AES-256-GCM ciphertext
///   [N-16..N] : 16-byte GCM authentication tag
///
/// Associated Authenticated Data (AAD): UTF-8 bytes of "otpbridge:v1".
class E2eeCrypto {
  E2eeCrypto({
    this.maxReplayWindowSeconds = AppConstants.maxReplayWindowSeconds,
  });

  static const int _versionByte = 0x01;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static final List<int> _aad = utf8.encode('otpbridge:v1');

  final int maxReplayWindowSeconds;
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Random _random = Random.secure();

  /// Replay cache: nonceHex -> receivedAtMs.
  final Map<String, int> _seenNonces = {};

  /// Generates a cryptographically secure 256-bit pre-shared key (base64url).
  static String generateSharedKeyBase64() {
    final rng = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Decodes a base64url (or standard base64) 32-byte key.
  static Uint8List decodeKey(String keyBase64) {
    final normalized = base64Url.normalize(keyBase64.trim());
    final bytes = base64Url.decode(normalized);
    if (bytes.length != 32) {
      throw ArgumentError('Expected 32-byte AES-256 key, got ${bytes.length}');
    }
    return Uint8List.fromList(bytes);
  }

  /// Encrypts a structured message envelope with AES-256-GCM + timestamp + replay nonce.
  Future<Uint8List> encryptEnvelope({
    required String type,
    required Map<String, dynamic> data,
    required String sharedKeyBase64,
    int? timestampMs,
  }) async {
    final keyBytes = decodeKey(sharedKeyBase64);
    final secretKey = SecretKey(keyBytes);

    final iv = Uint8List(_nonceLength);
    for (var i = 0; i < _nonceLength; i++) {
      iv[i] = _random.nextInt(256);
    }

    final replayNonce = _randomHex(16);
    final nowMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

    final plaintextJson = jsonEncode({
      't': type,
      'ts': nowMs,
      'nonce': replayNonce,
      'data': data,
    });
    final plaintextBytes = utf8.encode(plaintextJson);

    final secretBox = await _aesGcm.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: iv,
      aad: _aad,
    );

    final out = Uint8List(
      1 + _nonceLength + secretBox.cipherText.length + _macLength,
    );
    out[0] = _versionByte;
    out.setRange(1, 1 + _nonceLength, iv);
    out.setRange(
      1 + _nonceLength,
      1 + _nonceLength + secretBox.cipherText.length,
      secretBox.cipherText,
    );
    out.setRange(
      1 + _nonceLength + secretBox.cipherText.length,
      out.length,
      secretBox.mac.bytes,
    );
    return out;
  }

  /// Decrypts, authenticates (AEAD), validates timestamp window, and checks replay cache.
  Future<DecryptedEnvelope> decryptEnvelope({
    required Uint8List encryptedBytes,
    required String sharedKeyBase64,
    bool checkReplay = true,
    int? nowMsOverride,
  }) async {
    if (encryptedBytes.length < 1 + _nonceLength + _macLength + 2) {
      throw const E2eeException('Encrypted frame too short');
    }
    if (encryptedBytes[0] != _versionByte) {
      throw E2eeException('Unsupported protocol version: ${encryptedBytes[0]}');
    }

    final keyBytes = decodeKey(sharedKeyBase64);
    final secretKey = SecretKey(keyBytes);

    final iv = encryptedBytes.sublist(1, 1 + _nonceLength);
    final cipherEnd = encryptedBytes.length - _macLength;
    final cipherText = encryptedBytes.sublist(1 + _nonceLength, cipherEnd);
    final macBytes = encryptedBytes.sublist(cipherEnd);

    final secretBox = SecretBox(
      cipherText,
      nonce: iv,
      mac: Mac(macBytes),
    );

    List<int> plaintextBytes;
    try {
      plaintextBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: _aad,
      );
    } on SecretBoxAuthenticationError {
      throw const E2eeException(
        'Authentication failed: wrong pairing key or tampered packet',
      );
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(utf8.decode(plaintextBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const E2eeException('Decrypted payload is not valid JSON');
    }

    final type = (decoded['t'] as String?) ?? '';
    final ts = (decoded['ts'] as num?)?.toInt();
    final nonce = (decoded['nonce'] as String?) ?? '';
    final data = (decoded['data'] as Map<String, dynamic>?) ?? const {};

    if (type.isEmpty || ts == null || nonce.isEmpty) {
      throw const E2eeException('Missing required envelope fields');
    }

    if (checkReplay) {
      final nowMs = nowMsOverride ?? DateTime.now().millisecondsSinceEpoch;
      final skewMs = (nowMs - ts).abs();
      if (skewMs > maxReplayWindowSeconds * 1000) {
        throw E2eeException(
          'Rejected stale/replayed packet (clock skew ${(skewMs / 1000).round()}s)',
        );
      }

      _pruneNonces(nowMs);
      if (_seenNonces.containsKey(nonce)) {
        throw const E2eeException('Rejected duplicate replay nonce');
      }
      _seenNonces[nonce] = nowMs;
    }

    return DecryptedEnvelope(
      type: type,
      timestampMs: ts,
      nonce: nonce,
      data: data,
    );
  }

  void _pruneNonces(int nowMs) {
    final cutoff = nowMs - (maxReplayWindowSeconds * 1000 * 2);
    _seenNonces.removeWhere((_, seenAt) => seenAt < cutoff);
  }

  String _randomHex(int numBytes) {
    final sb = StringBuffer();
    for (var i = 0; i < numBytes; i++) {
      sb.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

class DecryptedEnvelope {
  const DecryptedEnvelope({
    required this.type,
    required this.timestampMs,
    required this.nonce,
    required this.data,
  });

  final String type;
  final int timestampMs;
  final String nonce;
  final Map<String, dynamic> data;
}

class E2eeException implements Exception {
  const E2eeException(this.message);
  final String message;

  @override
  String toString() => 'E2eeException: $message';
}
