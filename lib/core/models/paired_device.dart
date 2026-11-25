import 'dart:convert';

import 'otp_message.dart';

/// Represents a paired peer device stored locally on-device.
class PairedDevice {
  PairedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.sharedKeyBase64,
    required this.lanIps,
    required this.tcpPort,
    this.bluetoothAddress,
    this.bluetoothName,
    this.pairedAtMs,
    this.lastSeenMs,
  });

  final String deviceId;
  final String deviceName;
  final String sharedKeyBase64;
  final List<String> lanIps;
  final int tcpPort;
  final String? bluetoothAddress;
  final String? bluetoothName;
  final int? pairedAtMs;
  final int? lastSeenMs;

  PairedDevice copyWith({
    String? deviceName,
    List<String>? lanIps,
    int? tcpPort,
    String? bluetoothAddress,
    String? bluetoothName,
    int? lastSeenMs,
  }) {
    return PairedDevice(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      sharedKeyBase64: sharedKeyBase64,
      lanIps: lanIps ?? this.lanIps,
      tcpPort: tcpPort ?? this.tcpPort,
      bluetoothAddress: bluetoothAddress ?? this.bluetoothAddress,
      bluetoothName: bluetoothName ?? this.bluetoothName,
      pairedAtMs: pairedAtMs,
      lastSeenMs: lastSeenMs ?? this.lastSeenMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': deviceId,
        'name': deviceName,
        'key': sharedKeyBase64,
        'ips': lanIps,
        'port': tcpPort,
        if (bluetoothAddress != null) 'btAddr': bluetoothAddress,
        if (bluetoothName != null) 'btName': bluetoothName,
        if (pairedAtMs != null) 'pairedAt': pairedAtMs,
        if (lastSeenMs != null) 'lastSeen': lastSeenMs,
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    return PairedDevice(
      deviceId: json['id'] as String,
      deviceName: (json['name'] as String?) ?? 'Desktop',
      sharedKeyBase64: json['key'] as String,
      lanIps: ((json['ips'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      tcpPort: (json['port'] as num?)?.toInt() ?? 47831,
      bluetoothAddress: json['btAddr'] as String?,
      bluetoothName: json['btName'] as String?,
      pairedAtMs: (json['pairedAt'] as num?)?.toInt(),
      lastSeenMs: (json['lastSeen'] as num?)?.toInt(),
    );
  }

  factory PairedDevice.fromPairingPayload(PairingPayload payload) {
    return PairedDevice(
      deviceId: payload.deviceId,
      deviceName: payload.deviceName,
      sharedKeyBase64: payload.sharedKeyBase64,
      lanIps: payload.lanIps,
      tcpPort: payload.tcpPort,
      bluetoothAddress: payload.bluetoothAddress,
      pairedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String toJsonString() => jsonEncode(toJson());
}
