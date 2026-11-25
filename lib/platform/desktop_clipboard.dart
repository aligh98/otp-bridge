import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/constants.dart';

/// Privacy-aware Desktop clipboard controller.
///
/// - Copies OTP instantly on arrival (when Auto-Copy is enabled)
/// - On Windows, optionally uses native Win32 clipboard privacy flags so OTPs
///   are NOT saved into `Win+V` Clipboard History or Cloud Sync
/// - Optionally auto-clears the clipboard after N seconds ONLY if the clipboard
///   still contains the OTP (never overwrites something else you copied later!)
class DesktopClipboardService {
  static const MethodChannel _channel =
      MethodChannel(AppConstants.desktopClipboardChannel);

  Timer? _clearTimer;
  String? _lastCopiedOtp;

  Future<void> copyOtp(
    String code, {
    required bool excludeFromHistory,
    required int autoClearSeconds,
  }) async {
    _clearTimer?.cancel();
    _lastCopiedOtp = code;

    var copiedPrivately = false;
    if (Platform.isWindows && excludeFromHistory) {
      try {
        copiedPrivately = (await _channel.invokeMethod<bool>(
              'setPrivateClipboard',
              {'text': code},
            )) ??
            false;
      } catch (_) {
        copiedPrivately = false;
      }
    }

    if (!copiedPrivately) {
      await Clipboard.setData(ClipboardData(text: code));
    }

    if (autoClearSeconds > 0) {
      _clearTimer = Timer(Duration(seconds: autoClearSeconds), () async {
        try {
          final current = await Clipboard.getData(Clipboard.kTextPlain);
          if (current?.text == _lastCopiedOtp) {
            await Clipboard.setData(const ClipboardData(text: ''));
          }
        } catch (_) {}
      });
    }
  }

  void dispose() {
    _clearTimer?.cancel();
  }
}
