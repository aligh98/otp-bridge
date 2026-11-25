import '../constants.dart';
import 'otp_message.dart';

/// Local user settings for both Android and Desktop apps.
class AppSettings {
  const AppSettings({
    this.localeCode = 'fa',
    this.autoCopyOnDesktop = true,
    this.showReadyToast = true,
    this.clipboardClearSeconds = AppConstants.defaultClipboardClearSeconds,
    this.excludeFromClipboardHistory = true,
    this.minimizeToTrayOnClose = true,
    this.defaultTransport = TransportType.wifiLan,
    this.enableWifiLan = true,
    this.enableUsb = true,
    this.enableBluetooth = true,
    this.autoFallbackTransports = true,
    this.enableSmsCapture = true,
    this.enableNotificationCapture = true,
    this.sendSnippet = false,
    this.sensitivity = ParserSensitivity.balanced,
    this.tcpPort = AppConstants.defaultTcpPort,
    this.customAdbPath = '',
  });

  /// UI language ('fa' for Persian RTL, 'en' for English LTR).
  final String localeCode;

  /// Desktop: automatically copy incoming OTP to clipboard (default ON).
  final bool autoCopyOnDesktop;

  /// Desktop: show a sleek "✓ Copied / Ready to paste" notification badge.
  final bool showReadyToast;

  /// Desktop: clear clipboard after N seconds (0 = never).
  final int clipboardClearSeconds;

  /// Desktop (Windows): exclude OTP from Win+V Clipboard History.
  final bool excludeFromClipboardHistory;

  /// Desktop: hide to system tray instead of exiting on window close.
  final bool minimizeToTrayOnClose;

  /// Preferred default transport (default = Local Wi-Fi LAN).
  final TransportType defaultTransport;

  /// Optional transport toggles.
  final bool enableWifiLan;
  final bool enableUsb;
  final bool enableBluetooth;

  /// If primary transport fails, automatically try other enabled transports.
  final bool autoFallbackTransports;

  /// Android capture sources (Hybrid: SMS + NotificationListener).
  final bool enableSmsCapture;
  final bool enableNotificationCapture;

  /// Privacy: only send OTP + sender by default (no message body snippet).
  final bool sendSnippet;

  /// OTP parser sensitivity preset.
  final ParserSensitivity sensitivity;

  /// Local TCP port for LAN & USB.
  final int tcpPort;

  /// Optional custom `adb` binary path on Desktop for USB bridge.
  final String customAdbPath;

  bool get isPersian => localeCode == 'fa';

  AppSettings copyWith({
    String? localeCode,
    bool? autoCopyOnDesktop,
    bool? showReadyToast,
    int? clipboardClearSeconds,
    bool? excludeFromClipboardHistory,
    bool? minimizeToTrayOnClose,
    TransportType? defaultTransport,
    bool? enableWifiLan,
    bool? enableUsb,
    bool? enableBluetooth,
    bool? autoFallbackTransports,
    bool? enableSmsCapture,
    bool? enableNotificationCapture,
    bool? sendSnippet,
    ParserSensitivity? sensitivity,
    int? tcpPort,
    String? customAdbPath,
  }) {
    return AppSettings(
      localeCode: localeCode ?? this.localeCode,
      autoCopyOnDesktop: autoCopyOnDesktop ?? this.autoCopyOnDesktop,
      showReadyToast: showReadyToast ?? this.showReadyToast,
      clipboardClearSeconds:
          clipboardClearSeconds ?? this.clipboardClearSeconds,
      excludeFromClipboardHistory:
          excludeFromClipboardHistory ?? this.excludeFromClipboardHistory,
      minimizeToTrayOnClose:
          minimizeToTrayOnClose ?? this.minimizeToTrayOnClose,
      defaultTransport: defaultTransport ?? this.defaultTransport,
      enableWifiLan: enableWifiLan ?? this.enableWifiLan,
      enableUsb: enableUsb ?? this.enableUsb,
      enableBluetooth: enableBluetooth ?? this.enableBluetooth,
      autoFallbackTransports:
          autoFallbackTransports ?? this.autoFallbackTransports,
      enableSmsCapture: enableSmsCapture ?? this.enableSmsCapture,
      enableNotificationCapture:
          enableNotificationCapture ?? this.enableNotificationCapture,
      sendSnippet: sendSnippet ?? this.sendSnippet,
      sensitivity: sensitivity ?? this.sensitivity,
      tcpPort: tcpPort ?? this.tcpPort,
      customAdbPath: customAdbPath ?? this.customAdbPath,
    );
  }

  Map<String, dynamic> toJson() => {
        'localeCode': localeCode,
        'autoCopyOnDesktop': autoCopyOnDesktop,
        'showReadyToast': showReadyToast,
        'clipboardClearSeconds': clipboardClearSeconds,
        'excludeFromClipboardHistory': excludeFromClipboardHistory,
        'minimizeToTrayOnClose': minimizeToTrayOnClose,
        'defaultTransport': defaultTransport.wireValue,
        'enableWifiLan': enableWifiLan,
        'enableUsb': enableUsb,
        'enableBluetooth': enableBluetooth,
        'autoFallbackTransports': autoFallbackTransports,
        'enableSmsCapture': enableSmsCapture,
        'enableNotificationCapture': enableNotificationCapture,
        'sendSnippet': sendSnippet,
        'sensitivity': sensitivity.name,
        'tcpPort': tcpPort,
        'customAdbPath': customAdbPath,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      localeCode: (json['localeCode'] as String?) ?? 'fa',
      autoCopyOnDesktop: (json['autoCopyOnDesktop'] as bool?) ?? true,
      showReadyToast: (json['showReadyToast'] as bool?) ?? true,
      clipboardClearSeconds: (json['clipboardClearSeconds'] as num?)?.toInt() ??
          AppConstants.defaultClipboardClearSeconds,
      excludeFromClipboardHistory:
          (json['excludeFromClipboardHistory'] as bool?) ?? true,
      minimizeToTrayOnClose: (json['minimizeToTrayOnClose'] as bool?) ?? true,
      defaultTransport:
          TransportTypeX.fromWire(json['defaultTransport'] as String?),
      enableWifiLan: (json['enableWifiLan'] as bool?) ?? true,
      enableUsb: (json['enableUsb'] as bool?) ?? true,
      enableBluetooth: (json['enableBluetooth'] as bool?) ?? true,
      autoFallbackTransports: (json['autoFallbackTransports'] as bool?) ?? true,
      enableSmsCapture: (json['enableSmsCapture'] as bool?) ?? true,
      enableNotificationCapture:
          (json['enableNotificationCapture'] as bool?) ?? true,
      sendSnippet: (json['sendSnippet'] as bool?) ?? false,
      sensitivity: ParserSensitivity.values.firstWhere(
        (e) => e.name == json['sensitivity'],
        orElse: () => ParserSensitivity.balanced,
      ),
      tcpPort:
          (json['tcpPort'] as num?)?.toInt() ?? AppConstants.defaultTcpPort,
      customAdbPath: (json['customAdbPath'] as String?) ?? '',
    );
  }
}
