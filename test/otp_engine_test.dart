import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otp_bridge/core/models/otp_message.dart';
import 'package:otp_bridge/core/otp_parser/otp_deduplicator.dart';
import 'package:otp_bridge/core/otp_parser/otp_engine.dart';
import 'package:otp_bridge/core/otp_parser/otp_normalizer.dart';

void main() {
  final corpusFile = File('test/test_vectors/otp_corpus.json');
  final corpus =
      jsonDecode(corpusFile.readAsStringSync()) as Map<String, dynamic>;
  final truePositives = (corpus['true_positives'] as List).cast<Map<String, dynamic>>();
  final trueNegatives = (corpus['true_negatives'] as List).cast<Map<String, dynamic>>();

  group('OtpNormalizer', () {
    test('converts Persian, Arabic-Indic, and fullwidth digits to ASCII', () {
      expect(OtpNormalizer.toAsciiDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
      expect(OtpNormalizer.toAsciiDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(OtpNormalizer.toAsciiDigits('０１２３４５６７８９'), '0123456789');
    });

    test('strips invisible bidi characters and normalizes ZWNJ & Arabic Yeh/Kaf', () {
      const messy = '\u200Fكُد تأييد یک‌بارمصرف: \u200E۶۴۹۲۸۱';
      expect(
        OtpNormalizer.normalizeForParsing(messy),
        'کد تایید یک بارمصرف: 649281',
      );
    });
  });

  group('OtpEngine True Positives (Target: 100% Recall)', () {
    for (final item in truePositives) {
      final id = item['id'] as String;
      final title = item['title'] as String?;
      final body = item['body'] as String;
      final expectedCode = item['expected_code'] as String;
      final expectedSender = item['expected_sender'] as String?;

      test('detects [$id] -> $expectedCode', () {
        final result = OtpEngine.parse(
          title: title,
          body: body,
          sensitivity: ParserSensitivity.balanced,
        );

        expect(
          result.isOtp,
          isTrue,
          reason:
              'Missed OTP [$id]!\nReason: ${result.reason}\nMasked: ${result.maskedText}\nCandidates: ${result.candidates.map((c) => "${c.cleaned}:${c.score}(${c.notes})").join(" | ")}',
        );
        expect(
          result.code,
          expectedCode,
          reason:
              'Wrong code for [$id]! Got "${result.code}" instead of "$expectedCode".\nCandidates: ${result.candidates.map((c) => "${c.cleaned}:${c.score}(${c.notes})").join(" | ")}',
        );
        if (expectedSender != null) {
          expect(result.sender, expectedSender, reason: 'Sender mismatch for [$id]');
        }
      });
    }
  });

  group('OtpEngine True Negatives (Target: 0% False Positives)', () {
    for (final item in trueNegatives) {
      final id = item['id'] as String;
      final title = item['title'] as String?;
      final body = item['body'] as String;

      test('rejects non-OTP [$id]', () {
        final result = OtpEngine.parse(
          title: title,
          body: body,
          sensitivity: ParserSensitivity.balanced,
        );

        expect(
          result.isOtp,
          isFalse,
          reason:
              'FALSE POSITIVE on [$id]! Extracted "${result.code}" (score ${result.score}).\nReason: ${result.reason}\nMasked: ${result.maskedText}\nCandidates: ${result.candidates.map((c) => "${c.cleaned}:${c.score}(${c.notes})").join(" | ")}',
        );
      });
    }
  });

  group('OtpDeduplicator', () {
    test('deduplicates hybrid SMS + Notification events within 15s window', () {
      final dedup = OtpDeduplicator(windowSeconds: 15);
      expect(dedup.isDuplicate('649281', nowMs: 1000), isFalse);
      expect(dedup.isDuplicate('649281', nowMs: 1500), isTrue);
      expect(dedup.isDuplicate('649281', nowMs: 15999), isTrue);
      expect(dedup.isDuplicate('649281', nowMs: 17000), isFalse);
    });
  });
}
