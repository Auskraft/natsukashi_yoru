import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Сборка [ThemeData] из палитры [AppColors].
///
/// Вынесено отдельно, чтобы реколор сводился к подмене [AppColors] —
/// см. [AppColors.night] и `copyWith`.
class AppTheme {
  const AppTheme._();

  static ThemeData fromColors(AppColors c) {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.secondary,
      onSecondary: c.onPrimary,
      tertiary: c.accent,
      onTertiary: c.onPrimary,
      error: const Color(0xFFFF5370),
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.onBackground,
        centerTitle: true,
        elevation: 0,
      ),
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: c.onBackground,
        displayColor: c.onBackground,
      ),
    );
  }

  /// Тема по умолчанию — «ночная».
  static ThemeData get night => fromColors(AppColors.night);
}
