import 'package:material_ui/material_ui.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/otp_message.dart';
import '../../core/otp_parser/otp_engine.dart';
import '../theme/app_theme.dart';

/// Interactive OTP Parser Lab allowing users to test ANY Persian or English
/// SMS/email message and inspect masking, candidate scores, and FP rejection.
class OtpTesterView extends StatefulWidget {
  const OtpTesterView({
    super.key,
    required this.strings,
    required this.sensitivity,
  });

  final AppStrings strings;
  final ParserSensitivity sensitivity;

  @override
  State<OtpTesterView> createState() => _OtpTesterViewState();
}

class _OtpTesterViewState extends State<OtpTesterView> {
  final _titleController = TextEditingController(text: 'بانک ملت');
  final _bodyController = TextEditingController(
    text: 'بانک ملت\nرمز پویا: ۶۴۹۲۸۱\nمبلغ: ۲,۵۰۰,۰۰۰ ریال\nکارت: ۶۱۰۴****۴۸۲۱\nاعتبار: ۱۲۰ ثانیه',
  );

  static const _samples = <(String, String, String)>[
    (
      'رمز پویا بانک ملت',
      'بانک ملت',
      'بانک ملت\nرمز پویا: ۶۴۹۲۸۱\nمبلغ: ۲,۵۰۰,۰۰۰ ریال\nکارت: ۶۱۰۴****۴۸۲۱\nاعتبار: ۱۲۰ ثانیه',
    ),
    (
      'تراکنش بانکی (نباید تشخیص بده!)',
      'بانک ملت',
      'بانک ملت\nبرداشت: 1,500,000 ریال\nحساب: 12345678\nمانده: 45,200,000 ریال\n1405/08/21 14:32\nکد پیگیری: 984512',
    ),
    (
      'ایمیل GitHub',
      '[GitHub] Please verify your device',
      'A sign in attempt requires further verification. Verification code: 729104. Do not share.',
    ),
    (
      'پیامک کد رهگیری پست (نباید تشخیص بده!)',
      'تیپاکس',
      'بسته شما با کد رهگیری 682910 آماده ارسال است. پشتیبانی: 0218457',
    ),
    (
      'Google G-Code',
      'Google',
      'G-819204 کد تایید Google شما است.',
    ),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final result = OtpEngine.parse(
      title: _titleController.text,
      body: _bodyController.text,
      sensitivity: widget.sensitivity,
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          s.t('آزمایشگاه موتور تشخیص OTP (فارسی + انگلیسی)',
              'OTP Detection Engine Lab (Persian + English)'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          s.t(
            'هر پیامک یا ایمیل نمونه را وارد کنید تا نحوه ماسک‌کردن مبالغ/کارت‌ها و امتیازدهی دقیق کدها را ببینید.',
            'Paste any SMS or email to inspect entity masking, candidate scoring, and false-positive rejection.',
          ),
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _samples.map((sample) {
            return ActionChip(
              label: Text(sample.$1, style: const TextStyle(fontSize: 12)),
              onPressed: () {
                setState(() {
                  _titleController.text = sample.$2;
                  _bodyController.text = sample.$3;
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: s.t('عنوان / فرستنده', 'Title / Sender'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bodyController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: s.t('متن پیامک یا نوتیفیکیشن ایمیل', 'SMS or Email Notification Body'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      result.isOtp
                          ? Icons.verified_rounded
                          : Icons.block_rounded,
                      color: result.isOtp ? AppTheme.emerald : AppTheme.rose,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        result.isOtp
                            ? s.t(
                                'تشخیص داده شد: ${result.code}  (${result.sender})',
                                'Detected OTP: ${result.code}  (${result.sender})',
                              )
                            : s.t(
                                'رد شد (کد تایید نیست — محافظت در برابر False Positive)',
                                'Rejected (Not an OTP — False Positive Prevented)',
                              ),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color:
                              result.isOtp ? AppTheme.emeraldLight : AppTheme.rose,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  result.reason,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                if (result.maskedText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.t('متن پس از ماسک‌کردن مبالغ، کارت‌ها و شناسه‌های غیرمرتبط:',
                        'Text after non-OTP entity masking:'),
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.slateBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      result.maskedText,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
                if (result.candidates.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.t('کاندیداها و جزئیات امتیاز:', 'Candidate Score Breakdown:'),
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 6),
                  for (final c in result.candidates)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• ${c.cleaned}  [score: ${c.score}] — ${c.notes.join(", ")}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
