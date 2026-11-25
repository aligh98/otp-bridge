import 'dart:io';

import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/constants.dart';
import '../core/models/otp_message.dart';

/// Manages Desktop System Tray icon/menu, window hide/show, and native OS
/// "✓ Copied — Ready to Paste" notifications on Windows & Linux.
class DesktopTrayController with TrayListener, WindowListener {
  DesktopTrayController({
    required this.onCopyFromTray,
    required this.onToggleAutoCopy,
    required this.getAutoCopyEnabled,
    required this.getMinimizeToTray,
    required this.onQuitRequested,
  });

  final Future<void> Function(String code) onCopyFromTray;
  final Future<void> Function() onToggleAutoCopy;
  final bool Function() getAutoCopyEnabled;
  final bool Function() getMinimizeToTray;
  final Future<void> Function() onQuitRequested;

  bool _initialized = false;
  List<OtpMessage> _recentOtps = const [];

  Future<void> init() async {
    if (_initialized || !(Platform.isWindows || Platform.isLinux)) return;
    _initialized = true;

    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
    } catch (_) {}

    try {
      await localNotifier.setup(
        appName: AppConstants.appName,
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    } catch (_) {}

    try {
      trayManager.addListener(this);
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/icons/tray_icon.ico'
            : 'assets/icons/tray_icon.png',
      );
      await trayManager.setToolTip('OtpBridge — Offline Secure OTP');
      await rebuildMenu();
    } catch (_) {
      // Headless / minimal Linux environments without StatusNotifierWatcher.
    }
  }

  Future<void> updateRecentOtps(List<OtpMessage> otps) async {
    _recentOtps = otps.take(4).toList();
    await rebuildMenu();
  }

  Future<void> rebuildMenu() async {
    if (!_initialized) return;
    try {
      final items = <MenuItem>[
        MenuItem(key: 'show', label: 'Open OtpBridge'),
        MenuItem.separator(),
        if (_recentOtps.isEmpty)
          MenuItem(key: 'none', label: 'No recent OTPs', disabled: true)
        else
          for (final otp in _recentOtps)
            MenuItem(
              key: 'copy:${otp.code}',
              label: 'Copy ${otp.code}  (${otp.sender})',
            ),
        MenuItem.separator(),
        MenuItem.checkbox(
          key: 'toggle_autocopy',
          label: 'Auto-Copy to Clipboard',
          checked: getAutoCopyEnabled(),
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit OtpBridge'),
      ];
      await trayManager.setContextMenu(Menu(items: items));
    } catch (_) {}
  }

  /// Displays a sleek native OS notification confirming the OTP is ready to paste
  /// (works even when the main window is minimized to the System Tray!).
  Future<void> showOsReadyNotification({
    required OtpMessage otp,
    required bool autoCopied,
    required bool isPersian,
  }) async {
    try {
      final title = autoCopied
          ? (isPersian
              ? '✓ کپی شد — آماده پیست (${otp.sender})'
              : '✓ Copied — Ready to paste (${otp.sender})')
          : (isPersian
              ? 'کد تایید جدید از ${otp.sender}'
              : 'New OTP from ${otp.sender}');
      final body = autoCopied
          ? (isPersian
              ? 'کد ${otp.code} در کلیپ‌بورد کپی شد. Ctrl+V بزنید.'
              : 'Code ${otp.code} copied to clipboard. Press Ctrl+V.')
          : (isPersian
              ? 'کد: ${otp.code} (برای کپی کلیک کنید)'
              : 'Code: ${otp.code} (click to copy)');

      final notification = LocalNotification(
        identifier: 'otp_${otp.id}',
        title: title,
        body: body,
      );
      notification.onClick = () {
        onCopyFromTray(otp.code);
      };
      await notification.show();
    } catch (_) {}
  }

  Future<void> showMainWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    showMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    if (key == 'show') {
      showMainWindow();
    } else if (key == 'toggle_autocopy') {
      onToggleAutoCopy();
    } else if (key == 'quit') {
      onQuitRequested();
    } else if (key.startsWith('copy:')) {
      final code = key.substring(5);
      onCopyFromTray(code);
    }
  }

  @override
  void onWindowClose() async {
    if (getMinimizeToTray()) {
      await windowManager.hide();
    } else {
      await onQuitRequested();
    }
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
  }
}
