/// Device-aware, optional setup & troubleshooting guides for Android 13+
/// Restricted Settings and OEM aggressive background battery managers.
class OemGuideStep {
  const OemGuideStep({
    required this.titleFa,
    required this.titleEn,
    required this.descriptionFa,
    required this.descriptionEn,
    this.actionKey,
    this.actionLabelFa,
    this.actionLabelEn,
    this.isOptional = true,
  });

  final String titleFa;
  final String titleEn;
  final String descriptionFa;
  final String descriptionEn;
  final String? actionKey;
  final String? actionLabelFa;
  final String? actionLabelEn;
  final bool isOptional;
}

class OemDeviceGuide {
  const OemDeviceGuide({
    required this.oemLabelFa,
    required this.oemLabelEn,
    required this.steps,
  });

  final String oemLabelFa;
  final String oemLabelEn;
  final List<OemGuideStep> steps;
}

class OemGuideBuilder {
  OemGuideBuilder._();

  /// Builds tailored, step-by-step instructions based on Android SDK version
  /// and hardware manufacturer (`Build.MANUFACTURER` / `Build.BRAND`).
  static OemDeviceGuide buildForDevice({
    required String manufacturer,
    required String brand,
    required int sdkInt,
  }) {
    final m = '${manufacturer.toLowerCase()} ${brand.toLowerCase()}';
    final steps = <OemGuideStep>[];

    // 1. Android 13+ (API 33+) Sideload Restricted Settings Guide
    if (sdkInt >= 33) {
      steps.add(const OemGuideStep(
        titleFa: 'مرحله ۱ (اندروید ۱۳ به بالا): آزاد کردن تنظیمات محدودشده',
        titleEn: 'Step 1 (Android 13+): Allow Restricted Settings',
        descriptionFa:
            'اگر برنامه را از گیتهاب یا خارج از گوگل‌پلی نصب کرده‌اید، اندروید ۱۳ به بعد دسترسی نوتیفیکیشن را ابتدا قفل می‌کند:\n'
            '۱. دکمه زیر را بزنید تا صفحه «اطلاعات برنامه (App Info)» باز شود.\n'
            '۲. روی آیکون سه نقطه (⋮) در گوشه بالا کلیک کنید.\n'
            '۳. گزینه «اجازه تنظیمات محدودشده / Allow restricted settings» را بزنید و اثرانگشت/رمز گوشی را تایید کنید.\n'
            '(اگر از گوگل‌پلی نصب شده یا گزینه سه نقطه را نمی‌بینید، این مرحله لازم نیست.)',
        descriptionEn:
            'When installed from GitHub (sideloaded APK), Android 13+ locks Notification Access initially:\n'
            '1. Tap the button below to open "App Info".\n'
            '2. Tap the three-dot menu (⋮) in the top corner.\n'
            '3. Tap "Allow restricted settings" and confirm with your screen lock.\n'
            '(Skip this step if installed via Play Store or already unlocked.)',
        actionKey: 'openAppInfo',
        actionLabelFa: 'باز کردن صفحه App Info',
        actionLabelEn: 'Open App Info',
        isOptional: true,
      ));
    }

    // 2. Notification Access (reads Email, RCS, SMS, Telegram/WhatsApp notifications)
    steps.add(const OemGuideStep(
      titleFa: 'دسترسی خواندن نوتیفیکیشن‌ها (برای ایمیل، SMS و RCS)',
      titleEn: 'Notification Access (for Email, SMS & RCS)',
      descriptionFa:
          'این مجوز باعث می‌شود کدهای تایید ایمیل‌ها (Gmail، Outlook و...) و پیامک‌ها بدون نیاز به لاگین در ایمیل، به‌صورت کاملاً محلی تشخیص داده شوند. گزینه OtpBridge را روشن کنید.',
      descriptionEn:
          'Allows detecting Email (Gmail, Outlook, etc.) and SMS/RCS OTPs locally without ever logging into your email account. Toggle OtpBridge ON.',
      actionKey: 'openNotificationListener',
      actionLabelFa: 'باز کردن تنظیمات Notification Access',
      actionLabelEn: 'Open Notification Access',
      isOptional: true,
    ));

    // 3. Optional Direct SMS Permission (Hybrid mode)
    steps.add(const OemGuideStep(
      titleFa: 'دسترسی مستقیم SMS (اختیاری — حالت ترکیبی)',
      titleEn: 'Direct SMS Permission (Optional — Hybrid Mode)',
      descriptionFa:
          'در نسخه GitHub/Bazaar/Myket می‌توانید دسترسی RECEIVE_SMS را هم فعال کنید تا حتی اگر نوتیفیکیشن پیامک خاموش باشد، کدهای بانکی و پیامکی ۱۰۰٪ دریافت شوند. (در نسخه Google Play این مجوز حذف شده و اختیاری است.)',
      descriptionEn:
          'In the FOSS/GitHub build, granting RECEIVE_SMS ensures bank & SMS OTPs are captured even when SMS notifications are muted. Completely optional.',
      actionKey: 'requestSmsPermission',
      actionLabelFa: 'درخواست مجوز SMS',
      actionLabelEn: 'Grant SMS Permission',
      isOptional: true,
    ));

    // 4. OEM-Specific Background & Battery Reliability Guide
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      steps.add(const OemGuideStep(
        titleFa: 'تنظیمات ویژه گوشی‌های شیائومی / پوکو (MIUI / HyperOS)',
        titleEn: 'Xiaomi / Redmi / POCO (MIUI / HyperOS) Stability',
        descriptionFa:
            'شیائومی برنامه‌های پس‌زمینه را به‌سرعت می‌بندد. برای پایداری کامل:\n'
            '• گزینه «شروع خودکار در پس‌زمینه (Autostart)» را برای OtpBridge فعال کنید.\n'
            '• در بخش Battery Saver گزینه «No restrictions / بدون محدودیت» را انتخاب کنید.\n'
            '• در صفحه برنامه‌های اخیر (Recents) روی OtpBridge نگه دارید و آیکون قفل (🔒) را بزنید.',
        descriptionEn:
            'Xiaomi aggressively kills background services. For best reliability:\n'
            '• Enable "Autostart / Background autostart" for OtpBridge.\n'
            '• Set Battery Saver to "No restrictions".\n'
            '• Lock OtpBridge in the Recents screen (🔒).',
        actionKey: 'openOemAutostart',
        actionLabelFa: 'باز کردن تنظیمات Autostart شیائومی',
        actionLabelEn: 'Open Xiaomi Autostart',
        isOptional: true,
      ));
      return OemDeviceGuide(
        oemLabelFa: 'شیائومی / ردمی / پوکو (Android API $sdkInt)',
        oemLabelEn: 'Xiaomi / Redmi / POCO (Android API $sdkInt)',
        steps: steps,
      );
    }

    if (m.contains('samsung')) {
      steps.add(const OemGuideStep(
        titleFa: 'تنظیمات ویژه گوشی‌های سامسونگ (OneUI)',
        titleEn: 'Samsung (OneUI) Background Reliability',
        descriptionFa:
            'در OneUI ممکن است برنامه بعد از چند روز به حالت Deep Sleep برود:\n'
            '• در App Info → Battery گزینه «Unrestricted / بدون محدودیت» را انتخاب کنید.\n'
            '• در Device Care → Battery → Background usage limits برنامه را به «Never sleeping apps» اضافه کنید.',
        descriptionEn:
            'OneUI may put idle apps into Deep Sleep:\n'
            '• Go to App Info → Battery → select "Unrestricted".\n'
            '• Add OtpBridge to "Never sleeping apps" in Device Care.',
        actionKey: 'openBatteryOptimization',
        actionLabelFa: 'تنظیم باتری بدون محدودیت',
        actionLabelEn: 'Set Unrestricted Battery',
        isOptional: true,
      ));
      return OemDeviceGuide(
        oemLabelFa: 'سامسونگ OneUI (Android API $sdkInt)',
        oemLabelEn: 'Samsung OneUI (Android API $sdkInt)',
        steps: steps,
      );
    }

    if (m.contains('huawei') || m.contains('honor')) {
      steps.add(const OemGuideStep(
        titleFa: 'تنظیمات ویژه هوآوی / آنر (EMUI / MagicOS)',
        titleEn: 'Huawei / Honor (EMUI / MagicOS) Background Guide',
        descriptionFa:
            'وارد Settings → Battery → App launch شوید، حالت خودکار را برای OtpBridge خاموش کنید و هر سه گزینه Auto-launch، Secondary launch و Run in background را روشن بگذارید.',
        descriptionEn:
            'Open Settings → Battery → App launch, disable "Manage automatically" for OtpBridge, and enable Auto-launch, Secondary launch, and Run in background.',
        actionKey: 'openOemAutostart',
        actionLabelFa: 'باز کردن تنظیمات App Launch',
        actionLabelEn: 'Open App Launch Settings',
        isOptional: true,
      ));
      return OemDeviceGuide(
        oemLabelFa: 'هوآوی / آنر (Android API $sdkInt)',
        oemLabelEn: 'Huawei / Honor (Android API $sdkInt)',
        steps: steps,
      );
    }

    if (m.contains('oppo') || m.contains('realme') || m.contains('oneplus')) {
      steps.add(const OemGuideStep(
        titleFa: 'تنظیمات ویژه اوپو / ریلمی / وان‌پلاس (ColorOS / OxygenOS)',
        titleEn: 'Oppo / Realme / OnePlus (ColorOS / OxygenOS)',
        descriptionFa:
            'در App Info → Battery Usage گزینه‌های «Allow background activity» و «Allow auto-launch» را فعال کنید.',
        descriptionEn:
            'In App Info → Battery Usage, enable "Allow background activity" and "Allow auto-launch".',
        actionKey: 'openBatteryOptimization',
        actionLabelFa: 'باز کردن تنظیمات باتری',
        actionLabelEn: 'Open Battery Settings',
        isOptional: true,
      ));
      return OemDeviceGuide(
        oemLabelFa: 'اوپو / ریلمی / وان‌پلاس (Android API $sdkInt)',
        oemLabelEn: 'Oppo / Realme / OnePlus (Android API $sdkInt)',
        steps: steps,
      );
    }

    // Default / Pixel / Stock Android
    steps.add(const OemGuideStep(
      titleFa: 'غیرفعال کردن محدودیت باتری (اختیاری)',
      titleEn: 'Disable Battery Optimization (Optional)',
      descriptionFa:
          'برای اینکه هنگام قفل بودن صفحه گوشی هم کدها بدون تاخیر ارسال شوند، می‌توانید بهینه‌سازی باتری را برای OtpBridge غیرفعال کنید.',
      descriptionEn:
          'For instant OTP delivery even when the screen is off (Doze mode), exempt OtpBridge from battery optimization.',
      actionKey: 'openBatteryOptimization',
      actionLabelFa: 'غیرفعال کردن محدودیت باتری',
      actionLabelEn: 'Ignore Battery Optimization',
      isOptional: true,
    ));

    return OemDeviceGuide(
      oemLabelFa: '${manufacturer.isEmpty ? "اندروید" : manufacturer} (API $sdkInt)',
      oemLabelEn: '${manufacturer.isEmpty ? "Android" : manufacturer} (API $sdkInt)',
      steps: steps,
    );
  }
}
