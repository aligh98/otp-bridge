import 'package:material_ui/material_ui.dart';

import '../../core/models/otp_message.dart';
import '../theme/app_theme.dart';

class TransportPill extends StatelessWidget {
  const TransportPill({
    super.key,
    required this.type,
    required this.active,
    required this.label,
    this.isDefault = false,
  });

  final TransportType type;
  final bool active;
  final String label;
  final bool isDefault;

  IconData get _icon {
    switch (type) {
      case TransportType.wifiLan:
        return Icons.wifi_rounded;
      case TransportType.usb:
        return Icons.usb_rounded;
      case TransportType.bluetooth:
        return Icons.bluetooth_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.emerald : Colors.white38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? AppTheme.emerald.withValues(alpha: 0.14)
            : AppTheme.slateSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? AppTheme.emerald.withValues(alpha: 0.55)
              : AppTheme.slateBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : Colors.white54,
            ),
          ),
          if (isDefault) ...[
            const SizedBox(width: 5),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppTheme.emeraldLight,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
