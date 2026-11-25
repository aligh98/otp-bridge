/// Unicode, Persian, and Arabic text normalizer for deterministic OTP parsing.
class OtpNormalizer {
  OtpNormalizer._();

  static const Map<int, String> _digitMap = {
    // Persian digits (U+06F0..U+06F9)
    0x06F0: '0',
    0x06F1: '1',
    0x06F2: '2',
    0x06F3: '3',
    0x06F4: '4',
    0x06F5: '5',
    0x06F6: '6',
    0x06F7: '7',
    0x06F8: '8',
    0x06F9: '9',
    // Arabic-Indic digits (U+0660..U+0669)
    0x0660: '0',
    0x0661: '1',
    0x0662: '2',
    0x0663: '3',
    0x0664: '4',
    0x0665: '5',
    0x0666: '6',
    0x0667: '7',
    0x0668: '8',
    0x0669: '9',
    // Fullwidth digits (U+FF10..U+FF19)
    0xFF10: '0',
    0xFF11: '1',
    0xFF12: '2',
    0xFF13: '3',
    0xFF14: '4',
    0xFF15: '5',
    0xFF16: '6',
    0xFF17: '7',
    0xFF18: '8',
    0xFF19: '9',
  };

  /// Converts Persian, Arabic-Indic, and Fullwidth digits to ASCII 0-9.
  static String toAsciiDigits(String input) {
    final sb = StringBuffer();
    for (final unit in input.codeUnits) {
      final mapped = _digitMap[unit];
      if (mapped != null) {
        sb.write(mapped);
      } else {
        sb.writeCharCode(unit);
      }
    }
    return sb.toString();
  }

  /// Normalizes Persian/Arabic characters, digits, invisible bidi marks, and ZWNJ
  /// into a clean canonical form for OTP extraction while keeping line breaks.
  static String normalizeForParsing(String input) {
    final sb = StringBuffer();
    for (final unit in input.codeUnits) {
      // Digits -> ASCII
      final digit = _digitMap[unit];
      if (digit != null) {
        sb.write(digit);
        continue;
      }

      // Strip invisible directional/formatting characters & Arabic diacritics/tatweel
      if (unit == 0x200E || // LRM
          unit == 0x200F || // RLM
          unit == 0xFEFF || // BOM
          unit == 0x0640 || // Tatweel
          (unit >= 0x202A && unit <= 0x202E) || // Bidi embeddings
          (unit >= 0x2066 && unit <= 0x2069) || // Bidi isolates
          (unit >= 0x064B && unit <= 0x065F) || // Arabic diacritics
          unit == 0x0670) {
        continue;
      }

      // Normalize ZWNJ & NBSP to space so compound Persian words match uniformly
      if (unit == 0x200C || unit == 0x200D || unit == 0x00A0) {
        sb.write(' ');
        continue;
      }

      // Normalize Arabic Yeh / Kaf / Alef / Teh Marbuta / Hamza variants
      switch (unit) {
        case 0x064A: // ي
        case 0x0649: // ى
        case 0x0626: // ئ
          sb.write('ی');
          break;
        case 0x0643: // ك
          sb.write('ک');
          break;
        case 0x0623: // أ
        case 0x0625: // إ
        case 0x0622: // آ
        case 0x0671: // ٱ
          sb.write('ا');
          break;
        case 0x0629: // ة
          sb.write('ه');
          break;
        case 0x060C: // Arabic comma ،
          sb.write(',');
          break;
        case 0x066C: // Arabic thousands separator ٬
          sb.write(',');
          break;
        case 0x066B: // Arabic decimal separator ٫
          sb.write('.');
          break;
        case 0x2013: // En dash –
        case 0x2014: // Em dash —
        case 0x2212: // Minus −
          sb.write('-');
          break;
        default:
          sb.writeCharCode(unit);
      }
    }

    // Collapse repeated horizontal spaces while preserving newlines
    return sb
        .toString()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }
}
