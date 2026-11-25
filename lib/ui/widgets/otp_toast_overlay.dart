import 'package:material_ui/material_ui.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/otp_message.dart';
import '../theme/app_theme.dart';

/// Sleek animated floating ready-to-paste banner/toast shown whenever an OTP
/// arrives on Desktop. Clearly indicates "✓ Copied — Ready to paste (Ctrl+V)"
/// with a green checkmark, sender badge, monospace code, and 1-click Copy.
class OtpReadyToastCard extends StatelessWidget {
  const OtpReadyToastCard({
    super.key,
    required this.otp,
    required this.strings,
    required this.onCopy,
    required this.onDismiss,
  });

  final OtpMessage otp;
  final AppStrings strings;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: otp.autoCopied
                  ? AppTheme.emerald.withValues(alpha: 0.75)
                  : AppTheme.sky.withValues(alpha: 0.75),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (otp.autoCopied ? AppTheme.emerald : AppTheme.sky)
                    .withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // Animated check circle
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (otp.autoCopied ? AppTheme.emerald : AppTheme.sky)
                      .withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  otp.autoCopied
                      ? Icons.check_circle_rounded
                      : Icons.content_copy_rounded,
                  color: otp.autoCopied ? AppTheme.emeraldLight : AppTheme.sky,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            otp.autoCopied
                                ? strings.copiedReadyTitle
                                : strings.clickToCopyTitle,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: otp.autoCopied
                                  ? AppTheme.emeraldLight
                                  : AppTheme.sky,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            otp.code,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3.0,
                              fontFamily: 'monospace',
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.slateCard,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              otp.sender,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onCopy,
                tooltip: strings.copyAction,
                icon: const Icon(Icons.copy_rounded, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.emerald.withValues(alpha: 0.16),
                  foregroundColor: AppTheme.emeraldLight,
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 16),
                color: Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
