/// Comprehensive Persian and English OTP lexicons, anti-FP rejection cues,
/// and service/bank name recognizers.
class OtpKeywords {
  OtpKeywords._();

  /// High-confidence Persian OTP phrases (normalized: no ZWNJ, Arabic Yeh/Kaf unified).
  static final List<RegExp> strongPersianPatterns = [
    RegExp(r'رمز\s*دوم\s*پویا'),
    RegExp(r'رمز\s*پویا'),
    RegExp(r'رمز\s*(?:دوم\s*)?یک\s*بار\s*مصرف'),
    RegExp(r'رمز\s*(?:دوم\s*)?یکبار\s*مصرف'),
    RegExp(r'رمز\s*عبور\s*(?:یک\s*بار\s*مصرف|یکبار\s*مصرف|موقت)'),
    RegExp(r'رمز\s*(?:ورود|موقت|تایید|عملیات|احراز|امنیتی|اینترنتی|تراکنش|کارت\s*پویا)'),
    RegExp(r'کد\s*(?:تایید|تاییدیه|ورود|فعال\s*سازی|فعالسازی|احراز\s*هویت|احراز|امنیتی|اعتبار\s*سنجی|اعتبارسنجی)'),
    RegExp(r'کد\s*(?:یک\s*بار\s*مصرف|یکبار\s*مصرف|موقت|ثبت\s*نام|بازیابی|تغییر\s*رمز|اختصاصی\s*ورود|دو\s*مرحله\s*ای|دومرحله\s*ای|دو\s*عاملی|دوعاملی|ورود\s*شما|تایید\s*شما)'),
    RegExp(r'کد\s*پویا'),
    RegExp(r'شناسه\s*ورود\s*یکبار\s*مصرف'),
    RegExp(r'کد\s*تراکنش\s*پویا'),
    RegExp(r'رمز\s*بانک'),
    RegExp(r'رمز\s*شما\s*[:=\-]'),
    RegExp(r'کد\s*شما\s*[:=\-]'),
  ];

  /// High-confidence English OTP phrases.
  static final List<RegExp> strongEnglishPatterns = [
    RegExp(r'\bverification\s*code\b', caseSensitive: false),
    RegExp(r'\bverify\s*(?:your\s*(?:account|email|phone|login|identity)\s*)?(?:with\s*)?(?:code|pin)\b', caseSensitive: false),
    RegExp(r'\bsecurity\s*code\b', caseSensitive: false),
    RegExp(r'\b(?:login|log\s*in|sign[\s-]?in)\s*(?:code|pin|passcode|otp)\b', caseSensitive: false),
    RegExp(r'\bone[\s-]?time\s*(?:password|passcode|code|pin)\b', caseSensitive: false),
    RegExp(r'\b(?:otp|totp)\b', caseSensitive: false),
    RegExp(r'\b(?:2fa|mfa|two[\s-]?factor|two[\s-]?step)\s*(?:code|pin|verification)?\b', caseSensitive: false),
    RegExp(r'\b(?:auth|authentication|authorization|confirmation|activation|recovery|reset|access|validation|passcode)\s*code\b', caseSensitive: false),
    RegExp(r'\bpasscode\b', caseSensitive: false),
    RegExp(r'\b(?:temporary|temp|single[\s-]?use)\s*(?:password|passcode|code|pin)\b', caseSensitive: false),
    RegExp(
      r'\b(?:your|the)\s+(?:(?!(?:promo|promotional|coupon|discount|voucher|tracking|order|invoice|ref|reference|zip|postal|area)\b)[\w-]+\s+){0,2}(?:code|pin)\s*(?:is|:)',
      caseSensitive: false,
    ),
    RegExp(r'\bis\s*your\s*(?:[\w-]+\s+){0,3}(?:code|pin|otp|passcode)\b', caseSensitive: false),
    RegExp(r'\buse\s*(?:code|this\s*code)\b', caseSensitive: false),
    RegExp(r'\benter\s*(?:this\s*)?(?:code|pin)\b', caseSensitive: false),
    RegExp(r'\bcode\s*[:=\-]\s*[A-Za-z0-9]', caseSensitive: false),
    RegExp(r'\bpin\s*[:=\-]\s*\d', caseSensitive: false),
  ];

  /// Medium supporting context signals (increase confidence when combined with a code).
  static final List<RegExp> mediumContextPatterns = [
    // Persian
    RegExp(r'ورود\s*به'),
    RegExp(r'ثبت\s*نام'),
    RegExp(r'احراز\s*هویت'),
    RegExp(r'در\s*اختیار\s*دیگران\s*قرار\s*ندهید'),
    RegExp(r'به\s*دیگران\s*ندهید'),
    RegExp(r'محرمانه'),
    RegExp(r'شخصی\s*است'),
    RegExp(r'معتبر\s*است'),
    RegExp(r'مدت\s*اعتبار'),
    RegExp(r'اعتبار\s*[:\s]*\d'),
    RegExp(r'تایید\s*شماره'),
    RegExp(r'تایید\s*حساب'),
    RegExp(r'خوش\s*امدید'),
    RegExp(r'کد\s*[:=\-]'),
    RegExp(r'رمز\s*[:=\-]'),
    // English
    RegExp(r"\bdo\s*not\s*share\b|\bdon'?t\s*share\b|\bnever\s*share\b", caseSensitive: false),
    RegExp(r'\bexpires?\s*in\b|\bvalid\s*for\b', caseSensitive: false),
    RegExp(r'\bconfirm\s*your\b|\bverify\s*your\b', caseSensitive: false),
    RegExp(r'\bsign\s*in\s*attempt\b|\blogin\s*attempt\b', caseSensitive: false),
    RegExp(r'\brequested\s*(?:a\s*)?(?:code|login|sign[\s-]?in)\b', caseSensitive: false),
    RegExp(r'\bif\s*you\s*did\s*not\s*request\b', caseSensitive: false),
    RegExp(r'\bsecurity\s*alert\b', caseSensitive: false),
  ];

  /// Strong anti-sharing / OTP-exclusive security disclaimer cues.
  static final List<RegExp> securityWarningPatterns = [
    RegExp(r'در\s*اختیار\s*(?:دیگران|غیر|کسی)\s*قرار\s*ندهید'),
    RegExp(r'محرمانه\s*است'),
    RegExp(r"\bdo\s*not\s*share\b|\bdon'?t\s*share\b|\bnever\s*share\b", caseSensitive: false),
    RegExp(r'\bexpires?\s*in\b|\bvalid\s*for\b', caseSensitive: false),
    RegExp(r'اعتبار\s*(?:این\s*(?:کد|رمز))?'),
  ];

  /// Message-level negative cues (transactions, promotions, shipping, receipts).
  /// If these exist WITHOUT any strong OTP keyword, the message is rejected.
  static final List<RegExp> negativeMessagePatterns = [
    // Persian banking transactions & ads
    RegExp(r'برداشت\s*(?:از\s*حساب|وجه|مبلغ)?\s*[:\d]'),
    RegExp(r'واریز\s*(?:به\s*حساب|وجه|مبلغ)?\s*[:\d]'),
    RegExp(r'مانده\s*(?:حساب|قابل\s*برداشت|کل)?\s*[:\d]'),
    RegExp(r'موجودی\s*[:\d]'),
    RegExp(r'انتقال\s*وجه\s*(?:انجام\s*شد|موفق)'),
    RegExp(r'کد\s*تخفیف'),
    RegExp(r'تخفیف\s*ویژه'),
    RegExp(r'جشنواره'),
    RegExp(r'قرعه\s*کشی'),
    RegExp(r'مرسوله\s*(?:شما)?'),
    RegExp(r'تحویل\s*پست'),
    RegExp(r'کد\s*رهگیری'),
    RegExp(r'کد\s*پیگیری'),
    RegExp(r'صورتحساب'),
    RegExp(r'قبض\s*(?:برق|گاز|اب|تلفن|موبایل)'),
    RegExp(r'بسته\s*اینترنت'),
    RegExp(r'شارژ\s*مستقیم'),
    RegExp(r'لغو\s*=?\s*11'),
    // English receipts, shipping, promos, dev notifications
    RegExp(r'\b(?:shipped|out\s*for\s*delivery|tracking\s*number|package\s*delivered)\b', caseSensitive: false),
    RegExp(r'\b(?:invoice|receipt|payment\s*received|order\s*confirmed|thank\s*you\s*for\s*your\s*order)\b', caseSensitive: false),
    RegExp(r'\b(?:unsubscribe|promo\s*code|coupon\s*code|discount\s*code|% ?off|flash\s*sale)\b', caseSensitive: false),
    RegExp(r'\b(?:pull\s*request|merged|assigned\s*to\s*you|mentioned\s*you)\b', caseSensitive: false),
  ];

  /// Local proximity penalty words immediately adjacent to a candidate number.
  static final List<RegExp> localNegativeProximityPatterns = [
    RegExp(r'(?:مانده|موجودی|مبلغ|واریز|برداشت|کارمزد|کارت|حساب|شعبه|پیگیری|رهگیری|ارجاع|سفارش|مرسوله|تخفیف|پستی|ملی|قبض|فاکتور|قسط|تلفن|تماس|پشتیبانی|پلاک|واحد|طبقه|ریال|تومان|تومن|ثانیه|دقیقه|ساعت|روز|درصد)'),
    RegExp(
      r'\b(?:amount|balance|total|price|paid|fee|card|account|acct|order|invoice|receipt|tracking|ref|reference|ticket|flight|booking|promo|coupon|discount|port|issue|pr|ext|zip|postal|ending|last|sec|min|hour|day|usd|eur|gbp|irr)\b',
      caseSensitive: false,
    ),
  ];

  /// Known Iranian banks, Iranian services, and global platforms for clean sender labeling.
  static final List<(RegExp, String)> knownServiceMatchers = [
    // Iranian Banks
    (RegExp(r'بانک\s*ملت|bank\s*mellat|mellat', caseSensitive: false), 'بانک ملت'),
    (RegExp(r'بانک\s*ملی|bank\s*melli|bmi\.ir|(?:^|\s)بام(?:\s|$)', caseSensitive: false), 'بانک ملی'),
    (RegExp(r'بانک\s*صادرات|saderat|bsi\.ir', caseSensitive: false), 'بانک صادرات'),
    (RegExp(r'بانک\s*تجارت|tejarat', caseSensitive: false), 'بانک تجارت'),
    (RegExp(r'بانک\s*سپه|sepah', caseSensitive: false), 'بانک سپه'),
    (RegExp(r'بانک\s*پاسارگاد|پاسارگاد|pasargad|ویپاد|wepod', caseSensitive: false), 'بانک پاسارگاد'),
    (RegExp(r'بلوبانک|بلو\s*بانک|blubank', caseSensitive: false), 'بلوبانک'),
    (RegExp(r'بانک\s*سامان|saman\s*bank|samanbank', caseSensitive: false), 'بانک سامان'),
    (RegExp(r'بانک\s*کشاورزی|keshavarzi', caseSensitive: false), 'بانک کشاورزی'),
    (RegExp(r'بانک\s*مسکن|maskan', caseSensitive: false), 'بانک مسکن'),
    (RegExp(r'بانک\s*رفاه|refah', caseSensitive: false), 'بانک رفاه'),
    (RegExp(r'بانک\s*شهر|shahr', caseSensitive: false), 'بانک شهر'),
    (RegExp(r'بانک\s*اینده|ayandeh', caseSensitive: false), 'بانک آینده'),
    (RegExp(r'بانک\s*پارسیان|parsian', caseSensitive: false), 'بانک پارسیان'),
    (RegExp(r'بانک\s*سینا|sina\s*bank', caseSensitive: false), 'بانک سینا'),
    (RegExp(r'بانک\s*مهر\s*ایران|قرض\s*الحسنه\s*مهر', caseSensitive: false), 'بانک مهر ایران'),
    (RegExp(r'بانک\s*رسالت|resalat', caseSensitive: false), 'بانک رسالت'),
    (RegExp(r'بانک\s*اقتصاد\s*نوین|enbank', caseSensitive: false), 'اقتصاد نوین'),
    (RegExp(r'بانک\s*دی\b|day\s*bank', caseSensitive: false), 'بانک دی'),
    (RegExp(r'بانک\s*گردشگری', caseSensitive: false), 'بانک گردشگری'),
    (RegExp(r'پست\s*بانک', caseSensitive: false), 'پست بانک'),
    (RegExp(r'شاپرک|shaparak', caseSensitive: false), 'شاپرک'),
    // Iranian Services & Gov
    (RegExp(r'دیجی\s*کالا|digikala', caseSensitive: false), 'دیجی‌کالا'),
    (RegExp(r'اسنپ|snapp', caseSensitive: false), 'اسنپ'),
    (RegExp(r'تپسی|tapsi', caseSensitive: false), 'تپسی'),
    (RegExp(r'دیوار|divar', caseSensitive: false), 'دیوار'),
    (RegExp(r'ترب|torob', caseSensitive: false), 'ترب'),
    (RegExp(r'دولت\s*من|my\.gov\.ir|پنجره\s*ملی', caseSensitive: false), 'دولت من'),
    (RegExp(r'سجام|sejam', caseSensitive: false), 'سجام'),
    (RegExp(r'ثنا|adliran|قوه\s*قضاییه', caseSensitive: false), 'سامانه ثنا'),
    (RegExp(r'سخا|sakha|پلیس\s*من', caseSensitive: false), 'سخا'),
    (RegExp(r'تامین\s*اجتماعی|tamin', caseSensitive: false), 'تامین اجتماعی'),
    (RegExp(r'نوبیتکس|nobitex', caseSensitive: false), 'نوبیتکس'),
    (RegExp(r'والکس|wallex', caseSensitive: false), 'والکس'),
    (RegExp(r'ایرانسل|irancell', caseSensitive: false), 'ایرانسل'),
    (RegExp(r'همراه\s*اول|mci\.ir', caseSensitive: false), 'همراه اول'),
    (RegExp(r'رایتل|rightel', caseSensitive: false), 'رایتل'),
    (RegExp(r'بله|bale\.ai', caseSensitive: false), 'بله'),
    (RegExp(r'ایتا|eitaa', caseSensitive: false), 'ایتا'),
    (RegExp(r'روبیکا|rubika', caseSensitive: false), 'روبیکا'),
    (RegExp(r'علی\s*بابا|alibaba\.ir', caseSensitive: false), 'علی‌بابا'),
    (RegExp(r'فیلیمو|filimo', caseSensitive: false), 'فیلیمو'),
    (RegExp(r'نماوا|namava', caseSensitive: false), 'نماوا'),
    (RegExp(r'اپارات|aparat', caseSensitive: false), 'آپارات'),
    (RegExp(r'بازار|cafebazaar', caseSensitive: false), 'کافه‌بازار'),
    (RegExp(r'مایکت|myket', caseSensitive: false), 'مایکت'),
    // Global Platforms
    (RegExp(r'\bgoogle\b|gmail|g-\d{6}', caseSensitive: false), 'Google'),
    (RegExp(r'\bgithub\b', caseSensitive: false), 'GitHub'),
    (RegExp(r'\bgitlab\b', caseSensitive: false), 'GitLab'),
    (RegExp(r'\btelegram\b|تلگرام', caseSensitive: false), 'Telegram'),
    (RegExp(r'\bwhatsapp\b|واتساپ', caseSensitive: false), 'WhatsApp'),
    (RegExp(r'\bmicrosoft\b|outlook|azure', caseSensitive: false), 'Microsoft'),
    (RegExp(r'\bapple\b|icloud', caseSensitive: false), 'Apple'),
    (RegExp(r'\bopenai\b|chatgpt', caseSensitive: false), 'OpenAI'),
    (RegExp(r'\banthropic\b|claude', caseSensitive: false), 'Claude'),
    (RegExp(r'\bdiscord\b', caseSensitive: false), 'Discord'),
    (RegExp(r'\bsteam\b', caseSensitive: false), 'Steam'),
    (RegExp(r'\bcloudflare\b', caseSensitive: false), 'Cloudflare'),
    (RegExp(r'\baws\b|amazon', caseSensitive: false), 'Amazon / AWS'),
    (RegExp(r'\bpaypal\b', caseSensitive: false), 'PayPal'),
    (RegExp(r'\bstripe\b', caseSensitive: false), 'Stripe'),
    (RegExp(r'\blinkedin\b', caseSensitive: false), 'LinkedIn'),
    (RegExp(r'\binstagram\b|اینستاگرام', caseSensitive: false), 'Instagram'),
    (RegExp(r'\bfacebook\b|\bmeta\b', caseSensitive: false), 'Meta'),
    (RegExp(r'\bx\.com\b|\btwitter\b', caseSensitive: false), 'X / Twitter'),
    (RegExp(r'\buber\b', caseSensitive: false), 'Uber'),
    (RegExp(r'\bairbnb\b', caseSensitive: false), 'Airbnb'),
    (RegExp(r'\bspotify\b', caseSensitive: false), 'Spotify'),
    (RegExp(r'\bnotion\b', caseSensitive: false), 'Notion'),
    (RegExp(r'\bslack\b', caseSensitive: false), 'Slack'),
    (RegExp(r'\bfigma\b', caseSensitive: false), 'Figma'),
    (RegExp(r'\bbinance\b', caseSensitive: false), 'Binance'),
    (RegExp(r'\bcoinbase\b', caseSensitive: false), 'Coinbase'),
    (RegExp(r'\bhetzner\b', caseSensitive: false), 'Hetzner'),
    (RegExp(r'\bdigitalocean\b', caseSensitive: false), 'DigitalOcean'),
  ];
}
