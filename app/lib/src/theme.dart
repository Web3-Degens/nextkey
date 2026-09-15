import 'package:flutter/material.dart';

/// One accent, reserved for the mark and the primary action — the same rule
/// `web/brand/README.md` states, and the same two values. Never a gradient.
const nkAccentLight = Color(0xFF9A5218);
const nkAccentDark = Color(0xFFE2954A);
const nkPaper = Color(0xFFFAF9F7);
const nkInk = Color(0xFF1A1714);

ThemeData nkTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: nkAccentLight,
    brightness: brightness,
  ).copyWith(
    primary: dark ? nkAccentDark : nkAccentLight,
    surface: dark ? nkInk : nkPaper,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    // No `cardTheme:` here on purpose. Its type was renamed between Flutter
    // versions (`CardTheme` → `CardThemeData`), and a theme file that only
    // compiles on one of them is a trap for whoever upgrades. `Card` picks up
    // the scheme well enough on its own.
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// The monospace face for keys, IDs and record names — anything a person might
/// compare character by character.
const nkMono = TextStyle(fontFamily: 'monospace');
