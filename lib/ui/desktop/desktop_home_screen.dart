import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/otp_message.dart';
import '../../core/otp_parser/otp_deduplicator.dart';
import '../../core/security/local_network_guard.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/transport/bluetooth_channel.dart';
import '../../core/transport/lan_server.dart';
import '../../core/transport/usb_bridge_service.dart';
import '../../platform/desktop_clipboard.dart';
import '../../platform/desktop_tray_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/otp_tester_view.dart';
import '../widgets/otp_toast_overlay.dart';
import '../widgets/transport_badge.dart';

/// Main Desktop (Windows & Linux) dashboard for OtpBridge.
class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.onSettingsChanged,
  });

  final SettingsRepository repository;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  int _selectedTab = 0;

  late String _deviceId;
  late String _deviceName;
  late String _sharedKey;
  List<String> _lanIps = const [];

  DesktopLanServer? _lanServer;
  UsbBridgeService? _usbBridge;
  DesktopBluetoothBridge? _btBridge;
  DesktopTrayController? _trayController;

  final DesktopClipboardService _clipboard = DesktopClipboardService();
  final OtpDeduplicator _deduplicator = OtpDeduplicator();
  final List<OtpMessage> _otps = [];
  final List<String> _logs = [];

  OtpMessage? _activeToastOtp;
  Timer? _toastTimer;
  StreamSubscription<OtpMessage>? _otpSub;
  StreamSubscription<String>? _logSub;
  StreamSubscription<UsbBridgeStatus>? _usbSub;
  StreamSubscription<BluetoothServerStatus>? _btSub;
  bool _disposed = false;

  UsbBridgeStatus _usbStatus = const UsbBridgeStatus(
    adbAvailable: false,
    connectedDeviceSerials: [],
    reverseActive: false,
  );
  BluetoothServerStatus _btStatus = const BluetoothServerStatus(
    supported: false,
    running: false,
  );
  bool _ready = false;

  AppSettings get _settings => widget.settings;
  AppStrings get _s => AppStrings(_settings.isPersian);

  @override
  void initState() {
    super.initState();
    _initDesktopServices();
  }

  Future<void> _initDesktopServices() async {
    _deviceId = await widget.repository.getOrCreateDeviceId();
    _deviceName = widget.repository.getLocalDeviceName();
    _sharedKey = await widget.repository.getOrCreateDesktopSharedKey();
    _lanIps = await LocalNetworkGuard.getLocalPrivateIpv4Addresses();

    // 1. Local Encrypted TCP + LAN UDP Discovery Server (handles Wi-Fi LAN + USB loopback)
    _lanServer = DesktopLanServer(
      deviceId: _deviceId,
      deviceName: _deviceName,
      getSharedKey: () => _sharedKey,
      tcpPort: _settings.tcpPort,
    );
    _otpSub = _lanServer!.onOtpReceived.listen(_handleIncomingOtp);
    _logSub = _lanServer!.onStatusLog.listen(_appendLog);
    await _lanServer!.start(
      enableLanDiscovery: _settings.enableWifiLan,
      allowWifiLan: _settings.enableWifiLan,
    );

    // 2. USB ADB Reverse Bridge (optional, on by default)
    _usbBridge = UsbBridgeService(
      tcpPort: _lanServer!.boundPort,
      customAdbPath: _settings.customAdbPath,
    );
    _usbSub = _usbBridge!.onStatusChanged.listen((status) {
      if (mounted) setState(() => _usbStatus = status);
    });
    if (_settings.enableUsb) {
      await _usbBridge!.start();
    }

    // 3. Native Bluetooth RFCOMM Server (Windows Win32 / Linux BlueZ)
    _btBridge = DesktopBluetoothBridge(
      onEncryptedFrame: (frame) async {
        return _lanServer?.processExternalEncryptedFrame(
          frame,
          transport: TransportType.bluetooth,
        );
      },
    );
    _btSub = _btBridge!.onStatusChanged.listen((status) {
      if (mounted) setState(() => _btStatus = status);
    });
    if (_settings.enableBluetooth) {
      await _btBridge!.startServer();
    }

    // 4. System Tray & Native Notifications
    _trayController = DesktopTrayController(
      onCopyFromTray: (code) async => _copyCode(code, showSnack: false),
      onToggleAutoCopy: () async {
        widget.onSettingsChanged(
          _settings.copyWith(autoCopyOnDesktop: !_settings.autoCopyOnDesktop),
        );
        await _trayController?.rebuildMenu();
      },
      getAutoCopyEnabled: () => _settings.autoCopyOnDesktop,
      getMinimizeToTray: () => _settings.minimizeToTrayOnClose,
      onQuitRequested: () async {
        await _disposeServices();
        exit(0);
      },
    );
    await _trayController!.init();

    if (mounted) setState(() => _ready = true);
  }

  Future<void> _handleIncomingOtp(OtpMessage rawOtp) async {
    if (_deduplicator.isDuplicate(rawOtp.code)) return;

    var autoCopied = false;
    if (_settings.autoCopyOnDesktop) {
      await _clipboard.copyOtp(
        rawOtp.code,
        excludeFromHistory: _settings.excludeFromClipboardHistory,
        autoClearSeconds: _settings.clipboardClearSeconds,
      );
      autoCopied = true;
    }

    final otp = rawOtp.copyWith(autoCopied: autoCopied);

    if (mounted) {
      setState(() {
        _otps.insert(0, otp);
        if (_otps.length > 50) _otps.removeLast();
        if (_settings.showReadyToast) {
          _activeToastOtp = otp;
        }
      });
    }

    if (_settings.showReadyToast) {
      _toastTimer?.cancel();
      _toastTimer = Timer(
        const Duration(seconds: AppConstants.defaultToastDurationSeconds),
        () {
          if (mounted) setState(() => _activeToastOtp = null);
        },
      );
      await _trayController?.showOsReadyNotification(
        otp: otp,
        autoCopied: autoCopied,
        isPersian: _settings.isPersian,
      );
    }

    await _trayController?.updateRecentOtps(_otps);
  }

  Future<void> _copyCode(String code, {bool showSnack = true}) async {
    await _clipboard.copyOtp(
      code,
      excludeFromHistory: _settings.excludeFromClipboardHistory,
      autoClearSeconds: _settings.clipboardClearSeconds,
    );
    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_s.copiedFeedback}  $code'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _appendLog(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    if (mounted) {
      setState(() {
        _logs.insert(0, '[$ts] $msg');
        if (_logs.length > 40) _logs.removeLast();
      });
    }
  }

  Future<void> _refreshIps() async {
    final ips = await LocalNetworkGuard.getLocalPrivateIpv4Addresses();
    if (mounted) setState(() => _lanIps = ips);
  }

  Future<void> _rotateKey() async {
    final newKey = await widget.repository.rotateDesktopSharedKey();
    if (mounted) {
      setState(() => _sharedKey = newKey);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_s.t(
            'کلید امنیتی جدید ساخته شد. گوشی را دوباره با QR جفت کنید.',
            'New 256-bit key generated. Re-scan the QR code on your phone.',
          )),
        ),
      );
    }
  }

  PairingPayload _buildPairingPayload() {
    return PairingPayload(
      version: 1,
      deviceId: _deviceId,
      deviceName: _deviceName,
      sharedKeyBase64: _sharedKey,
      lanIps: _lanIps,
      tcpPort: _lanServer?.boundPort ?? _settings.tcpPort,
      bluetoothAddress: _btStatus.adapterAddress,
    );
  }

  Future<void> _disposeServices() async {
    if (_disposed) return;
    _disposed = true;
    _toastTimer?.cancel();
    await _otpSub?.cancel();
    await _logSub?.cancel();
    await _usbSub?.cancel();
    await _btSub?.cancel();
    _clipboard.dispose();
    await _trayController?.dispose();
    await _usbBridge?.dispose();
    await _btBridge?.dispose();
    await _lanServer?.dispose();
  }

  @override
  void dispose() {
    _disposeServices();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              NavigationRail(
                backgroundColor: AppTheme.slateSurface,
                selectedIndex: _selectedTab,
                onDestinationSelected: (i) => setState(() => _selectedTab = i),
                extended: MediaQuery.of(context).size.width >= 920,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.emerald.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.emerald.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: AppTheme.emeraldLight,
                        ),
                      ),
                    ],
                  ),
                ),
                destinations: [
                  NavigationRailDestination(
                    icon: const Icon(Icons.bolt_rounded),
                    label: Text(s.tabLive),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: Text(s.tabPair),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.hub_rounded),
                    label: Text(s.tabTransports),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.science_rounded),
                    label: Text(s.tabParserLab),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.tune_rounded),
                    label: Text(s.tabSettings),
                  ),
                ],
              ),
              const VerticalDivider(width: 1, color: AppTheme.slateBorder),
              Expanded(
                child: Column(
                  children: [
                    _buildTopBar(s),
                    const Divider(height: 1, color: AppTheme.slateBorder),
                    Expanded(child: _buildBody(s)),
                  ],
                ),
              ),
            ],
          ),

          // Sleek floating ready-to-paste toast badge
          if (_activeToastOtp != null)
            Positioned(
              bottom: 20,
              right: 20,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: OtpReadyToastCard(
                  key: ValueKey(_activeToastOtp!.id),
                  otp: _activeToastOtp!,
                  strings: s,
                  onCopy: () => _copyCode(_activeToastOtp!.code),
                  onDismiss: () => setState(() => _activeToastOtp = null),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(AppStrings s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: AppTheme.slateSurface,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'OtpBridge',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      s.zeroInternetBadge,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.emeraldLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Wrap(
            spacing: 8,
            children: [
              TransportPill(
                type: TransportType.wifiLan,
                active: _settings.enableWifiLan && (_lanServer?.isRunning ?? false),
                label: 'Wi-Fi',
                isDefault: _settings.defaultTransport == TransportType.wifiLan,
              ),
              TransportPill(
                type: TransportType.usb,
                active: _settings.enableUsb && _usbStatus.isConnected,
                label: 'USB',
                isDefault: _settings.defaultTransport == TransportType.usb,
              ),
              TransportPill(
                type: TransportType.bluetooth,
                active: _settings.enableBluetooth && _btStatus.running,
                label: 'BT',
                isDefault: _settings.defaultTransport == TransportType.bluetooth,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppStrings s) {
    switch (_selectedTab) {
      case 0:
        return _buildLiveFeedTab(s);
      case 1:
        return _buildPairingTab(s);
      case 2:
        return _buildTransportsTab(s);
      case 3:
        return OtpTesterView(strings: s, sensitivity: _settings.sensitivity);
      case 4:
      default:
        return _buildSettingsTab(s);
    }
  }

  Widget _buildLiveFeedTab(AppStrings s) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                s.tabLive,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              Chip(
                avatar: Icon(
                  _settings.autoCopyOnDesktop
                      ? Icons.check_circle_rounded
                      : Icons.touch_app_rounded,
                  size: 16,
                  color: _settings.autoCopyOnDesktop
                      ? AppTheme.emeraldLight
                      : AppTheme.sky,
                ),
                label: Text(
                  _settings.autoCopyOnDesktop
                      ? s.t('کپی خودکار فعال', 'Auto-Copy ON')
                      : s.t('کپی با یک کلیک', '1-Click Copy'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  _handleIncomingOtp(OtpMessage(
                    id: const Uuid().v4(),
                    code: '649281',
                    sender: 'بانک ملت (آزمایشی)',
                    source: OtpSource.manualTest,
                    timestampMs: DateTime.now().millisecondsSinceEpoch,
                    transport: TransportType.wifiLan,
                  ));
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(s.t('شبیه‌سازی دریافت کد', 'Simulate OTP')),
              ),
              if (_otps.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _otps.clear()),
                  child: Text(s.clearAll),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _otps.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mark_email_read_outlined,
                          size: 54,
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          s.noOtpsYet,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white60,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _otps.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final otp = _otps[index];
                      return Card(
                        child: InkWell(
                          onTap: () => _copyCode(otp.code),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color:
                                        AppTheme.emerald.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    otp.source == OtpSource.email
                                        ? Icons.email_outlined
                                        : Icons.sms_outlined,
                                    color: AppTheme.emeraldLight,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            otp.sender,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (otp.autoCopied)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.emerald
                                                    .withValues(alpha: 0.18),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                s.t('✓ کپی شد', '✓ Copied'),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.emeraldLight,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${otp.receivedAt.hour.toString().padLeft(2, '0')}:${otp.receivedAt.minute.toString().padLeft(2, '0')}:${otp.receivedAt.second.toString().padLeft(2, '0')} • ${otp.transport.name.toUpperCase()}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    otp.code,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 3.0,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                FilledButton.icon(
                                  onPressed: () => _copyCode(otp.code),
                                  icon: const Icon(Icons.copy_rounded, size: 16),
                                  label: Text(s.copyAction),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairingTab(AppStrings s) {
    final payload = _buildPairingPayload();
    final pairingUri = payload.toUriString();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: pairingUri,
                    version: QrVersions.auto,
                    size: 210,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.t('اتصال امن با اسکن QR Code', 'Secure Local QR Pairing'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.t(
                          'اپ OtpBridge را روی اندروید باز کرده و این QR را اسکن کنید. کلید رمزنگاری ۲۵۶ بیتی (AES-256-GCM) فقط به‌صورت مستقیم بین گوشی و کامپیوتر ردوبدل می‌شود و هیچ سروری در کار نیست.',
                          'Open OtpBridge on Android and scan this QR code. A 256-bit AES-GCM key is exchanged directly between your devices with zero cloud servers.',
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text('Device: $_deviceName')),
                          Chip(
                            label: Text(
                              'LAN IP: ${_lanIps.isEmpty ? "None" : _lanIps.join(", ")}',
                            ),
                          ),
                          Chip(label: Text('Port: ${payload.tcpPort}')),
                          if (_btStatus.adapterAddress != null)
                            Chip(label: Text('BT: ${_btStatus.adapterAddress}')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: pairingUri));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(s.t(
                                    'کد اتصال دستی کپی شد',
                                    'Manual pairing code copied',
                                  )),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: Text(
                              s.t('کپی کد اتصال دستی', 'Copy Manual Pairing Code'),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _refreshIps,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: Text(s.t('بروزرسانی IP شبکه', 'Refresh LAN IPs')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _rotateKey,
                            icon: const Icon(Icons.key_rounded, size: 16),
                            label: Text(
                              s.t('تولید کلید جدید (لغو اتصال‌های قبلی)',
                                  'Rotate Key (Revoke Old Phones)'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransportsTab(AppStrings s) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.wifi_rounded, color: AppTheme.emeraldLight),
            title: Text(s.wifiLan),
            subtitle: Text(
              _lanIps.isEmpty
                  ? s.t('شبکه وای‌فای محلی یافت نشد', 'No private LAN IPv4 detected')
                  : 'LAN: ${_lanIps.join(", ")} : ${_lanServer?.boundPort ?? _settings.tcpPort}',
            ),
            value: _settings.enableWifiLan,
            onChanged: (v) async {
              widget.onSettingsChanged(_settings.copyWith(enableWifiLan: v));
              await _lanServer?.stop();
              await _lanServer?.start(
                enableLanDiscovery: v,
                allowWifiLan: v,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.usb_rounded, color: AppTheme.sky),
                title: Text(s.usbCable),
                subtitle: Text(_usbStatus.message),
                value: _settings.enableUsb,
                onChanged: (v) async {
                  widget.onSettingsChanged(_settings.copyWith(enableUsb: v));
                  if (v) {
                    await _usbBridge?.start();
                  } else {
                    await _usbBridge?.stop();
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t(
                          'برای انتقال از طریق کابل USB (حتی با VPN روشن روی PC)، USB Debugging را در گوشی فعال کنید و کابل را وصل نمایید.',
                          'For USB mode (works even with Desktop VPN ON), enable USB Debugging on Android and plug in your USB cable.',
                        ),
                        style: const TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          _usbBridge?.refreshNow(forceRebind: true),
                      child: Text(s.t('بررسی مجدد', 'Re-scan')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.bluetooth_rounded, color: AppTheme.amber),
            title: Text(s.bluetooth),
            subtitle: Text(
              _btStatus.message.isEmpty
                  ? (_btStatus.running
                      ? 'RFCOMM UUID: ${AppConstants.bluetoothServiceUuid}'
                      : s.t('غیرفعال / آداپتور بلوتوث یافت نشد',
                          'Inactive / Bluetooth adapter unavailable'))
                  : _btStatus.message,
            ),
            value: _settings.enableBluetooth,
            onChanged: (v) async {
              widget.onSettingsChanged(_settings.copyWith(enableBluetooth: v));
              if (v) {
                await _btBridge?.startServer();
              } else {
                await _btBridge?.stopServer();
              }
            },
          ),
        ),
        const SizedBox(height: 18),
        Text(
          s.t('گزارش اتصال‌های محلی (فقط در حافظه موقت)', 'Local Transport Log (RAM only)'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _logs.isEmpty
                ? const Text('—', style: TextStyle(color: Colors.white54))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _logs
                        .take(12)
                        .map((l) => Text(
                              l,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab(AppStrings s) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(s.autoCopyTitle),
                subtitle: Text(s.autoCopyDesc),
                value: _settings.autoCopyOnDesktop,
                onChanged: (v) {
                  widget.onSettingsChanged(
                    _settings.copyWith(autoCopyOnDesktop: v),
                  );
                  _trayController?.rebuildMenu();
                },
              ),
              const Divider(height: 1, color: AppTheme.slateBorder),
              SwitchListTile(
                title: Text(s.showReadyToastTitle),
                value: _settings.showReadyToast,
                onChanged: (v) => widget.onSettingsChanged(
                  _settings.copyWith(showReadyToast: v),
                ),
              ),
              const Divider(height: 1, color: AppTheme.slateBorder),
              if (Platform.isWindows) ...[
                SwitchListTile(
                  title: Text(s.excludeClipboardHistoryTitle),
                  value: _settings.excludeFromClipboardHistory,
                  onChanged: (v) => widget.onSettingsChanged(
                    _settings.copyWith(excludeFromClipboardHistory: v),
                  ),
                ),
                const Divider(height: 1, color: AppTheme.slateBorder),
              ],
              ListTile(
                title: Text(s.autoClearClipboardTitle),
                subtitle: Text(
                  _settings.clipboardClearSeconds == 0
                      ? s.t('غیرفعال', 'Disabled')
                      : s.t('${_settings.clipboardClearSeconds} ثانیه پس از کپی',
                          '${_settings.clipboardClearSeconds} seconds after copy'),
                ),
                trailing: DropdownButton<int>(
                  value: _settings.clipboardClearSeconds,
                  items: [0, 30, 60, 120]
                      .map((sec) => DropdownMenuItem(
                            value: sec,
                            child: Text(sec == 0
                                ? s.t('هرگز', 'Never')
                                : '${sec}s'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      widget.onSettingsChanged(
                        _settings.copyWith(clipboardClearSeconds: v),
                      );
                    }
                  },
                ),
              ),
              const Divider(height: 1, color: AppTheme.slateBorder),
              SwitchListTile(
                title: Text(s.minimizeToTrayTitle),
                value: _settings.minimizeToTrayOnClose,
                onChanged: (v) => widget.onSettingsChanged(
                  _settings.copyWith(minimizeToTrayOnClose: v),
                ),
              ),
              const Divider(height: 1, color: AppTheme.slateBorder),
              ListTile(
                title: Text(s.languageTitle),
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'fa', label: Text('فارسی')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {_settings.localeCode},
                  onSelectionChanged: (set) {
                    widget.onSettingsChanged(
                      _settings.copyWith(localeCode: set.first),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
