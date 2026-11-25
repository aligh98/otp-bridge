import '../constants.dart';

/// Time-windowed deduplicator so hybrid Android capture (SMS BroadcastReceiver +
/// NotificationListenerService) never forwards the same OTP twice to Desktop.
class OtpDeduplicator {
  OtpDeduplicator({
    this.windowSeconds = AppConstants.dedupWindowSeconds,
  });

  final int windowSeconds;
  final Map<String, int> _recentCodes = {};

  /// Returns true if [code] was already seen within [windowSeconds].
  /// Otherwise records it and returns false.
  bool isDuplicate(String code, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - (windowSeconds * 1000);
    _recentCodes.removeWhere((_, ts) => ts < cutoff);

    final key = code.trim().toUpperCase();
    final lastSeen = _recentCodes[key];
    if (lastSeen != null && (now - lastSeen) <= windowSeconds * 1000) {
      return true;
    }
    _recentCodes[key] = now;
    return false;
  }

  void clear() => _recentCodes.clear();
}
