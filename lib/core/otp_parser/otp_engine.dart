import '../models/otp_message.dart';
import 'otp_entity_masker.dart';
import 'otp_keywords.dart';
import 'otp_normalizer.dart';

/// Detailed output of the multi-stage OTP parser, including diagnostics for
/// the interactive Parser Lab and automated precision/recall testing.
class OtpParseResult {
  const OtpParseResult({
    required this.isOtp,
    this.code,
    this.sender,
    this.score = 0,
    this.confidence = 0.0,
    this.reason = '',
    this.normalizedText = '',
    this.maskedText = '',
    this.candidates = const [],
  });

  final bool isOtp;
  final String? code;
  final String? sender;
  final int score;
  final double confidence;
  final String reason;
  final String normalizedText;
  final String maskedText;
  final List<OtpCandidateDebug> candidates;
}

class OtpCandidateDebug {
  const OtpCandidateDebug({
    required this.raw,
    required this.cleaned,
    required this.score,
    required this.notes,
  });

  final String raw;
  final String cleaned;
  final int score;
  final List<String> notes;
}

/// High-precision bilingual (Persian + English) OTP extraction engine.
///
/// Pipeline:
///   1. Unicode & Persian/Arabic digit normalization
///   2. Explicit standard format check (WebOTP `@domain #code`, Google `G-XXXXXX`)
///   3. Non-OTP entity masking (cards, IBANs, dates, times, amounts, phones, IDs)
///   4. Message-level OTP signal gate & negative transaction/promo shield
///   5. Candidate generation (numeric 4-8, split 3-3 / 4-4, explicit alphanumeric)
///   6. Local window contextual scoring + threshold decision
class OtpEngine {
  OtpEngine._();

  // WebOTP standard: `@domain.tld #123456` (last line or standalone)
  static final RegExp _webOtpRegex = RegExp(
    r'(?:^|\n)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\s+#([A-Za-z0-9]{4,8})\b',
  );

  // Google explicit format: `G-123456`
  static final RegExp _googleCodeRegex = RegExp(r'\bG-(\d{6})\b');

  // Split numeric OTP like `123-456` or `123 456` (3+3) or `1234-5678` (4+4)
  static final RegExp _splitNumericRegex =
      RegExp(r'(?<![A-Za-z0-9])(\d{3})[-\s](\d{3})(?![A-Za-z0-9])');

  // Pure numeric 4-8 digits (rejects decimals like 12.34 & IPs, allows sentence period "204819.")
  static final RegExp _pureNumericRegex =
      RegExp(r'(?<![A-Za-z0-9])(?<!\d[.,])(\d{4,8})(?![A-Za-z0-9])(?![.,]\d)');

  // Alphanumeric OTP (e.g., Steam Guard `K7M9P`, AWS/etc. `A4K92B`, `A4K-92B`)
  // Must contain at least one digit AND one uppercase letter, length 5-8.
  static final RegExp _alphanumericRegex = RegExp(
    r'(?<![A-Za-z0-9])((?=[A-Z0-9-]*[A-Z])(?=[A-Z0-9-]*\d)[A-Z0-9]{5,8}|(?=[A-Z0-9-]*[A-Z])(?=[A-Z0-9-]*\d)[A-Z0-9]{3}-[A-Z0-9]{3})(?![A-Za-z0-9])',
  );

  static int _thresholdFor(ParserSensitivity sensitivity) {
    switch (sensitivity) {
      case ParserSensitivity.strict:
        return 68;
      case ParserSensitivity.balanced:
        return 55;
      case ParserSensitivity.relaxed:
        return 42;
    }
  }

  /// Parses an incoming SMS, email notification, or chat message.
  ///
  /// [title] is optional (e.g., notification title / email subject / SMS sender).
  /// [body] is the message text.
  static OtpParseResult parse({
    required String body,
    String? title,
    String? senderHint,
    ParserSensitivity sensitivity = ParserSensitivity.balanced,
  }) {
    final combinedRaw = [
      if (title != null && title.trim().isNotEmpty) title.trim(),
      body.trim(),
    ].join('\n');

    if (combinedRaw.isEmpty) {
      return const OtpParseResult(isOtp: false, reason: 'Empty message');
    }

    final normalized = OtpNormalizer.normalizeForParsing(combinedRaw);
    final normalizedTitle =
        title != null ? OtpNormalizer.normalizeForParsing(title) : '';

    // -------------------------------------------------------------------------
    // Stage 2A: WebOTP Standard (`@domain.com #123456`)
    // -------------------------------------------------------------------------
    final webOtpMatch = _webOtpRegex.firstMatch(normalized);
    if (webOtpMatch != null) {
      final domain = webOtpMatch.group(1)!;
      final code = webOtpMatch.group(2)!;
      final resolvedSender = _resolveSender(
        normalizedText: normalized,
        title: normalizedTitle,
        senderHint: senderHint,
        webOtpDomain: domain,
      );
      return OtpParseResult(
        isOtp: true,
        code: code,
        sender: resolvedSender,
        score: 100,
        confidence: 0.99,
        reason: 'Matched WebOTP standard (@$domain #$code)',
        normalizedText: normalized,
        maskedText: normalized,
        candidates: [
          OtpCandidateDebug(
            raw: '#$code',
            cleaned: code,
            score: 100,
            notes: ['WebOTP origin-bound code (@$domain)'],
          ),
        ],
      );
    }

    // -------------------------------------------------------------------------
    // Stage 2B: Google Explicit Format (`G-123456`)
    // -------------------------------------------------------------------------
    final googleMatch = _googleCodeRegex.firstMatch(normalized);
    if (googleMatch != null &&
        (_hasAnyMatch(normalized, OtpKeywords.strongEnglishPatterns) ||
            _hasAnyMatch(normalized, OtpKeywords.strongPersianPatterns) ||
            _hasAnyMatch(normalized, OtpKeywords.mediumContextPatterns) ||
            normalized.toLowerCase().contains('google'))) {
      final code = googleMatch.group(1)!;
      return OtpParseResult(
        isOtp: true,
        code: code,
        sender: 'Google',
        score: 98,
        confidence: 0.99,
        reason: 'Matched Google G-XXXXXX format (stripped G- prefix for direct paste)',
        normalizedText: normalized,
        maskedText: normalized,
        candidates: [
          OtpCandidateDebug(
            raw: googleMatch.group(0)!,
            cleaned: code,
            score: 98,
            notes: ['Explicit Google verification format'],
          ),
        ],
      );
    }

    // -------------------------------------------------------------------------
    // Stage 3: Entity Masking (cards, amounts, dates, times, phones, IDs)
    // -------------------------------------------------------------------------
    final masked = OtpEntityMasker.maskNonOtpEntities(normalized);

    // -------------------------------------------------------------------------
    // Stage 4: Message-Level OTP Signal Gate & Anti-FP Shield
    // -------------------------------------------------------------------------
    final strongMatches = <RegExpMatch>[
      ..._findAllMatches(normalized, OtpKeywords.strongPersianPatterns),
      ..._findAllMatches(normalized, OtpKeywords.strongEnglishPatterns),
    ];
    final mediumMatches =
        _findAllMatches(normalized, OtpKeywords.mediumContextPatterns);
    final hasSecurityWarning =
        _hasAnyMatch(normalized, OtpKeywords.securityWarningPatterns);
    final hasNegativeMessageCue =
        _hasAnyMatch(normalized, OtpKeywords.negativeMessagePatterns);

    final hasStrongSignal = strongMatches.isNotEmpty;
    final hasMediumSignal = mediumMatches.isNotEmpty;

    // Hard Gate 1: Zero OTP context anywhere -> ALWAYS reject (prevents random numbers!)
    if (!hasStrongSignal && !hasMediumSignal) {
      return OtpParseResult(
        isOtp: false,
        reason: 'Rejected: no OTP/authentication keywords found',
        normalizedText: normalized,
        maskedText: masked,
      );
    }

    // Hard Gate 2: Transaction/Promo/Shipping message with NO strong OTP keyword -> reject
    if (hasNegativeMessageCue && !hasStrongSignal) {
      return OtpParseResult(
        isOtp: false,
        reason:
            'Rejected: transaction/promotional/tracking message without strong OTP keyword',
        normalizedText: normalized,
        maskedText: masked,
      );
    }

    // -------------------------------------------------------------------------
    // Stage 5: Candidate Generation on Masked Text
    // -------------------------------------------------------------------------
    final rawCandidates = <_RawCandidate>[];
    final coveredRanges = <(int, int)>[];

    bool overlapsCovered(int start, int end) {
      for (final (cs, ce) in coveredRanges) {
        if (start < ce && end > cs) return true;
      }
      return false;
    }

    // 5A. Split numeric codes (e.g. 123-456 or 123 456)
    for (final m in _splitNumericRegex.allMatches(masked)) {
      final cleaned = '${m.group(1)}${m.group(2)}';
      rawCandidates.add(_RawCandidate(
        raw: m.group(0)!,
        cleaned: cleaned,
        start: m.start,
        end: m.end,
        isAlphanumeric: false,
        isSplit: true,
      ));
      coveredRanges.add((m.start, m.end));
    }

    // 5B. Pure numeric 4-8 digit codes
    for (final m in _pureNumericRegex.allMatches(masked)) {
      if (overlapsCovered(m.start, m.end)) continue;
      final digits = m.group(1)!;
      rawCandidates.add(_RawCandidate(
        raw: digits,
        cleaned: digits,
        start: m.start,
        end: m.end,
        isAlphanumeric: false,
        isSplit: false,
      ));
      coveredRanges.add((m.start, m.end));
    }

    // 5C. Alphanumeric codes (ONLY allowed when a strong OTP keyword exists!)
    if (hasStrongSignal) {
      for (final m in _alphanumericRegex.allMatches(masked)) {
        if (overlapsCovered(m.start, m.end)) continue;
        final rawToken = m.group(0)!;
        final cleaned = rawToken.replaceAll('-', '');
        // Skip common non-OTP alphanumeric tokens (e.g., 2FA, 3D, COVID19, MP4, UTF8)
        if (_isCommonNonOtpAlphaToken(cleaned)) continue;
        rawCandidates.add(_RawCandidate(
          raw: rawToken,
          cleaned: cleaned,
          start: m.start,
          end: m.end,
          isAlphanumeric: true,
          isSplit: rawToken.contains('-'),
        ));
        coveredRanges.add((m.start, m.end));
      }
    }

    if (rawCandidates.isEmpty) {
      return OtpParseResult(
        isOtp: false,
        reason: 'Rejected: no valid candidate tokens survived entity masking',
        normalizedText: normalized,
        maskedText: masked,
      );
    }

    // -------------------------------------------------------------------------
    // Stage 6: Multi-Feature Contextual Candidate Scoring
    // -------------------------------------------------------------------------
    final scored = <(_RawCandidate, int, List<String>)>[];

    for (final c in rawCandidates) {
      var score = 0;
      final notes = <String>[];

      // Feature 1: Distance & direction to nearest strong OTP keyword
      final strongDist = _nearestKeywordDistance(c.start, c.end, strongMatches);
      if (strongDist != null) {
        if (strongDist <= 18) {
          score += 52;
          notes.add('+52 directly adjacent to strong OTP keyword (${strongDist}ch)');
        } else if (strongDist <= 45) {
          score += 38;
          notes.add('+38 close to strong OTP keyword (${strongDist}ch)');
        } else if (strongDist <= 100) {
          score += 24;
          notes.add('+24 within message near strong OTP keyword (${strongDist}ch)');
        } else {
          score += 14;
          notes.add('+14 strong OTP keyword elsewhere in message');
        }
      } else if (hasMediumSignal) {
        final medDist = _nearestKeywordDistance(c.start, c.end, mediumMatches);
        if (medDist != null && medDist <= 28) {
          score += 28;
          notes.add('+28 close to medium auth keyword (${medDist}ch)');
        } else {
          score += 14;
          notes.add('+14 medium auth context');
        }
      }

      // Feature 2: Direct punctuation binding (e.g., `کد تایید: 482910` or `Code: 482910`)
      final prefixWindow = _slice(normalized, c.start - 40, c.start);
      final immediateBefore = _slice(normalized, c.start - 6, c.start).trimRight();
      if (immediateBefore.endsWith(':') ||
          immediateBefore.endsWith('=') ||
          immediateBefore.endsWith('-')) {
        if (_hasAnyMatch(prefixWindow, OtpKeywords.strongPersianPatterns) ||
            _hasAnyMatch(prefixWindow, OtpKeywords.strongEnglishPatterns)) {
          score += 18;
          notes.add('+18 directly follows strong keyword + delimiter');
        } else if (_hasAnyMatch(prefixWindow, OtpKeywords.mediumContextPatterns)) {
          score += 10;
          notes.add('+10 directly follows auth keyword + delimiter');
        }
      }

      // Feature 3: Token length prior (5-6 digits is standard OTP length)
      final len = c.cleaned.length;
      if (!c.isAlphanumeric) {
        if (len == 6 || len == 5) {
          score += 16;
          notes.add('+16 standard $len-digit OTP length');
        } else if (len == 4) {
          score += 10;
          notes.add('+10 4-digit OTP length');
        } else if (len == 7 || len == 8) {
          score += 11;
          notes.add('+11 $len-digit OTP length');
        }
      } else {
        // Alphanumeric requires very tight proximity to strong keyword
        if (strongDist != null && strongDist <= 30) {
          score += 10;
          notes.add('+10 alphanumeric code tightly bound to strong keyword');
        } else {
          score -= 30;
          notes.add('-30 alphanumeric token not tightly bound to strong keyword');
        }
      }

      // Feature 4: Standalone line or wrapped in quotes/brackets
      if (_isStandaloneOnLine(normalized, c.start, c.end)) {
        score += 12;
        notes.add('+12 standalone on its own line');
      } else if (_isWrappedInQuotesOrBrackets(normalized, c.start, c.end)) {
        score += 8;
        notes.add('+8 wrapped in quotes/brackets');
      }

      // Feature 5: Security disclaimer bonus ("do not share", "در اختیار دیگران قرار ندهید")
      if (hasSecurityWarning) {
        score += 12;
        notes.add('+12 anti-sharing / validity security disclaimer present');
      }

      // Feature 6: Single surviving candidate bonus
      if (rawCandidates.length == 1 && hasStrongSignal) {
        score += 8;
        notes.add('+8 sole numeric candidate in strong-OTP message');
      }

      // Feature 7: Year-like 4-digit penalty (1380..1420, 1990..2035)
      if (!c.isAlphanumeric && len == 4) {
        final numVal = int.tryParse(c.cleaned) ?? 0;
        final isLikelyYear = (numVal >= 1380 && numVal <= 1425) ||
            (numVal >= 1990 && numVal <= 2035);
        if (isLikelyYear && (strongDist == null || strongDist > 20)) {
          score -= 45;
          notes.add('-45 looks like a calendar year ($numVal)');
        }
      }

      // Feature 8: Local negative proximity penalty (on masked text so already-masked
      // card/amount spans like "کارت ****8821" don't falsely penalize the actual OTP)
      final tightBefore = _slice(masked, c.start - 26, c.start);
      final tightAfter = _slice(masked, c.end, c.end + 18);
      // Only penalize if negative word appears closer than any strong OTP keyword
      final hasNegBefore =
          _hasAnyMatch(tightBefore, OtpKeywords.localNegativeProximityPatterns);
      final hasStrongBefore =
          _hasAnyMatch(tightBefore, OtpKeywords.strongPersianPatterns) ||
              _hasAnyMatch(tightBefore, OtpKeywords.strongEnglishPatterns);
      final hasNegAfter =
          _hasAnyMatch(tightAfter, OtpKeywords.localNegativeProximityPatterns);

      if (hasNegBefore && !hasStrongBefore) {
        score -= 45;
        notes.add('-45 immediately preceded by negative financial/ID keyword');
      }
      if (hasNegAfter && !c.isAlphanumeric) {
        // e.g. "4829 ریال" or "120 ثانیه" if anything slipped past masking
        if (RegExp(r'^\s*(?:ریال|تومان|تومن|ثانیه|دقیقه|ساعت|روز|درصد|%|usd|eur|irr|sec|min|hour|day)',
                caseSensitive: false)
            .hasMatch(tightAfter)) {
          score -= 55;
          notes.add('-55 directly followed by unit/currency');
        }
      }

      // Feature 9: Short message bonus (typical SMS OTP is concise < 240 chars)
      if (normalized.length <= 220 && hasStrongSignal) {
        score += 5;
        notes.add('+5 concise OTP message');
      }

      // Feature 10: Avoid repeated identical digits like 0000 or 1111 unless tightly bound
      if (!c.isAlphanumeric &&
          RegExp(r'^(\d)\1+$').hasMatch(c.cleaned) &&
          (strongDist == null || strongDist > 15)) {
        score -= 25;
        notes.add('-25 trivial repeated digits');
      }

      scored.add((c, score, notes));
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));

    final best = scored.first;
    final threshold = _thresholdFor(sensitivity);
    final debugCandidates = scored
        .map((e) => OtpCandidateDebug(
              raw: e.$1.raw,
              cleaned: e.$1.cleaned,
              score: e.$2,
              notes: e.$3,
            ))
        .toList();

    if (best.$2 < threshold) {
      return OtpParseResult(
        isOtp: false,
        score: best.$2,
        confidence: (best.$2.clamp(0, 100)) / 100.0,
        reason:
            'Rejected: top candidate "${best.$1.cleaned}" scored ${best.$2} < threshold $threshold',
        normalizedText: normalized,
        maskedText: masked,
        candidates: debugCandidates,
      );
    }

    final resolvedSender = _resolveSender(
      normalizedText: normalized,
      title: normalizedTitle,
      senderHint: senderHint,
    );

    final confidence = (best.$2.clamp(50, 100)) / 100.0;
    return OtpParseResult(
      isOtp: true,
      code: best.$1.cleaned,
      sender: resolvedSender,
      score: best.$2,
      confidence: confidence,
      reason: 'Accepted "${best.$1.cleaned}" (score ${best.$2} >= $threshold)',
      normalizedText: normalized,
      maskedText: masked,
      candidates: debugCandidates,
    );
  }

  static List<RegExpMatch> _findAllMatches(String text, List<RegExp> patterns) {
    final matches = <RegExpMatch>[];
    for (final p in patterns) {
      matches.addAll(p.allMatches(text));
    }
    return matches;
  }

  static bool _hasAnyMatch(String text, List<RegExp> patterns) {
    for (final p in patterns) {
      if (p.hasMatch(text)) return true;
    }
    return false;
  }

  static int? _nearestKeywordDistance(
    int start,
    int end,
    List<RegExpMatch> matches,
  ) {
    if (matches.isEmpty) return null;
    int? best;
    for (final m in matches) {
      int dist;
      if (m.end <= start) {
        // Keyword precedes candidate (slightly preferred)
        dist = start - m.end;
      } else if (m.start >= end) {
        // Keyword follows candidate (e.g. "482910 is your verification code")
        dist = m.start - end;
      } else {
        dist = 0;
      }
      if (best == null || dist < best) {
        best = dist;
      }
    }
    return best;
  }

  static String _slice(String text, int start, int end) {
    final s = start < 0 ? 0 : (start > text.length ? text.length : start);
    final e = end < s ? s : (end > text.length ? text.length : end);
    return text.substring(s, e);
  }

  static bool _isStandaloneOnLine(String text, int start, int end) {
    final lineStart = text.lastIndexOf('\n', start > 0 ? start - 1 : 0);
    final lineEnd = text.indexOf('\n', end);
    final ls = lineStart == -1 ? 0 : lineStart + 1;
    final le = lineEnd == -1 ? text.length : lineEnd;
    final line = text.substring(ls, le).trim();
    final token = text.substring(start, end).trim();
    return line == token || line == '"$token"' || line == "'$token'" || line == '«$token»';
  }

  static bool _isWrappedInQuotesOrBrackets(String text, int start, int end) {
    if (start == 0 || end >= text.length) return false;
    final before = text[start - 1];
    final after = text[end];
    const pairs = {
      '"': '"',
      "'": "'",
      '`': '`',
      '(': ')',
      '[': ']',
      '«': '»',
      '<': '>',
    };
    return pairs[before] == after;
  }

  static bool _isCommonNonOtpAlphaToken(String token) {
    const blocked = {
      'COVID19',
      'SHA256',
      'AES256',
      'UTF8',
      'HTTP2',
      'HTTPS2',
      'HTML5',
      'IPv4',
      'IPV4',
      'IPV6',
      '2FA',
      '3DS',
      'OAUTH2',
      'TLS13',
      'BASE64',
    };
    return blocked.contains(token.toUpperCase());
  }

  static String _resolveSender({
    required String normalizedText,
    required String title,
    String? senderHint,
    String? webOtpDomain,
  }) {
    // 1. Check known services/banks in title + body
    final searchPool = '$title\n$normalizedText\n${senderHint ?? ''}';
    for (final (regex, label) in OtpKeywords.knownServiceMatchers) {
      if (regex.hasMatch(searchPool)) {
        return label;
      }
    }

    // 2. WebOTP domain if present
    if (webOtpDomain != null && webOtpDomain.isNotEmpty) {
      return webOtpDomain;
    }

    // 3. Clean title or senderHint (if not a generic SMS numeric shortcode)
    if (senderHint != null &&
        senderHint.trim().isNotEmpty &&
        !RegExp(r'^\+?\d{4,}$').hasMatch(senderHint.trim())) {
      return senderHint.trim();
    }
    if (title.isNotEmpty && title.length <= 40) {
      return title;
    }
    if (senderHint != null && senderHint.trim().isNotEmpty) {
      return senderHint.trim();
    }

    return 'OTP';
  }
}

class _RawCandidate {
  const _RawCandidate({
    required this.raw,
    required this.cleaned,
    required this.start,
    required this.end,
    required this.isAlphanumeric,
    required this.isSplit,
  });

  final String raw;
  final String cleaned;
  final int start;
  final int end;
  final bool isAlphanumeric;
  final bool isSplit;
}
