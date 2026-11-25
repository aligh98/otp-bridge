import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/otp_message.dart';
import '../../core/models/paired_device.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/transport/lan_client.dart';
import '../../platform/android_bridge.dart';
import '../theme/app_theme.dart';
import '../widgets/otp_tester_view.dart';
import '../widgets/transport_badge.dart';
import 'qr_pair_screen.dart';
import 'setup_guide_screen.dart';

/// Main Android companion app UI.
///
/// The actual OTP capture & encrypted transmission run natively in Kotlin
/// (`OtpNotificationListenerService` + `SmsBroadcastReceiver` + `NativeTransportSender`),
/// so OTP forwarding keeps working reliably even when this Flutter UI is closed.
class AndroidHomeScreen extends StatefulWidget {
  const AndroidHomeScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.onSettingsChanged,
  });

  final SettingsRepository repository;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<AndroidHomeScreen> createState() => _AndroidHomeScreenState();
}

class _AndroidHomeScreenState extends State<AndroidHomeScreen>
    with WidgetsBindingObserver {
  int _tabIndex = 0;
  PairedDevice? _pairedDesktop;
  AndroidDeviceStatus _deviceStatus = AndroidDeviceStatus.fromMap(null);
  final List<OtpMessage> _recentOtps = [];
  StreamSubscription<OtpMessage>? _otpSub;
  bool _testingConnection = false;

  AppSettings get _settings => widget.settings;
  AppStrings get _s => AppStrings(_settings.isPersian);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAndroid();
  }

  Future<void> _initAndroid() async {
    _pairedDesktop = widget.repository.loadPairedDesktop();
    await _refreshDeviceStatus();
    await _syncNative();

    final recent = await AndroidNativeBridge.fetchRecentNativeOtps();
    if (mounted) {
      setState(() {
        _recentOtps
          ..clear()
          ..addAll(recent);
      });
    }

    _otpSub = AndroidNativeBridge.liveOtpStream.listen((otp) {
      if (!mounted) return;
      setState(() {
        _recentOtps.insert(0, otp);
        if (_recentOtps.length > 30) _recentOtps.removeLast();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDeviceStatus();
    }
  }

  Future<void> _refreshDeviceStatus() async {
    final status = await AndroidNativeBridge.getDeviceStatus();
    if (mounted) setState(() => _deviceStatus = status);
  }

  Future<void> _syncNative() async {
    await AndroidNativeBridge.syncNativeConfig(
      desktop: _pairedDesktop,
      settings: _settings,
    );
  }

  void _updateSettings(AppSettings updated) {
    widget.onSettingsChanged(updated);
    AndroidNativeBridge.syncNativeConfig(
      desktop: _pairedDesktop,
      settings: updated,
    );
  }

  Future<void> _openQrPairing() async {
    final paired = await Navigator.of(context).push<PairedDevice>(
      MaterialPageRoute(builder: (_) => QrPairScreen(strings: _s)),
    );
    if (paired != null) {
      await widget.repository.savePairedDesktop(paired);
      if (mounted) setState(() => _pairedDesktop = paired);
      await _syncNative();
    }
  }

  Future<void> _discoverUpdatedDesktopIp() async {
    if (_pairedDesktop == null) return;
    final client = LocalTransportClient();
    final found = await client.discoverOnLan(
      targetDeviceId: _pairedDesktop!.deviceId,
    );
    if (found.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_s.t(
            'کامپیوتر روی شبکه وای‌فای محلی پیدا نشد.',
            'Desktop not found on current local Wi-Fi.',
          )),
        ),
      );
      return;
    }

    final first = found.first;
    final updatedIps = <String>[
      first.ip,
      ..._pairedDesktop!.lanIps.where((ip) => ip != first.ip),
    ];
    final updated = _pairedDesktop!.copyWith(
      deviceName: first.deviceName,
      lanIps: updatedIps,
      tcpPort: first.port,
    );
    await widget.repository.savePairedDesktop(updated);
    if (mounted) setState(() => _pairedDesktop = updated);
    await _syncNative();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_s.t(
            'آدرس جدید کامپیوتر پیدا شد: ${first.ip}',
            'Found Desktop on LAN: ${first.ip}',
          )),
        ),
      );
    }
  }

  Future<void> _pickBluetoothPeer() async {
    if (_pairedDesktop == null) return;
    await AndroidNativeBridge.requestBluetoothPermission();
    final devices = await AndroidNativeBridge.getBondedBluetoothDevices();
    if (!mounted) return;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_s.t(
            'ابتدا کامپیوتر را در تنظیمات بلوتوث اندروید جفت (Pair) کنید.',
            'Please pair your PC in Android Bluetooth Settings first.',
          )),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<BondedBluetoothDevice>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              _s.t('انتخاب کامپیوتر بلوتوثی', 'Select Paired Bluetooth PC'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          for (final d in devices)
            ListTile(
              leading: const Icon(Icons.bluetooth_rounded),
              title: Text(d.name),
              subtitle: Text(d.address),
              onTap: () => Navigator.of(ctx).pop(d),
            ),
        ],
      ),
    );

    if (selected != null) {
      final updated = _pairedDesktop!.copyWith(
        bluetoothAddress: selected.address,
        bluetoothName: selected.name,
      );
      await widget.repository.savePairedDesktop(updated);
      if (mounted) setState(() => _pairedDesktop = updated);
      await _syncNative();
    }
  }

  Future<void> _sendTestOtp() async {
    if (_pairedDesktop == null) return;
    setState(() => _testingConnection = true);
    final res = await AndroidNativeBridge.sendTestOtpViaNative(
      code: '591028',
      sender: 'OtpBridge Test',
    );
    if (mounted) {
      setState(() => _testingConnection = false);
      final ok = res['ok'] == true;
      final via = res['transport'] ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? _s.t('کد آزمایشی با موفقیت از طریق $via ارسال شد!',
                    'Test OTP delivered via $via!')
                : _s.t('ارسال ناموفق بود (${res['error'] ?? "عدم اتصال"})',
                    'Delivery failed (${res['error'] ?? "unreachable"})'),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _otpSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.slateSurface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OtpBridge', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              s.zeroInternetBadge,
              style: const TextStyle(fontSize: 11, color: AppTheme.emeraldLight),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildOverviewTab(s),
          SetupGuideScreen(
            strings: s,
            deviceStatus: _deviceStatus,
            onRefreshStatus: _refreshDeviceStatus,
          ),
          OtpTesterView(strings: s, sensitivity: _settings.sensitivity),
          _buildSettingsTab(s),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.bolt_rounded),
            label: s.tabLive,
          ),
          NavigationDestination(
            icon: const Icon(Icons.checklist_rounded),
            label: s.tabGuide,
          ),
          NavigationDestination(
            icon: const Icon(Icons.science_rounded),
            label: s.tabParserLab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.tune_rounded),
            label: s.tabSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(AppStrings s) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Paired Desktop Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _pairedDesktop == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        s.t('هنوز به کامپیوتر متصل نشده‌اید',
                            'Not Paired with Desktop Yet'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.t(
                          'برنامه OtpBridge را روی ویندوز یا لینوکس باز کرده و QR Code را اسکن کنید.',
                          'Open OtpBridge on Windows or Linux and scan its pairing QR code.',
                        ),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _openQrPairing,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: Text(s.t('اسکن QR کامپیوتر', 'Scan Desktop QR')),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.computer_rounded,
                              color: AppTheme.emeraldLight),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _pairedDesktop!.deviceName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'LAN: ${_pairedDesktop!.lanIps.join(", ")} • BT: ${_pairedDesktop!.bluetoothName ?? _pairedDesktop!.bluetoothAddress ?? "—"}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _openQrPairing,
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            tooltip: s.t('اتصال مجدد', 'Re-pair'),
                          ),
                          IconButton(
                            onPressed: () async {
                              await widget.repository.savePairedDesktop(null);
                              if (mounted) {
                                setState(() => _pairedDesktop = null);
                              }
                              await _syncNative();
                            },
                            icon: const Icon(Icons.link_off_rounded,
                                color: AppTheme.rose),
                            tooltip: s.t('قطع اتصال', 'Unpair'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TransportPill(
                            type: TransportType.wifiLan,
                            active: _settings.enableWifiLan,
                            label: 'Wi-Fi',
                            isDefault:
                                _settings.defaultTransport == TransportType.wifiLan,
                          ),
                          TransportPill(
                            type: TransportType.usb,
                            active: _settings.enableUsb,
                            label: 'USB',
                            isDefault:
                                _settings.defaultTransport == TransportType.usb,
                          ),
                          TransportPill(
                            type: TransportType.bluetooth,
                            active: _settings.enableBluetooth &&
                                (_pairedDesktop!.bluetoothAddress?.isNotEmpty ??
                                    false),
                            label: 'BT',
                            isDefault: _settings.defaultTransport ==
                                TransportType.bluetooth,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _testingConnection ? null : _sendTestOtp,
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: Text(
                              _testingConnection
                                  ? '...'
                                  : s.t('ارسال کد آزمایشی', 'Send Test OTP'),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _discoverUpdatedDesktopIp,
                            icon: const Icon(Icons.wifi_find_rounded, size: 16),
                            label: Text(s.t('یافتن IP جدید', 'Find LAN IP')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pickBluetoothPeer,
                            icon: const Icon(Icons.bluetooth_searching_rounded,
                                size: 16),
                            label: Text(s.t('تنظیم بلوتوث', 'Link Bluetooth')),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        if (!_deviceStatus.notificationListenerEnabled)
          Card(
            color: AppTheme.amber.withValues(alpha: 0.14),
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: AppTheme.amber),
              title: Text(
                s.t('راهنمای فعال‌سازی اختیاری برای این گوشی آماده است',
                    'Device-specific optional setup guide available'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              trailing: TextButton(
                onPressed: () => setState(() => _tabIndex = 1),
                child: Text(s.tabGuide),
              ),
            ),
          ),
        const SizedBox(height: 14),
        Text(
          s.t('آخرین کدهای تشخیص‌داده‌شده', 'Recently Forwarded OTPs'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 8),
        if (_recentOtps.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                s.t('هنوز کدی ارسال نشده است.', 'No OTPs forwarded yet.'),
                style: const TextStyle(color: Colors.white60),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          for (final otp in _recentOtps)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  otp.source == OtpSource.email
                      ? Icons.email_outlined
                      : Icons.sms_outlined,
                  color: AppTheme.emeraldLight,
                ),
                title: Text(otp.sender,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(otp.transport.name.toUpperCase()),
                trailing: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    otp.code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildSettingsTab(AppStrings s) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(s.defaultTransportLabel),
                trailing: DropdownButton<TransportType>(
                  value: _settings.defaultTransport,
                  items: [
                    DropdownMenuItem(
                      value: TransportType.wifiLan,
                      child: Text(s.t('وای‌فای محلی', 'Local Wi-Fi')),
                    ),
                    DropdownMenuItem(
                      value: TransportType.usb,
                      child: Text(s.t('کابل USB', 'USB Cable')),
                    ),
                    DropdownMenuItem(
                      value: TransportType.bluetooth,
                      child: Text(s.t('بلوتوث', 'Bluetooth')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      _updateSettings(_settings.copyWith(defaultTransport: v));
                    }
                  },
                ),
              ),
              const Divider(height: 1, color: AppTheme.slateBorder),
              SwitchListTile(
                title: Text(s.wifiLan),
                value: _settings.enableWifiLan,
                onChanged: (v) =>
                    _updateSettings(_settings.copyWith(enableWifiLan: v)),
              ),
              SwitchListTile(
                title: Text(s.usbCable),
                value: _settings.enableUsb,
                onChanged: (v) =>
                    _updateSettings(_settings.copyWith(enableUsb: v)),
              ),
              SwitchListTile(
                title: Text(s.bluetooth),
                value: _settings.enableBluetooth,
                onChanged: (v) =>
                    _updateSettings(_settings.copyWith(enableBluetooth: v)),
              ),
              SwitchListTile(
                title: Text(s.autoFallbackLabel),
                value: _settings.autoFallbackTransports,
                onChanged: (v) => _updateSettings(
                    _settings.copyWith(autoFallbackTransports: v)),
              ),
              const Divider(height: 1, color: AppTheme.slateBorder),
              if (_deviceStatus.smsFlavorSupported)
                SwitchListTile(
                  title: Text(s.smsCaptureTitle),
                  value: _settings.enableSmsCapture,
                  onChanged: (v) =>
                      _updateSettings(_settings.copyWith(enableSmsCapture: v)),
                ),
              SwitchListTile(
                title: Text(s.notificationCaptureTitle),
                value: _settings.enableNotificationCapture,
                onChanged: (v) => _updateSettings(
                    _settings.copyWith(enableNotificationCapture: v)),
              ),
              const Divider(height: 1, color: AppTheme.slateBorder),
              ListTile(
                title: Text(s.sensitivityTitle),
                trailing: DropdownButton<ParserSensitivity>(
                  value: _settings.sensitivity,
                  items: [
                    DropdownMenuItem(
                      value: ParserSensitivity.strict,
                      child: Text(s.t('سخت‌گیرانه', 'Strict')),
                    ),
                    DropdownMenuItem(
                      value: ParserSensitivity.balanced,
                      child: Text(s.t('متعادل (پیشنهادی)', 'Balanced')),
                    ),
                    DropdownMenuItem(
                      value: ParserSensitivity.relaxed,
                      child: Text(s.t('حداکثری', 'Relaxed')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      _updateSettings(_settings.copyWith(sensitivity: v));
                    }
                  },
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
                    _updateSettings(_settings.copyWith(localeCode: set.first));
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
