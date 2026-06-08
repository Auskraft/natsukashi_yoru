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
}
