/// Core protocol, networking, Bluetooth, and security constants for OtpBridge.
class AppConstants {
  AppConstants._();

  static const String appName = 'OtpBridge';
  static const String protocolVersion = '1';

  /// Local TCP port used for Wi-Fi LAN and USB (adb reverse) encrypted transport.
  static const int defaultTcpPort = 47831;

  /// Local UDP port used for LAN discovery (only on RFC1918 subnets).
  static const int discoveryUdpPort = 47832;

  /// Magic discovery header (verified before responding).
  static const String discoveryMagic = 'OTPBRIDGE_DISCOVER_V1';
  static const String discoveryResponseMagic = 'OTPBRIDGE_HERE_V1';

  /// Custom Bluetooth Classic RFCOMM / SPP Service UUID.
  static const String bluetoothServiceUuid =
      '8a7c4b2e-91f3-4d6a-b5e1-2c8f9a0d3e41';
  static const String bluetoothServiceName = 'OtpBridge Secure Link';

  /// Maximum allowed clock skew / replay window in seconds.
  static const int maxReplayWindowSeconds = 120;

  /// Deduplication window in seconds for hybrid SMS + Notification capture.
  static const int dedupWindowSeconds = 15;

  /// Maximum encrypted frame payload size (64 KB — prevents memory DoS).
  static const int maxFrameBytes = 64 * 1024;

  /// Default clipboard auto-clear duration in seconds (0 = disabled).
  static const int defaultClipboardClearSeconds = 60;

  /// Default toast display duration in seconds.
  static const int defaultToastDurationSeconds = 6;

  /// Platform channels.
  static const String androidMethodChannel = 'dev.otpbridge/android';
  static const String androidEventChannel = 'dev.otpbridge/android_events';
  static const String desktopBluetoothChannel = 'dev.otpbridge/bluetooth';
  static const String desktopClipboardChannel = 'dev.otpbridge/clipboard';
}
