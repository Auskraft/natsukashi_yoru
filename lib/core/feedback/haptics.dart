import 'dart:async';

import 'package:flutter/services.dart';

/// Тактильная отдача на игровые события — дешёвый, но мощный источник
/// «сока» и ощущения отклика на телефоне.
///
/// Единая точка, чтобы позже добавить общий флаг отключения вибрации.
class Haptics {
  const Haptics._();

  static bool enabled = true;

  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  static void select() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// Особый «комбо»-паттерн: очередь импульсов с финальным тяжёлым акцентом
  /// («та-та-ДАМ»). Чем выше [level], тем длиннее очередь — комбо ощущается
  /// телом иначе, чем обычное событие.
  static void combo(int level) {
    if (!enabled) return;
    unawaited(_comboPattern(level.clamp(2, 5)));
  }

  static Future<void> _comboPattern(int pulses) async {
    for (var i = 0; i < pulses; i++) {
      if (i == pulses - 1) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
      if (i < pulses - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 55));
      }
    }
  }
}
