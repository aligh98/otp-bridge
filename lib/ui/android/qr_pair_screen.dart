import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/otp_message.dart';
import '../../core/models/paired_device.dart';
import '../theme/app_theme.dart';

/// Android pairing screen: scans the Desktop QR code with camera OR accepts
/// a manual pairing code paste (100% offline, zero servers).
class QrPairScreen extends StatefulWidget {
  const QrPairScreen({
    super.key,
    required this.strings,
  });

  final AppStrings strings;

  @override
  State<QrPairScreen> createState() => _QrPairScreenState();
}

class _QrPairScreenState extends State<QrPairScreen> {
  final TextEditingController _manualController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();
  bool _handled = false;
  bool _manualMode = false;
  String? _error;

  void _tryAcceptRaw(String raw) {
    if (_handled) return;
    final payload = PairingPayload.tryParse(raw);
    if (payload == null) {
      setState(() {
        _error = widget.strings.t(
          'کد اتصال معتبر نیست. لطفاً QR نمایش‌داده‌شده در نسخه دسکتاپ را اسکن کنید.',
          'Invalid pairing payload. Please scan the QR shown on the Desktop app.',
        );
      });
      return;
    }
    _handled = true;
    Navigator.of(context).pop(PairedDevice.fromPairingPayload(payload));
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('اتصال به کامپیوتر', 'Pair with Desktop')),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _manualMode = !_manualMode),
            icon: Icon(_manualMode ? Icons.qr_code_scanner : Icons.keyboard),
            label: Text(_manualMode
                ? s.t('دوربین', 'Camera')
                : s.t('ورود دستی', 'Manual')),
          ),
        ],
      ),
      body: _manualMode
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    s.t(
                      'کد اتصال دستی (`otpbridge://pair?...`) را از نسخه دسکتاپ کپی و این‌جا پیست کنید:',
                      'Paste the manual pairing string (`otpbridge://pair?...`) copied from Desktop:',
                    ),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _manualController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'otpbridge://pair?d=...',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: AppTheme.rose)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => _tryAcceptRaw(_manualController.text),
                    child: Text(s.t('تایید و اتصال', 'Pair Device')),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    for (final barcode in capture.barcodes) {
                      final val = barcode.rawValue;
                      if (val != null && val.isNotEmpty) {
                        _tryAcceptRaw(val);
                        break;
                      }
                    }
                  },
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    color: Colors.black.withValues(alpha: 0.72),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.t(
                            'دوربین را روی QR Code نسخه دسکتاپ بگیرید',
                            'Point your camera at the QR Code shown on Desktop',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: const TextStyle(color: AppTheme.rose),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
