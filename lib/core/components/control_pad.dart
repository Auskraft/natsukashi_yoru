import 'package:flutter/material.dart';

import '../feedback/haptics.dart';
import '../input/control_scheme.dart';

/// Экранные контролы (крестовина / джойстик) для направленных игр.
///
/// Игро-независимы: выдают [PadDir] через `onDir`; конкретная игра сама
/// сопоставляет его со своим направлением (см. Snake `_dirOf`). Стиль — «ночной
/// неон», как у оверлеев. Логику игр не трогают — лишь второй источник ввода.

const List<PadDir> _all4 = [PadDir.up, PadDir.down, PadDir.left, PadDir.right];

/// Обёртка: по [scheme] показывает нужный контрол (или ничего для жестов).
/// Размещать внизу `Stack` экрана игры; [visible] — управляет показом (пауза и
/// т.п.) с плавным затуханием.
class ControlOverlay extends StatelessWidget {
  const ControlOverlay({
    super.key,
    required this.scheme,
    required this.onDir,
    this.accent = const Color(0xFF7C5CFF),
    this.dirs = _all4,
    this.visible = true,
  });

  final ControlScheme scheme;
  final ValueChanged<PadDir> onDir;
  final Color accent;
  final List<PadDir> dirs;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (scheme == ControlScheme.gestures) return const SizedBox.shrink();

    final control = scheme == ControlScheme.dpad
        ? DirectionPad(onDir: onDir, accent: accent, dirs: dirs)
        : FloatingJoystick(onDir: onDir, accent: accent, dirs: dirs);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: control,
          ),
        ),
      ),
    );
  }
}

/// Крестовина из 4 кнопок (показываются только направления из [dirs]).
class DirectionPad extends StatelessWidget {
  const DirectionPad({
    super.key,
    required this.onDir,
    required this.accent,
    this.dirs = _all4,
  });

  final ValueChanged<PadDir> onDir;
  final Color accent;
  final List<PadDir> dirs;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: 172,
        height: 172,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (dirs.contains(PadDir.up))
              Align(
                alignment: Alignment.topCenter,
                child: _PadButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  accent: accent,
                  onPressed: () => onDir(PadDir.up),
                ),
              ),
            if (dirs.contains(PadDir.down))
              Align(
                alignment: Alignment.bottomCenter,
                child: _PadButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  accent: accent,
                  onPressed: () => onDir(PadDir.down),
                ),
              ),
            if (dirs.contains(PadDir.left))
              Align(
                alignment: Alignment.centerLeft,
                child: _PadButton(
                  icon: Icons.keyboard_arrow_left_rounded,
                  accent: accent,
                  onPressed: () => onDir(PadDir.left),
                ),
              ),
            if (dirs.contains(PadDir.right))
              Align(
                alignment: Alignment.centerRight,
                child: _PadButton(
                  icon: Icons.keyboard_arrow_right_rounded,
                  accent: accent,
                  onPressed: () => onDir(PadDir.right),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Круглая кнопка крестовины: нажатие даёт действие сразу (onTapDown) + хаптику,
/// со сжатием и подсветкой акцентом.
class _PadButton extends StatefulWidget {
  const _PadButton({
    required this.icon,
    required this.accent,
    required this.onPressed,
  });

  final IconData icon;
  final Color accent;
  final VoidCallback onPressed;

  @override
  State<_PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<_PadButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _down = true);
        Haptics.select();
        widget.onPressed();
      },
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _down
                ? widget.accent.withValues(alpha: 0.28)
                : const Color(0x14FFFFFF),
            border: Border.all(
              color: _down ? widget.accent : const Color(0x22FFFFFF),
              width: 1.5,
            ),
            boxShadow: _down
                ? [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.5),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            widget.icon,
            color: _down ? Colors.white : widget.accent,
            size: 30,
          ),
        ),
      ),
    );
  }
}

const double _kJoyRadius = 62;
const double _kKnob = 54;

/// Плавающий джойстик: зажми и веди. Выдаёт доминирующее направление из [dirs]
/// при его смене (с мёртвой зоной), шар тянется за пальцем и возвращается в
/// центр при отпускании.
class FloatingJoystick extends StatefulWidget {
  const FloatingJoystick({
    super.key,
    required this.onDir,
    required this.accent,
    this.dirs = _all4,
  });

  final ValueChanged<PadDir> onDir;
  final Color accent;
  final List<PadDir> dirs;

  @override
  State<FloatingJoystick> createState() => _FloatingJoystickState();
}

class _FloatingJoystickState extends State<FloatingJoystick> {
  static const double _side = _kJoyRadius * 2 + 28;
  Offset _knob = Offset.zero;
  PadDir? _last;

  void _drive(Offset local) {
    const center = Offset(_side / 2, _side / 2);
    var v = local - center;
    final dist = v.distance;
    if (dist > _kJoyRadius) v = v / dist * _kJoyRadius;
    setState(() => _knob = v);

    if (dist < _kJoyRadius * 0.4) {
      _last = null; // мёртвая зона
      return;
    }
    final dir = v.dx.abs() > v.dy.abs()
        ? (v.dx > 0 ? PadDir.right : PadDir.left)
        : (v.dy > 0 ? PadDir.down : PadDir.up);
    if (widget.dirs.contains(dir) && dir != _last) {
      _last = dir;
      Haptics.select();
      widget.onDir(dir);
    }
  }

  void _reset() {
    setState(() {
      _knob = Offset.zero;
      _last = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => _drive(d.localPosition),
        onPanUpdate: (d) => _drive(d.localPosition),
        onPanEnd: (_) => _reset(),
        onPanCancel: _reset,
        child: SizedBox(
          width: _side,
          height: _side,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: _kJoyRadius * 2,
                height: _kJoyRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x10FFFFFF),
                  border: Border.all(color: const Color(0x22FFFFFF), width: 1.5),
                ),
              ),
              Transform.translate(
                offset: _knob,
                child: Container(
                  width: _kKnob,
                  height: _kKnob,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.accent.withValues(alpha: 0.85),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accent.withValues(alpha: 0.5),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.control_camera_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
