import 'package:flutter/material.dart';

/// Палитра приложения.
///
/// Все цвета собраны в одном месте, чтобы в будущем поддержать «реколор» —
/// подмену палитры на лету (тема/скин). Пока используется единственная
/// «ночная» палитра [night] (natsukashi yoru — «ностальгическая ночь»).
class AppColors {
  const AppColors({
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.onBackground,
    required this.onSurface,
    required this.onPrimary,
  });

  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color onBackground;
  final Color onSurface;
  final Color onPrimary;

  /// Базовая «ночная» палитра.
  static const AppColors night = AppColors(
    background: Color(0xFF0E0B1A),
    surface: Color(0xFF1B1530),
    primary: Color(0xFF7C5CFF),
    secondary: Color(0xFFFF6FAE),
    accent: Color(0xFF4ECDC4),
    onBackground: Color(0xFFEDEAFB),
    onSurface: Color(0xFFEDEAFB),
    onPrimary: Color(0xFFFFFFFF),
  );

  /// Заготовка под реколор: вернуть копию палитры с заменёнными цветами.
  /// Реальная реализация скинов — в следующих итерациях.
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? primary,
    Color? secondary,
    Color? accent,
    Color? onBackground,
    Color? onSurface,
    Color? onPrimary,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      accent: accent ?? this.accent,
      onBackground: onBackground ?? this.onBackground,
      onSurface: onSurface ?? this.onSurface,
      onPrimary: onPrimary ?? this.onPrimary,
    );
  }
}
