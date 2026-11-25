# Contributing to OtpBridge

Thank you for helping make **OtpBridge** better, safer, and more accurate!

## Adding New OTP Templates or False-Positive Traps

If you encounter an SMS or email that was **missed** (False Negative) or **incorrectly detected** (False Positive):

1. **Sanitize all sensitive data** (replace real OTP digits, card numbers, amounts, names, and phone numbers with fake values while preserving the exact wording and punctuation).
2. Add the sanitized sample to `test/test_vectors/otp_corpus.json` under `true_positives` or `true_negatives`.
3. Update both:
   - Dart parser (`lib/core/otp_parser/`)
   - Android native Kotlin mirror (`android/app/src/main/kotlin/dev/otpbridge/otp_bridge/NativeOtpEngine.kt`)
4. Run `flutter test` and verify **100% pass rate** (0% false positives).

## Security & Privacy Rules for PRs

- **Zero Internet Policy:** Never add cloud SDKs, analytics, crash reporting, remote font downloads, or outbound HTTP requests.
- All TCP/UDP sockets MUST pass through `LocalNetworkGuard` / `NativeLocalNetworkGuard`.
- Never log raw OTP codes or message bodies to persistent storage or system logs (`Log.d`/`print`).
