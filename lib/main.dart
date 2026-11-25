import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'core/models/app_settings.dart';
import 'core/storage/settings_repository.dart';
import 'ui/android/android_home_screen.dart';
import 'ui/desktop/desktop_home_screen.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await SettingsRepository.create();
  runApp(OtpBridgeApp(repository: repository));
}

class OtpBridgeApp extends StatefulWidget {
  const OtpBridgeApp({super.key, required this.repository});

  final SettingsRepository repository;

  @override
  State<OtpBridgeApp> createState() => _OtpBridgeAppState();
}

class _OtpBridgeAppState extends State<OtpBridgeApp> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.repository.loadSettings();
  }

  void _onSettingsChanged(AppSettings updated) {
    setState(() => _settings = updated);
    widget.repository.saveSettings(updated);
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = _settings.isPersian;
    return MaterialApp(
      title: 'OtpBridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      builder: (context, child) {
        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Platform.isAndroid
          ? AndroidHomeScreen(
              repository: widget.repository,
              settings: _settings,
              onSettingsChanged: _onSettingsChanged,
            )
          : DesktopHomeScreen(
              repository: widget.repository,
              settings: _settings,
              onSettingsChanged: _onSettingsChanged,
            ),
    );
  }
}
