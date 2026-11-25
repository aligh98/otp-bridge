import 'package:material_ui/material_ui.dart';

class AppTheme {
  AppTheme._();

  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldLight = Color(0xFF34D399);
  static const Color slateBg = Color(0xFF0B1120);
  static const Color slateSurface = Color(0xFF111827);
  static const Color slateCard = Color(0xFF1E293B);
  static const Color slateBorder = Color(0xFF334155);
  static const Color amber = Color(0xFFF59E0B);
  static const Color sky = Color(0xFF38BDF8);
  static const Color rose = Color(0xFFF43F5E);

  static ThemeData darkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
      surface: slateSurface,
    ).copyWith(
      primary: emerald,
      secondary: sky,
      error: rose,
      surfaceContainerHighest: slateCard,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: slateBg,
      cardTheme: CardThemeData(
        color: slateCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: slateBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: slateSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slateBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slateBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: emerald, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: emerald,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: slateSurface,
        side: const BorderSide(color: slateBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
