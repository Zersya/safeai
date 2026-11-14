import 'package:flutter/material.dart';

import '../checking/models.dart';

const seedColor = Color(0xFF1B7F3B);

class VerdictStyle {
  const VerdictStyle(this.color, this.icon);
  final Color color;
  final IconData icon;

  static VerdictStyle of(Verdict v) => switch (v) {
        Verdict.safe => const VerdictStyle(Color(0xFF1B7F3B), Icons.verified_user),
        Verdict.suspicious => const VerdictStyle(Color(0xFFB26A00), Icons.warning_amber_rounded),
        Verdict.dangerous => const VerdictStyle(Color(0xFFC62828), Icons.gpp_bad),
        Verdict.unchecked => const VerdictStyle(Color(0xFF546E7A), Icons.help_outline),
      };
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
  );
  final t = base.textTheme;
  const buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)));
  const buttonText = TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
  return base.copyWith(
    textTheme: t.copyWith(
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 20),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 18),
      titleLarge: t.titleLarge?.copyWith(fontSize: 26),
      headlineMedium: t.headlineMedium?.copyWith(fontSize: 30),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: buttonText,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 80,
      labelTextStyle: WidgetStatePropertyAll(
        base.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
  );
}
