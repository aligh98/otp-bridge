/// Bilingual (Persian RTL + English LTR) localization strings.
class AppStrings {
  const AppStrings(this.isPersian);

  final bool isPersian;

  String t(String fa, String en) => isPersian ? fa : en;

  String get appTitle => 'OtpBridge';
  String get subtitle => t(
        'انتقال امن و آفلاین کدهای تایید به کامپیوتر',
        'Secure, 100% offline OTP bridge to your PC',
      );
  String get zeroInternetBadge => t(
        '۱۰۰٪ آفلاین • بدون سرور • رمزنگاری AES-256',
        '100% Offline • Zero Cloud • AES-256-GCM',
      );

  // Navigation tabs
  String get tabLive => t('کدهای زنده', 'Live OTPs');
  String get tabPair => t('اتصال', 'Pairing');
  String get tabTransports => t('مسیر انتقال', 'Transports');
  String get tabParserLab => t('آزمایش تشخیص', 'Parser Lab');
  String get tabSettings => t('تنظیمات', 'Settings');
  String get tabGuide => t('راهنمای گوشی', 'Setup Guide');

  // Toast / Auto-Copy
  String get copiedReadyTitle => t('کپی شد — آماده پیست (Ctrl+V)', 'Copied — Ready to paste (Ctrl+V)');
  String get clickToCopyTitle => t('کد تایید جدید — کلیک برای کپی', 'New OTP — Click to copy');
  String get copyAction => t('کپی', 'Copy');
  String get copiedFeedback => t('کپی شد!', 'Copied!');
  String get clearAll => t('پاک کردن لیست', 'Clear list');
  String get noOtpsYet => t(
        'هنوز کدی دریافت نشده است.\nبه محض دریافت پیامک یا ایمیل حاوی کد تایید روی گوشی، این‌جا ظاهر شده و خودکار کپی می‌شود.',
        'No OTPs received yet.\nAs soon as an OTP SMS or email arrives on your phone, it will appear here and auto-copy.',
      );

  // Transports
  String get wifiLan => t('وای‌فای محلی (پیش‌فرض)', 'Local Wi-Fi (Default)');
  String get usbCable => t('کابل USB (ضد VPN)', 'USB Cable (VPN-Proof)');
  String get bluetooth => t('بلوتوث مستقیم', 'Direct Bluetooth');
  String get defaultTransportLabel => t('مسیر پیش‌فرض انتقال', 'Default Transport');
  String get autoFallbackLabel => t(
        'جایگزینی خودکار در صورت قطعی مسیر اصلی',
        'Auto-fallback to other enabled transports',
      );

  // Settings
  String get autoCopyTitle => t('کپی خودکار در کلیپ‌بورد', 'Auto-copy to clipboard');
  String get autoCopyDesc => t(
        'به محض رسیدن کد، خودکار کپی شود و فقط یک اعلان زیبا نمایش داده شود',
        'Automatically copy incoming codes and show a sleek ready-to-paste badge',
      );
  String get showReadyToastTitle => t('نمایش اعلان زیبای «آماده پیست»', 'Show sleek "Ready to Paste" toast');
  String get excludeClipboardHistoryTitle => t(
        'عدم ذخیره در تاریخچه کلیپ‌بورد (Win+V)',
        'Exclude OTP from Windows Clipboard History (Win+V)',
      );
  String get autoClearClipboardTitle => t('پاک شدن خودکار کلیپ‌بورد', 'Auto-clear clipboard');
  String get minimizeToTrayTitle => t('مینیمایز در کنار ساعت (System Tray)', 'Minimize to System Tray on close');
  String get smsCaptureTitle => t('دریافت مستقیم SMS (هیبرید)', 'Direct SMS Capture (Hybrid)');
  String get notificationCaptureTitle => t(
        'خواندن نوتیفیکیشن‌ها (ایمیل، پیامک، پیام‌رسان‌ها)',
        'Notification Listener (Email, SMS, RCS, Messengers)',
      );
  String get languageTitle => t('زبان برنامه', 'App Language');
  String get sensitivityTitle => t('حساسیت موتور تشخیص OTP', 'OTP Detection Sensitivity');
}
