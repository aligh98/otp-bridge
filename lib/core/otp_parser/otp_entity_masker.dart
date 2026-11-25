/// Masks non-OTP numeric/alphanumeric entities (amounts, card numbers, dates,
/// times, phones, IBANs, tracking/order/invoice/account IDs, URLs, durations)
/// so the OTP candidate scorer never mistakes them for verification codes.
class OtpEntityMasker {
  OtpEntityMasker._();

  static final List<RegExp> _maskPatterns = [
    // 1. URLs & Email addresses (Note: WebOTP @domain #code is checked BEFORE masking)
    RegExp(r'https?://\S+', caseSensitive: false),
    RegExp(r'\bwww\.\S+', caseSensitive: false),
    RegExp(r'\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b'),

    // 2. IBAN (Iranian & international)
    RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b', caseSensitive: false),

    // 3. Full & Masked Bank Card Numbers (e.g. 6037-99**-****-1234, 6104****4821, ****4821)
    RegExp(r'\b\d{4}[-\s]?[\d*xX•●]{4}[-\s]?[\d*xX•●]{4}[-\s]?\d{4}\b'),
    RegExp(r'\b\d{4,6}[*xX•●]{2,12}\d{4}\b'),
    RegExp(r'[*xX•●]{3,12}\d{4}\b'),
    RegExp(r'\b\d{16}\b'),
    RegExp(
      r'(?:شماره\s*کارت|کارت|حساب|شماره\s*حساب|سپرده)\s*(?:بانکی|شما|مبدا|مقصد)?\s*[:=\-#]?\s*[\d*xX•●\-./]{4,24}',
    ),
    RegExp(
      r'(?:card|account|acct)\s*(?:ending\s*(?:in|with)|last\s*4(?:\s*digits)?|no\.?|number|#)?\s*[:=\-#]?\s*[\d*xX•●\-]{4,20}',
      caseSensitive: false,
    ),

    // 4. Dates (Jalali 13xx/14xx and Gregorian 19xx/20xx) & short dates
    RegExp(r'\b(?:13|14|19|20)\d{2}[/\-.]\d{1,2}[/\-.]\d{1,2}\b'),
    RegExp(r'\b\d{1,2}[/\-.]\d{1,2}[/\-.](?:13|14|19|20)?\d{2}\b'),
    RegExp(r'\b(?:13|14|19|20)\d{2}[/\-.]\d{1,2}\b'),

    // 5. Times (HH:MM:SS or HH:MM)
    RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\b'),

    // 6. Financial amounts (comma-separated, currency suffix/prefix, financial label)
    RegExp(r'\b\d{1,3}(?:,\d{3})+(?:\.\d+)?\b'),
    RegExp(
      r'\b\d+(?:[.,]\d+)?\s*(?:ریال|تومان|تومن|هزار\s*تومان|میلیون\s*تومان|میلیون\s*ریال|دلار|یورو|پوند|درهم|لیر|تتر|IRR|IRT|USD|EUR|GBP|AED|TRY|USDT|BTC|ETH)\b',
      caseSensitive: false,
    ),
    RegExp(r'(?:[$€£¥₹])\s*\d+(?:[.,]\d+)*'),
    RegExp(
      r'(?:مبلغ|مانده|موجودی|واریز|برداشت|کارمزد|بدهکار|بستانکار|قسط|تخفیف|مجموع|جمع\s*کل|سقف|پرداختی|تراکنش\s*به\s*مبلغ)\s*[:=\-]?\s*[+\-]?\s*[\d,./]+',
    ),
    RegExp(
      r'(?:amount|balance|bal|total|price|paid|fee|charged?|debited|credited|deposit|withdrawal)\s*[:=\-]?\s*(?:[$€£¥₹]|USD|EUR|IRR|IRT)?\s*[\d,]+(?:\.\d+)?',
      caseSensitive: false,
    ),

    // 7. Durations / Validity windows (e.g. 120 ثانیه, 2 minutes)
    RegExp(
      r'\b\d+\s*(?:ثانیه|دقیقه|ساعت|روز|هفته|ماه|سال|sec|secs|second|seconds|min|mins|minute|minutes|hr|hrs|hour|hours|day|days)\b',
      caseSensitive: false,
    ),

    // 8. Phone numbers, USSD codes, SMS shortcodes & cancellation footers
    RegExp(r'(?:\+98|0098|(?<!\d)98|(?<!\d)0)9\d{9}\b'),
    RegExp(r'(?<!\d)0\d{2,3}[-\s]?\d{7,8}\b'),
    RegExp(r'\+\d{1,3}[-\s]?\(?\d{2,4}\)?[-\s]?\d{3,4}[-\s]?\d{3,5}\b'),
    RegExp(r'\*[\d*#]+#'),
    RegExp(r'لغو\s*=?\s*11\b'),
    RegExp(r'(?:ارسال\s*(?:عدد\s*\d+\s*)?به|به\s*شماره)\s*\d{4,14}'),
    RegExp(
      r'(?:تلفن|تماس|پشتیبانی|مرکز\s*تماس|شماره\s*تماس|شماره\s*پشتیبانی|فکس)\s*[:=\-]?\s*[\d\s\-+]{4,16}',
    ),
    RegExp(
      r'(?:call|phone|tel|hotline|support|contact)\s*(?:us\s*(?:at|on))?\s*[:=\-]?\s*[\d\s\-+()]{5,18}',
      caseSensitive: false,
    ),

    // 9. Explicit Non-OTP Persian Codes & Identifiers
    RegExp(
      r'(?:کد|شماره|شناسه)\s*(?:پیگیری|رهگیری|ارجاع|مرسوله|سفارش|پستی|ملی|اقتصادی|اشتراک|تخفیف|فیش|قبض|پرداخت|پرونده|عضویت|پرسنلی|قرارداد|بیمه(?:\s*نامه)?|نوبت|پذیرش|فاکتور|تراکنش|صندوق|شعبه|پلاک|پرواز|واچر|کوپن|قرعه\s*کشی|دانشجویی|مشتری|تیکت|درخواست|محصول|کالا)\s*(?:شما)?\s*(?:عبارت\s*است\s*از|برابر\s*است\s*با)?\s*[:=\-#]?\s*[A-Za-z0-9\-]{3,24}',
    ),
    RegExp(
      r'(?:کدپستی|کدملی|کد\s*پستی|کد\s*ملی|کد\s*تخفیف|شعبه|پلاک|طبقه|واحد|سفارش|مرسوله|فاکتور|قبض|فیش|تیکت|درخواست)\s*(?:شماره)?\s*[:=\-#]\s*[A-Za-z0-9\-]{3,20}',
    ),
    RegExp(r'(?:سفارش|تیکت|فاکتور|درخواست|مرسوله)\s*(?:شماره\s*)?#?\d{4,15}'),

    // 10. Explicit Non-OTP English Codes & Identifiers
    RegExp(
      r'\b(?:order|invoice|receipt|tracking|track|reference|ref|ticket|case|flight|booking|reservation|shipment|parcel|promo|promotional|coupon|discount|voucher|port|issue|pr|pull\s*request|commit|meeting|webinar|room|zip|postal|extension|ext|building|apt|suite|unit|policy|claim|member|customer|client|patient|batch|serial|model|sku|item|product|transaction|txn|tx|trace|rrn|stan)\s*(?:no\.?|num(?:ber)?|id|code|#)?\s*[:=\-#]\s*[A-Za-z0-9\-]{3,24}',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:order|invoice|ticket|issue|pr|booking|flight|tracking|ref|reference|transaction|txn)\s+(?:number\s+|no\.?\s+|id\s+|#\s*)?[A-Za-z]{0,3}\d{4,16}\b',
      caseSensitive: false,
    ),

    // 11. Percentages (e.g. 50% تخفیف, 20% off)
    RegExp(r'\b\d+(?:\.\d+)?\s*(?:%|درصد)'),

    // 12. Very long pure digit strings (>= 9 digits: national IDs, postal codes, account IDs)
    RegExp(r'(?<!\d)\d{9,}(?!\d)'),
  ];

  /// Replaces matched non-OTP spans with underscores of identical length so
  /// character offsets remain intact for proximity scoring.
  static String maskNonOtpEntities(String normalizedText) {
    final chars = normalizedText.split('');
    for (final pattern in _maskPatterns) {
      for (final match in pattern.allMatches(normalizedText)) {
        for (var i = match.start; i < match.end; i++) {
          if (chars[i] != '\n') {
            chars[i] = '_';
          }
        }
      }
    }
    return chars.join();
  }
}
