import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF14122B);
  static const surface = Color(0xFF1F1B3F);
  static const surfaceHigh = Color(0xFF2A2552);
  static const textPrimary = Color(0xFFF5F3FF);
  static const textMuted = Color(0xFFA9A3D1);
  static const danger = Color(0xFFFF5C6C);
  static const success = Color(0xFF3DD6A3);
}

abstract final class AppTheme {
  static ThemeData build(Color accent) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      primary: accent,
      surface: AppColors.surface,
      error: AppColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(56, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.surfaceHigh),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.surface),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
