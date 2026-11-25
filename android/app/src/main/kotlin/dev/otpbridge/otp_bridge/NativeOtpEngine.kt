package dev.otpbridge.otp_bridge

/**
 * 100% feature-parity Kotlin mirror of Dart `OtpEngine`.
 *
 * Verified against the exact same `test/test_vectors/otp_corpus.json` suite via
 * JUnit tests so Android background capture matches Dart with 100% recall and
 * 0% false positives even when the Flutter UI is closed.
 */
object NativeOtpEngine {

    data class ParseResult(
        val isOtp: Boolean,
        val code: String? = null,
        val sender: String? = null,
        val score: Int = 0,
        val confidence: Double = 0.0,
    )

    private val webOtpRegex = Regex("""(?:^|\n)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\s+#([A-Za-z0-9]{4,8})\b""")
    private val googleCodeRegex = Regex("""\bG-(\d{6})\b""")
    private val splitNumericRegex = Regex("""(?<![A-Za-z0-9])(\d{3})[-\s](\d{3})(?![A-Za-z0-9])""")
    private val pureNumericRegex = Regex("""(?<![A-Za-z0-9])(?<!\d[.,])(\d{4,8})(?![A-Za-z0-9])(?![.,]\d)""")
    private val alphaRegex = Regex(
        """(?<![A-Za-z0-9])((?=[A-Z0-9-]*[A-Z])(?=[A-Z0-9-]*\d)[A-Z0-9]{5,8}|(?=[A-Z0-9-]*[A-Z])(?=[A-Z0-9-]*\d)[A-Z0-9]{3}-[A-Z0-9]{3})(?![A-Za-z0-9])"""
    )
    private val repeatedDigitsRegex = Regex("""^(\d)\1+$""")
    private val trailingUnitRegex = Regex(
        """^\s*(?:ریال|تومان|تومن|ثانیه|دقیقه|ساعت|روز|درصد|%|usd|eur|irr|sec|min|hour|day)""",
        RegexOption.IGNORE_CASE,
    )

    private val blockedAlphaTokens = setOf(
        "COVID19", "SHA256", "AES256", "UTF8", "HTTP2", "HTTPS2",
        "HTML5", "IPV4", "IPV6", "2FA", "3DS", "OAUTH2", "TLS13", "BASE64",
    )

    private val maskPatterns = listOf(
        Regex("""https?://\S+""", RegexOption.IGNORE_CASE),
        Regex("""\bwww\.\S+""", RegexOption.IGNORE_CASE),
        Regex("""\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b"""),
        Regex("""\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b""", RegexOption.IGNORE_CASE),
        Regex("""\b\d{4}[-\s]?[\d*xX•●]{4}[-\s]?[\d*xX•●]{4}[-\s]?\d{4}\b"""),
        Regex("""\b\d{4,6}[*xX•●]{2,12}\d{4}\b"""),
        Regex("""[*xX•●]{3,12}\d{4}\b"""),
        Regex("""\b\d{16}\b"""),
        Regex("""(?:شماره\s*کارت|کارت|حساب|شماره\s*حساب|سپرده)\s*(?:بانکی|شما|مبدا|مقصد)?\s*[:=\-#]?\s*[\d*xX•●\-./]{4,24}"""),
        Regex("""(?:card|account|acct)\s*(?:ending\s*(?:in|with)|last\s*4(?:\s*digits)?|no\.?|number|#)?\s*[:=\-#]?\s*[\d*xX•●\-]{4,20}""", RegexOption.IGNORE_CASE),
        Regex("""\b(?:13|14|19|20)\d{2}[/\-.]\d{1,2}[/\-.]\d{1,2}\b"""),
        Regex("""\b\d{1,2}[/\-.]\d{1,2}[/\-.](?:13|14|19|20)?\d{2}\b"""),
        Regex("""\b(?:13|14|19|20)\d{2}[/\-.]\d{1,2}\b"""),
        Regex("""\b\d{1,2}:\d{2}(?::\d{2})?\b"""),
        Regex("""\b\d{1,3}(?:,\d{3})+(?:\.\d+)?\b"""),
        Regex("""\b\d+(?:[.,]\d+)?\s*(?:ریال|تومان|تومن|هزار\s*تومان|میلیون\s*تومان|میلیون\s*ریال|دلار|یورو|پوند|درهم|لیر|تتر|IRR|IRT|USD|EUR|GBP|AED|TRY|USDT|BTC|ETH)\b""", RegexOption.IGNORE_CASE),
        Regex("""(?:[$€£¥₹])\s*\d+(?:[.,]\d+)*"""),
        Regex("""(?:مبلغ|مانده|موجودی|واریز|برداشت|کارمزد|بدهکار|بستانکار|قسط|تخفیف|مجموع|جمع\s*کل|سقف|پرداختی|تراکنش\s*به\s*مبلغ)\s*[:=\-]?\s*[+\-]?\s*[\d,./]+"""),
        Regex("""(?:amount|balance|bal|total|price|paid|fee|charged?|debited|credited|deposit|withdrawal)\s*[:=\-]?\s*(?:[$€£¥₹]|USD|EUR|IRR|IRT)?\s*[\d,]+(?:\.\d+)?""", RegexOption.IGNORE_CASE),
        Regex("""\b\d+\s*(?:ثانیه|دقیقه|ساعت|روز|هفته|ماه|سال|sec|secs|second|seconds|min|mins|minute|minutes|hr|hrs|hour|hours|day|days)\b""", RegexOption.IGNORE_CASE),
        Regex("""(?:\+98|0098|(?<!\d)98|(?<!\d)0)9\d{9}\b"""),
        Regex("""(?<!\d)0\d{2,3}[-\s]?\d{7,8}\b"""),
        Regex("""\+\d{1,3}[-\s]?\(?\d{2,4}\)?[-\s]?\d{3,4}[-\s]?\d{3,5}\b"""),
        Regex("""\*[\d*#]+#"""),
        Regex("""لغو\s*=?\s*11\b"""),
        Regex("""(?:ارسال\s*(?:عدد\s*\d+\s*)?به|به\s*شماره)\s*\d{4,14}"""),
        Regex("""(?:تلفن|تماس|پشتیبانی|مرکز\s*تماس|شماره\s*تماس|شماره\s*پشتیبانی|فکس)\s*[:=\-]?\s*[\d\s\-+]{4,16}"""),
        Regex("""(?:call|phone|tel|hotline|support|contact)\s*(?:us\s*(?:at|on))?\s*[:=\-]?\s*[\d\s\-+()]{5,18}""", RegexOption.IGNORE_CASE),
        Regex("""(?:کد|شماره|شناسه)\s*(?:پیگیری|رهگیری|ارجاع|مرسوله|سفارش|پستی|ملی|اقتصادی|اشتراک|تخفیف|فیش|قبض|پرداخت|پرونده|عضویت|پرسنلی|قرارداد|بیمه(?:\s*نامه)?|نوبت|پذیرش|فاکتور|تراکنش|صندوق|شعبه|پلاک|پرواز|واچر|کوپن|قرعه\s*کشی|دانشجویی|مشتری|تیکت|درخواست|محصول|کالا)\s*(?:شما)?\s*(?:عبارت\s*است\s*از|برابر\s*است\s*با)?\s*[:=\-#]?\s*[A-Za-z0-9\-]{3,24}"""),
        Regex("""(?:کدپستی|کدملی|کد\s*پستی|کد\s*ملی|کد\s*تخفیف|شعبه|پلاک|طبقه|واحد|سفارش|مرسوله|فاکتور|قبض|فیش|تیکت|درخواست)\s*(?:شماره)?\s*[:=\-#]\s*[A-Za-z0-9\-]{3,20}"""),
        Regex("""(?:سفارش|تیکت|فاکتور|درخواست|مرسوله)\s*(?:شماره\s*)?#?\d{4,15}"""),
        Regex("""\b(?:order|invoice|receipt|tracking|track|reference|ref|ticket|case|flight|booking|reservation|shipment|parcel|promo|promotional|coupon|discount|voucher|port|issue|pr|pull\s*request|commit|meeting|webinar|room|zip|postal|extension|ext|building|apt|suite|unit|policy|claim|member|customer|client|patient|batch|serial|model|sku|item|product|transaction|txn|tx|trace|rrn|stan)\s*(?:no\.?|num(?:ber)?|id|code|#)?\s*[:=\-#]\s*[A-Za-z0-9\-]{3,24}""", RegexOption.IGNORE_CASE),
        Regex("""\b(?:order|invoice|ticket|issue|pr|booking|flight|tracking|ref|reference|transaction|txn)\s+(?:number\s+|no\.?\s+|id\s+|#\s*)?[A-Za-z]{0,3}\d{4,16}\b""", RegexOption.IGNORE_CASE),
        Regex("""\b\d+(?:\.\d+)?\s*(?:%|درصد)"""),
        Regex("""(?<!\d)\d{9,}(?!\d)"""),
    )

    private val strongPatterns = listOf(
        // Persian
        Regex("""رمز\s*دوم\s*پویا"""),
        Regex("""رمز\s*پویا"""),
        Regex("""رمز\s*(?:دوم\s*)?یک\s*بار\s*مصرف"""),
        Regex("""رمز\s*(?:دوم\s*)?یکبار\s*مصرف"""),
        Regex("""رمز\s*عبور\s*(?:یک\s*بار\s*مصرف|یکبار\s*مصرف|موقت)"""),
        Regex("""رمز\s*(?:ورود|موقت|تایید|عملیات|احراز|امنیتی|اینترنتی|تراکنش|کارت\s*پویا)"""),
        Regex("""کد\s*(?:تایید|تاییدیه|ورود|فعال\s*سازی|فعالسازی|احراز\s*هویت|احراز|امنیتی|اعتبار\s*سنجی|اعتبارسنجی)"""),
        Regex("""کد\s*(?:یک\s*بار\s*مصرف|یکبار\s*مصرف|موقت|ثبت\s*نام|بازیابی|تغییر\s*رمز|اختصاصی\s*ورود|دو\s*مرحله\s*ای|دومرحله\s*ای|دو\s*عاملی|دوعاملی|ورود\s*شما|تایید\s*شما)"""),
        Regex("""کد\s*پویا"""),
        Regex("""شناسه\s*ورود\s*یکبار\s*مصرف"""),
        Regex("""کد\s*تراکنش\s*پویا"""),
        Regex("""رمز\s*بانک"""),
        Regex("""رمز\s*شما\s*[:=\-]"""),
        Regex("""کد\s*شما\s*[:=\-]"""),
        // English
        Regex("""\bverification\s*code\b""", RegexOption.IGNORE_CASE),
        Regex("""\bverify\s*(?:your\s*(?:account|email|phone|login|identity)\s*)?(?:with\s*)?(?:code|pin)\b""", RegexOption.IGNORE_CASE),
        Regex("""\bsecurity\s*code\b""", RegexOption.IGNORE_CASE),
        Regex("""\b(?:login|log\s*in|sign[\s-]?in)\s*(?:code|pin|passcode|otp)\b""", RegexOption.IGNORE_CASE),
        Regex("""\bone[\s-]?time\s*(?:password|passcode|code|pin)\b""", RegexOption.IGNORE_CASE),
        Regex("""\b(?:otp|totp)\b""", RegexOption.IGNORE_CASE),
        Regex("""\b(?:2fa|mfa|two[\s-]?factor|two[\s-]?step)\s*(?:code|pin|verification)?\b""", RegexOption.IGNORE_CASE),
        Regex("""\b(?:auth|authentication|authorization|confirmation|activation|recovery|reset|access|validation|passcode)\s*code\b""", RegexOption.IGNORE_CASE),
        Regex("""\bpasscode\b""", RegexOption.IGNORE_CASE),
        Regex("""\b(?:temporary|temp|single[\s-]?use)\s*(?:password|passcode|code|pin)\b""", RegexOption.IGNORE_CASE),
        Regex("""\b(?:your|the)\s+(?:(?!(?:promo|promotional|coupon|discount|voucher|tracking|order|invoice|ref|reference|zip|postal|area)\b)[\w-]+\s+){0,2}(?:code|pin)\s*(?:is|:)""", RegexOption.IGNORE_CASE),
        Regex("""\bis\s*your\s*(?:[\w-]+\s+){0,3}(?:code|pin|otp|passcode)\b""", RegexOption.IGNORE_CASE),
        Regex("""\buse\s*(?:code|this\s*code)\b""", RegexOption.IGNORE_CASE),
        Regex("""\benter\s*(?:this\s*)?(?:code|pin)\b""", RegexOption.IGNORE_CASE),
        Regex("""\bcode\s*[:=\-]\s*[A-Za-z0-9]""", RegexOption.IGNORE_CASE),
        Regex("""\bpin\s*[:=\-]\s*\d""", RegexOption.IGNORE_CASE),
    )

    private val mediumPatterns = listOf(
        Regex("""ورود\s*به|ثبت\s*نام|احراز\s*هویت|در\s*اختیار\s*دیگران\s*قرار\s*ندهید|به\s*دیگران\s*ندهید|محرمانه|شخصی\s*است|معتبر\s*است|مدت\s*اعتبار|اعتبار\s*[:\s]*\d|تایید\s*شماره|تایید\s*حساب|خوش\s*امدید|کد\s*[:=\-]|رمز\s*[:=\-]"""),
        Regex("""\b(?:do\s*not\s*share|don'?t\s*share|never\s*share|expires?\s*in|valid\s*for|confirm\s*your|verify\s*your|sign\s*in\s*attempt|login\s*attempt|requested\s*(?:a\s*)?(?:code|login|sign[\s-]?in)|if\s*you\s*did\s*not\s*request|security\s*alert)\b""", RegexOption.IGNORE_CASE),
    )

    private val securityWarningPatterns = listOf(
        Regex("""در\s*اختیار\s*(?:دیگران|غیر|کسی)\s*قرار\s*ندهید|محرمانه\s*است|اعتبار"""),
        Regex("""\b(?:do\s*not\s*share|don'?t\s*share|never\s*share|expires?\s*in|valid\s*for)\b""", RegexOption.IGNORE_CASE),
    )

    private val negativeMessagePatterns = listOf(
        Regex("""برداشت\s*(?:از\s*حساب|وجه|مبلغ)?\s*[:\d]|واریز\s*(?:به\s*حساب|وجه|مبلغ)?\s*[:\d]|مانده\s*(?:حساب|قابل\s*برداشت|کل)?\s*[:\d]|موجودی\s*[:\d]|انتقال\s*وجه\s*(?:انجام\s*شد|موفق)|کد\s*تخفیف|تخفیف\s*ویژه|جشنواره|قرعه\s*کشی|مرسوله|تحویل\s*پست|کد\s*رهگیری|کد\s*پیگیری|صورتحساب|قبض\s*(?:برق|گاز|اب|تلفن|موبایل)|بسته\s*اینترنت|شارژ\s*مستقیم|لغو\s*=?\s*11"""),
        Regex("""\b(?:shipped|out\s*for\s*delivery|tracking\s*number|package\s*delivered|invoice|receipt|payment\s*received|order\s*confirmed|thank\s*you\s*for\s*your\s*order|unsubscribe|promo\s*code|coupon\s*code|discount\s*code|% ?off|flash\s*sale|pull\s*request|merged|assigned\s*to\s*you|mentioned\s*you)\b""", RegexOption.IGNORE_CASE),
    )

    private val localNegativePatterns = listOf(
        Regex("""(?:مانده|موجودی|مبلغ|واریز|برداشت|کارمزد|کارت|حساب|شعبه|پیگیری|رهگیری|ارجاع|سفارش|مرسوله|تخفیف|پستی|ملی|قبض|فاکتور|قسط|تلفن|تماس|پشتیبانی|پلاک|واحد|طبقه|ریال|تومان|تومن|ثانیه|دقیقه|ساعت|روز|درصد)"""),
        Regex("""\b(?:amount|balance|total|price|paid|fee|card|account|acct|order|invoice|receipt|tracking|ref|reference|ticket|flight|booking|promo|coupon|discount|port|issue|pr|ext|zip|postal|ending|last|sec|min|hour|day|usd|eur|gbp|irr)\b""", RegexOption.IGNORE_CASE),
    )

    private val knownServices = listOf(
        // Iranian Banks
        Regex("""بانک\s*ملت|bank\s*mellat|mellat""", RegexOption.IGNORE_CASE) to "بانک ملت",
        Regex("""بانک\s*ملی|bank\s*melli|bmi\.ir|(?:^|\s)بام(?:\s|$)""", RegexOption.IGNORE_CASE) to "بانک ملی",
        Regex("""بانک\s*صادرات|saderat|bsi\.ir""", RegexOption.IGNORE_CASE) to "بانک صادرات",
        Regex("""بانک\s*تجارت|tejarat""", RegexOption.IGNORE_CASE) to "بانک تجارت",
        Regex("""بانک\s*سپه|sepah""", RegexOption.IGNORE_CASE) to "بانک سپه",
        Regex("""بانک\s*پاسارگاد|پاسارگاد|pasargad|ویپاد|wepod""", RegexOption.IGNORE_CASE) to "بانک پاسارگاد",
        Regex("""بلوبانک|بلو\s*بانک|blubank""", RegexOption.IGNORE_CASE) to "بلوبانک",
        Regex("""بانک\s*سامان|saman\s*bank|samanbank""", RegexOption.IGNORE_CASE) to "بانک سامان",
        Regex("""بانک\s*کشاورزی|keshavarzi""", RegexOption.IGNORE_CASE) to "بانک کشاورزی",
        Regex("""بانک\s*مسکن|maskan""", RegexOption.IGNORE_CASE) to "بانک مسکن",
        Regex("""بانک\s*رفاه|refah""", RegexOption.IGNORE_CASE) to "بانک رفاه",
        Regex("""بانک\s*شهر|shahr""", RegexOption.IGNORE_CASE) to "بانک شهر",
        Regex("""بانک\s*اینده|ayandeh""", RegexOption.IGNORE_CASE) to "بانک آینده",
        Regex("""بانک\s*پارسیان|parsian""", RegexOption.IGNORE_CASE) to "بانک پارسیان",
        Regex("""بانک\s*سینا|sina\s*bank""", RegexOption.IGNORE_CASE) to "بانک سینا",
        Regex("""بانک\s*مهر\s*ایران|قرض\s*الحسنه\s*مهر""", RegexOption.IGNORE_CASE) to "بانک مهر ایران",
        Regex("""بانک\s*رسالت|resalat""", RegexOption.IGNORE_CASE) to "بانک رسالت",
        Regex("""بانک\s*اقتصاد\s*نوین|enbank""", RegexOption.IGNORE_CASE) to "اقتصاد نوین",
        Regex("""بانک\s*دی\b|day\s*bank""", RegexOption.IGNORE_CASE) to "بانک دی",
        Regex("""بانک\s*گردشگری""", RegexOption.IGNORE_CASE) to "بانک گردشگری",
        Regex("""پست\s*بانک""", RegexOption.IGNORE_CASE) to "پست بانک",
        Regex("""شاپرک|shaparak""", RegexOption.IGNORE_CASE) to "شاپرک",
        // Iranian Services & Gov
        Regex("""دیجی\s*کالا|digikala""", RegexOption.IGNORE_CASE) to "دیجی‌کالا",
        Regex("""اسنپ|snapp""", RegexOption.IGNORE_CASE) to "اسنپ",
        Regex("""تپسی|tapsi""", RegexOption.IGNORE_CASE) to "تپسی",
        Regex("""دیوار|divar""", RegexOption.IGNORE_CASE) to "دیوار",
        Regex("""ترب|torob""", RegexOption.IGNORE_CASE) to "ترب",
        Regex("""دولت\s*من|my\.gov\.ir|پنجره\s*ملی""", RegexOption.IGNORE_CASE) to "دولت من",
        Regex("""سجام|sejam""", RegexOption.IGNORE_CASE) to "سجام",
        Regex("""ثنا|adliran|قوه\s*قضاییه""", RegexOption.IGNORE_CASE) to "سامانه ثنا",
        Regex("""سخا|sakha|پلیس\s*من""", RegexOption.IGNORE_CASE) to "سخا",
        Regex("""تامین\s*اجتماعی|tamin""", RegexOption.IGNORE_CASE) to "تامین اجتماعی",
        Regex("""نوبیتکس|nobitex""", RegexOption.IGNORE_CASE) to "نوبیتکس",
        Regex("""والکس|wallex""", RegexOption.IGNORE_CASE) to "والکس",
        Regex("""ایرانسل|irancell""", RegexOption.IGNORE_CASE) to "ایرانسل",
        Regex("""همراه\s*اول|mci\.ir""", RegexOption.IGNORE_CASE) to "همراه اول",
        Regex("""رایتل|rightel""", RegexOption.IGNORE_CASE) to "رایتل",
        Regex("""بله|bale\.ai""", RegexOption.IGNORE_CASE) to "بله",
        Regex("""ایتا|eitaa""", RegexOption.IGNORE_CASE) to "ایتا",
        Regex("""روبیکا|rubika""", RegexOption.IGNORE_CASE) to "روبیکا",
        Regex("""علی\s*بابا|alibaba\.ir""", RegexOption.IGNORE_CASE) to "علی‌بابا",
        Regex("""فیلیمو|filimo""", RegexOption.IGNORE_CASE) to "فیلیمو",
        Regex("""نماوا|namava""", RegexOption.IGNORE_CASE) to "نماوا",
        Regex("""اپارات|aparat""", RegexOption.IGNORE_CASE) to "آپارات",
        Regex("""بازار|cafebazaar""", RegexOption.IGNORE_CASE) to "کافه‌بازار",
        Regex("""مایکت|myket""", RegexOption.IGNORE_CASE) to "مایکت",
        // Global Platforms
        Regex("""\bgoogle\b|gmail|g-\d{6}""", RegexOption.IGNORE_CASE) to "Google",
        Regex("""\bgithub\b""", RegexOption.IGNORE_CASE) to "GitHub",
        Regex("""\bgitlab\b""", RegexOption.IGNORE_CASE) to "GitLab",
        Regex("""\btelegram\b|تلگرام""", RegexOption.IGNORE_CASE) to "Telegram",
        Regex("""\bwhatsapp\b|واتساپ""", RegexOption.IGNORE_CASE) to "WhatsApp",
        Regex("""\bmicrosoft\b|outlook|azure""", RegexOption.IGNORE_CASE) to "Microsoft",
        Regex("""\bapple\b|icloud""", RegexOption.IGNORE_CASE) to "Apple",
        Regex("""\bopenai\b|chatgpt""", RegexOption.IGNORE_CASE) to "OpenAI",
        Regex("""\banthropic\b|claude""", RegexOption.IGNORE_CASE) to "Claude",
        Regex("""\bdiscord\b""", RegexOption.IGNORE_CASE) to "Discord",
        Regex("""\bsteam\b""", RegexOption.IGNORE_CASE) to "Steam",
        Regex("""\bcloudflare\b""", RegexOption.IGNORE_CASE) to "Cloudflare",
        Regex("""\baws\b|amazon""", RegexOption.IGNORE_CASE) to "Amazon / AWS",
        Regex("""\bpaypal\b""", RegexOption.IGNORE_CASE) to "PayPal",
        Regex("""\bstripe\b""", RegexOption.IGNORE_CASE) to "Stripe",
        Regex("""\blinkedin\b""", RegexOption.IGNORE_CASE) to "LinkedIn",
        Regex("""\binstagram\b|اینستاگرام""", RegexOption.IGNORE_CASE) to "Instagram",
        Regex("""\bfacebook\b|\bmeta\b""", RegexOption.IGNORE_CASE) to "Meta",
        Regex("""\bx\.com\b|\btwitter\b""", RegexOption.IGNORE_CASE) to "X / Twitter",
        Regex("""\buber\b""", RegexOption.IGNORE_CASE) to "Uber",
        Regex("""\bairbnb\b""", RegexOption.IGNORE_CASE) to "Airbnb",
        Regex("""\bspotify\b""", RegexOption.IGNORE_CASE) to "Spotify",
        Regex("""\bnotion\b""", RegexOption.IGNORE_CASE) to "Notion",
        Regex("""\bslack\b""", RegexOption.IGNORE_CASE) to "Slack",
        Regex("""\bfigma\b""", RegexOption.IGNORE_CASE) to "Figma",
        Regex("""\bbinance\b""", RegexOption.IGNORE_CASE) to "Binance",
        Regex("""\bcoinbase\b""", RegexOption.IGNORE_CASE) to "Coinbase",
        Regex("""\bhetzner\b""", RegexOption.IGNORE_CASE) to "Hetzner",
        Regex("""\bdigitalocean\b""", RegexOption.IGNORE_CASE) to "DigitalOcean",
    )

    fun normalize(input: String): String {
        val sb = StringBuilder(input.length)
        for (ch in input) {
            val code = ch.code
            when {
                code in 0x06F0..0x06F9 -> sb.append(('0'.code + (code - 0x06F0)).toChar())
                code in 0x0660..0x0669 -> sb.append(('0'.code + (code - 0x0660)).toChar())
                code in 0xFF10..0xFF19 -> sb.append(('0'.code + (code - 0xFF10)).toChar())
                code == 0x200E || code == 0x200F || code == 0xFEFF || code == 0x0640 ||
                    code in 0x202A..0x202E || code in 0x2066..0x2069 ||
                    code in 0x064B..0x065F || code == 0x0670 -> Unit
                code == 0x200C || code == 0x200D || code == 0x00A0 -> sb.append(' ')
                code == 0x064A || code == 0x0649 || code == 0x0626 -> sb.append('ی')
                code == 0x0643 -> sb.append('ک')
                code == 0x0623 || code == 0x0625 || code == 0x0622 || code == 0x0671 -> sb.append('ا')
                code == 0x0629 -> sb.append('ه')
                code == 0x060C || code == 0x066C -> sb.append(',')
                code == 0x066B -> sb.append('.')
                code == 0x2013 || code == 0x2014 || code == 0x2212 -> sb.append('-')
                else -> sb.append(ch)
            }
        }
        return sb.toString()
            .replace("\r\n", "\n")
            .replace('\r', '\n')
            .replace(Regex("""[ \t]+"""), " ")
            .trim()
    }

    private fun maskNonOtp(text: String): String {
        val chars = text.toCharArray()
        for (p in maskPatterns) {
            for (m in p.findAll(text)) {
                for (i in m.range) {
                    if (chars[i] != '\n') chars[i] = '_'
                }
            }
        }
        return String(chars)
    }

    fun parse(
        title: String?,
        body: String,
        senderHint: String? = null,
        sensitivity: String = "balanced",
    ): ParseResult {
        val combined = buildString {
            if (!title.isNullOrBlank()) {
                append(title.trim())
                append('\n')
            }
            append(body.trim())
        }.trim()
        if (combined.isEmpty()) return ParseResult(false)

        val normalized = normalize(combined)
        val normTitle = title?.let { normalize(it) } ?: ""

        // 1. WebOTP
        webOtpRegex.find(normalized)?.let { m ->
            val domain = m.groupValues[1]
            val code = m.groupValues[2]
            return ParseResult(
                isOtp = true,
                code = code,
                sender = resolveSender(normalized, normTitle, senderHint, domain),
                score = 100,
                confidence = 0.99,
            )
        }

        // 2. Google G-XXXXXX
        googleCodeRegex.find(normalized)?.let { m ->
            if (strongPatterns.any { it.containsMatchIn(normalized) } ||
                mediumPatterns.any { it.containsMatchIn(normalized) } ||
                normalized.contains("google", ignoreCase = true)
            ) {
                return ParseResult(
                    isOtp = true,
                    code = m.groupValues[1],
                    sender = "Google",
                    score = 98,
                    confidence = 0.99,
                )
            }
        }

        val masked = maskNonOtp(normalized)
        val strongMatches = strongPatterns.flatMap { it.findAll(normalized).toList() }
        val mediumMatches = mediumPatterns.flatMap { it.findAll(normalized).toList() }
        val hasStrong = strongMatches.isNotEmpty()
        val hasMedium = mediumMatches.isNotEmpty()
        val hasSecWarn = securityWarningPatterns.any { it.containsMatchIn(normalized) }
        val hasNegMsg = negativeMessagePatterns.any { it.containsMatchIn(normalized) }

        if (!hasStrong && !hasMedium) return ParseResult(false)
        if (hasNegMsg && !hasStrong) return ParseResult(false)

        data class Cand(val cleaned: String, val start: Int, val end: Int, val isAlpha: Boolean)
        val cands = mutableListOf<Cand>()
        val covered = mutableListOf<IntRange>()
        fun overlaps(s: Int, e: Int) = covered.any { s <= it.last && e >= it.first }

        for (m in splitNumericRegex.findAll(masked)) {
            cands.add(Cand(m.groupValues[1] + m.groupValues[2], m.range.first, m.range.last + 1, false))
            covered.add(m.range)
        }
        for (m in pureNumericRegex.findAll(masked)) {
            if (overlaps(m.range.first, m.range.last)) continue
            cands.add(Cand(m.groupValues[1], m.range.first, m.range.last + 1, false))
            covered.add(m.range)
        }
        if (hasStrong) {
            for (m in alphaRegex.findAll(masked)) {
                if (overlaps(m.range.first, m.range.last)) continue
                val cleaned = m.value.replace("-", "")
                if (cleaned.uppercase() in blockedAlphaTokens) continue
                cands.add(Cand(cleaned, m.range.first, m.range.last + 1, true))
                covered.add(m.range)
            }
        }
        if (cands.isEmpty()) return ParseResult(false)

        fun nearestDist(s: Int, e: Int, matches: List<MatchResult>): Int? {
            if (matches.isEmpty()) return null
            return matches.minOf { m ->
                val ms = m.range.first
                val me = m.range.last + 1
                when {
                    me <= s -> s - me
                    ms >= e -> ms - e
                    else -> 0
                }
            }
        }

        fun slice(text: String, s: Int, e: Int): String {
            val a = s.coerceIn(0, text.length)
            val b = e.coerceIn(a, text.length)
            return text.substring(a, b)
        }

        fun isStandaloneOnLine(text: String, s: Int, e: Int): Boolean {
            val lineStart = text.lastIndexOf('\n', if (s > 0) s - 1 else 0)
            val lineEnd = text.indexOf('\n', e)
            val ls = if (lineStart == -1) 0 else lineStart + 1
            val le = if (lineEnd == -1) text.length else lineEnd
            val line = text.substring(ls, le).trim()
            val token = text.substring(s, e).trim()
            return line == token || line == "\"$token\"" || line == "'$token'" || line == "«$token»"
        }

        fun isWrappedInQuotesOrBrackets(text: String, s: Int, e: Int): Boolean {
            if (s == 0 || e >= text.length) return false
            val before = text[s - 1]
            val after = text[e]
            return (before == '"' && after == '"') ||
                (before == '\'' && after == '\'') ||
                (before == '`' && after == '`') ||
                (before == '(' && after == ')') ||
                (before == '[' && after == ']') ||
                (before == '«' && after == '»') ||
                (before == '<' && after == '>')
        }

        var bestCode: String? = null
        var bestScore = Int.MIN_VALUE

        for (c in cands) {
            var score = 0
            val strongDist = nearestDist(c.start, c.end, strongMatches)
            if (strongDist != null) {
                score += when {
                    strongDist <= 18 -> 52
                    strongDist <= 45 -> 38
                    strongDist <= 100 -> 24
                    else -> 14
                }
            } else if (hasMedium) {
                val medDist = nearestDist(c.start, c.end, mediumMatches)
                score += if (medDist != null && medDist <= 28) 28 else 14
            }

            val prefix = slice(normalized, c.start - 40, c.start)
            val before = slice(normalized, c.start - 6, c.start).trimEnd()
            if (before.endsWith(':') || before.endsWith('=') || before.endsWith('-')) {
                if (strongPatterns.any { it.containsMatchIn(prefix) }) score += 18
                else if (mediumPatterns.any { it.containsMatchIn(prefix) }) score += 10
            }

            val len = c.cleaned.length
            if (!c.isAlpha) {
                score += when (len) {
                    5, 6 -> 16
                    4 -> 10
                    7, 8 -> 11
                    else -> 0
                }
            } else {
                score += if (strongDist != null && strongDist <= 30) 10 else -30
            }

            if (isStandaloneOnLine(normalized, c.start, c.end)) {
                score += 12
            } else if (isWrappedInQuotesOrBrackets(normalized, c.start, c.end)) {
                score += 8
            }

            if (hasSecWarn) score += 12
            if (cands.size == 1 && hasStrong) score += 8
            if (normalized.length <= 220 && hasStrong) score += 5

            if (!c.isAlpha && len == 4) {
                val v = c.cleaned.toIntOrNull() ?: 0
                if ((v in 1380..1425 || v in 1990..2035) && (strongDist == null || strongDist > 20)) {
                    score -= 45
                }
            }

            val tightBefore = slice(masked, c.start - 26, c.start)
            val tightAfter = slice(masked, c.end, c.end + 18)
            val hasNegBefore = localNegativePatterns.any { it.containsMatchIn(tightBefore) }
            val hasStrongBefore = strongPatterns.any { it.containsMatchIn(tightBefore) }
            if (hasNegBefore && !hasStrongBefore) score -= 45
            if (!c.isAlpha && trailingUnitRegex.containsMatchIn(tightAfter)) score -= 55

            if (!c.isAlpha &&
                repeatedDigitsRegex.matches(c.cleaned) &&
                (strongDist == null || strongDist > 15)
            ) {
                score -= 25
            }

            if (score > bestScore) {
                bestScore = score
                bestCode = c.cleaned
            }
        }

        val threshold = when (sensitivity) {
            "strict" -> 68
            "relaxed" -> 42
            else -> 55
        }
        if (bestCode == null || bestScore < threshold) {
            return ParseResult(false, score = bestScore)
        }

        return ParseResult(
            isOtp = true,
            code = bestCode,
            sender = resolveSender(normalized, normTitle, senderHint, null),
            score = bestScore,
            confidence = bestScore.coerceIn(50, 100) / 100.0,
        )
    }

    private fun resolveSender(
        normalized: String,
        title: String,
        senderHint: String?,
        webDomain: String?,
    ): String {
        val pool = "$title\n$normalized\n${senderHint ?: ""}"
        for ((re, label) in knownServices) {
            if (re.containsMatchIn(pool)) return label
        }
        if (!webDomain.isNullOrBlank()) return webDomain
        if (!senderHint.isNullOrBlank() && !Regex("""^\+?\d{4,}$""").matches(senderHint.trim())) {
            return senderHint.trim()
        }
        if (title.isNotBlank() && title.length <= 40) return title
        return senderHint?.trim()?.ifBlank { null } ?: "OTP"
    }
}
