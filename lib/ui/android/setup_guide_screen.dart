import 'package:material_ui/material_ui.dart';

import '../../core/l10n/app_strings.dart';
import '../../platform/android_bridge.dart';
import '../../platform/oem_guide_data.dart';
import '../theme/app_theme.dart';

/// Optional, device-aware interactive setup guide tailored to the user's exact
/// Android version (Android 13+ Restricted Settings) and hardware brand
/// (Xiaomi/HyperOS, Samsung/OneUI, Huawei/Honor, Oppo/Realme, Stock Android).
class SetupGuideScreen extends StatelessWidget {
  const SetupGuideScreen({
    super.key,
    required this.strings,
    required this.deviceStatus,
    required this.onRefreshStatus,
  });

  final AppStrings strings;
  final AndroidDeviceStatus deviceStatus;
  final VoidCallback onRefreshStatus;

  Future<void> _handleAction(String? key) async {
    switch (key) {
      case 'openAppInfo':
        await AndroidNativeBridge.openAppInfo();
        break;
      case 'openNotificationListener':
        await AndroidNativeBridge.openNotificationListenerSettings();
        break;
      case 'requestSmsPermission':
        await AndroidNativeBridge.requestSmsPermission();
        break;
      case 'openBatteryOptimization':
        await AndroidNativeBridge.openBatteryOptimizationSettings();
        break;
      case 'openOemAutostart':
        await AndroidNativeBridge.openOemAutostartSettings();
        break;
    }
    onRefreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final guide = OemGuideBuilder.buildForDevice(
      manufacturer: deviceStatus.manufacturer,
      brand: deviceStatus.brand,
      sdkInt: deviceStatus.sdkInt,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.smartphone_rounded,
                        color: AppTheme.emeraldLight),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.isPersian ? guide.oemLabelFa : guide.oemLabelEn,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onRefreshStatus,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  s.t(
                    'همه مراحل زیر اختیاری هستند، اما انجام آن‌ها باعث می‌شود کدهای SMS و ایمیل حتی در حالت قفل گوشی و بدون قطعی ارسال شوند.',
                    'All steps below are optional, but completing them ensures instant SMS & email OTP forwarding even when your phone screen is off.',
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statusChip(
                      s.t('نوتیفیکیشن', 'Notification'),
                      deviceStatus.notificationListenerEnabled,
                    ),
                    if (deviceStatus.smsFlavorSupported)
                      _statusChip(
                        s.t('پیامک مستقیم', 'Direct SMS'),
                        deviceStatus.smsPermissionGranted,
                      ),
                    _statusChip(
                      s.t('باتری آزاد', 'Battery'),
                      deviceStatus.batteryOptimizationIgnored,
                    ),
                    _statusChip(
                      s.t('بلوتوث', 'Bluetooth'),
                      deviceStatus.bluetoothPermissionGranted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final step in guide.steps) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.isPersian ? step.titleFa : step.titleEn,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (step.isOptional)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.slateSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            s.t('اختیاری', 'Optional'),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.isPersian ? step.descriptionFa : step.descriptionEn,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      height: 1.55,
                    ),
                  ),
                  if (step.actionKey != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _handleAction(step.actionKey),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(
                        s.isPersian
                            ? (step.actionLabelFa ?? '')
                            : (step.actionLabelEn ?? ''),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _statusChip(String label, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (ok ? AppTheme.emerald : AppTheme.amber).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (ok ? AppTheme.emerald : AppTheme.amber).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 14,
            color: ok ? AppTheme.emeraldLight : AppTheme.amber,
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
