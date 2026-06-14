import 'package:flutter/material.dart';

import '../feedback/haptics.dart';
import '../input/control_scheme.dart';

/// Экранные контролы (крестовина / джойстик) для направленных игр.
///
/// Игро-независимы: выдают [PadDir] через `onDir`; конкретная игра сама
/// сопоставляет его со своим направлением (см. Snake `_dirOf`). Стиль — «ночной
/// неон», как у оверлеев. Логику игр не трогают — лишь второй источник ввода.

/// Раскладка кнопочной крестовины.
enum DpadLayout {
  /// Крестовина по центру (4 стрелки).
  cross,

  /// Раздельно: вверх/вниз слева, влево/вправо справа.
  splitLeft,

  /// Раздельно: вверх/вниз справа, влево/вправо слева.
  splitRight,
}

/// Обёртка: по [scheme] показывает нужный контрол (или ничего для жестов).
/// Размещать внизу `Stack` экрана игры; [visible] плавно гасит контрол на паузе.
class ControlOverlay extends StatelessWidget {
  const ControlOverlay({
    super.key,
    required this.scheme,
    required this.onDir,
    this.onTurn,
    this.accent = const Color(0xFF7C5CFF),
    this.visible = true,
  });

  final ControlScheme scheme;
  final ValueChanged<PadDir> onDir;

  /// Для относительной схемы [ControlScheme.turnButtons]: true — по часовой
  /// (вправо), false — против (влево).
  final ValueChanged<bool>? onTurn;
  final Color accent;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    // Жесты и наклон не имеют экранного контрола.
    if (scheme == ControlScheme.gestures || scheme == ControlScheme.gyro) {
      return const SizedBox.shrink();
    }

    final Widget control = switch (scheme) {
      ControlScheme.dpad =>
        DirectionPad(onDir: onDir, accent: accent, layout: DpadLayout.cross),
      ControlScheme.dpadSplitLeft => DirectionPad(
          onDir: onDir, accent: accent, layout: DpadLayout.splitLeft),
      ControlScheme.dpadSplitRight => DirectionPad(
          onDir: onDir, accent: accent, layout: DpadLayout.splitRight),
      ControlScheme.joystick => FloatingJoystick(onDir: onDir, accent: accent),
      ControlScheme.turnButtons =>
        TurnPad(onTurn: onTurn ?? (_) {}, accent: accent),
      ControlScheme.gestures ||
      ControlScheme.gyro ||
      ControlScheme.tetrisButtons =>
        const SizedBox.shrink(),
    };

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: control,
          ),
        ),
      ),
    );
  }
}

/// Кнопочная крестовина в одной из раскладок [DpadLayout].
class DirectionPad extends StatelessWidget {
  const DirectionPad({
    super.key,
    required this.onDir,
    required this.accent,
    this.layout = DpadLayout.cross,
  });

  final ValueChanged<PadDir> onDir;
  final Color accent;
  final DpadLayout layout;

  Widget _btn(IconData icon, PadDir dir) =>
      _PadButton(icon: icon, accent: accent, onPressed: () => onDir(dir));

  Widget get _vertical => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.keyboard_arrow_up_rounded, PadDir.up),
          const SizedBox(height: 14),
          _btn(Icons.keyboard_arrow_down_rounded, PadDir.down),
        ],
      );

  Widget get _horizontal => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.keyboard_arrow_left_rounded, PadDir.left),
          const SizedBox(width: 14),
          _btn(Icons.keyboard_arrow_right_rounded, PadDir.right),
        ],
      );

  @override
  Widget build(BuildContext context) {
    switch (layout) {
      case DpadLayout.cross:
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 164,
            height: 164,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: _btn(Icons.keyboard_arrow_up_rounded, PadDir.up),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _btn(Icons.keyboard_arrow_down_rounded, PadDir.down),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _btn(Icons.keyboard_arrow_left_rounded, PadDir.left),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _btn(Icons.keyboard_arrow_right_rounded, PadDir.right),
                ),
              ],
            ),
          ),
        );
      case DpadLayout.splitLeft:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [_vertical, _horizontal],
        );
      case DpadLayout.splitRight:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [_horizontal, _vertical],
        );
    }
  }
}

/// Круглая кнопка: действие сразу на нажатие (onTapDown) + хаптика, со сжатием
/// и подсветкой акцентом.
class _PadButton extends StatefulWidget {
  const _PadButton({
    required this.icon,
    required this.accent,
    required this.onPressed,
    this.size = 58,
  });

  final IconData icon;
  final Color accent;
  final VoidCallback onPressed;
  final double size;

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
          width: widget.size,
          height: widget.size,
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
            size: widget.size * 0.52,
          ),
        ),
      ),
    );
  }
}

/// Две кнопки относительного поворота: ◄ влево / ► вправо относительно курса.
/// Для игр с «направлением движения» (Snake). [onTurn] true = по часовой.
class TurnPad extends StatelessWidget {
  const TurnPad({super.key, required this.onTurn, required this.accent});

  final ValueChanged<bool> onTurn;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _PadButton(
          icon: Icons.rotate_left_rounded,
          accent: accent,
          size: 78,
          onPressed: () => onTurn(false),
        ),
        _PadButton(
          icon: Icons.rotate_right_rounded,
          accent: accent,
          size: 78,
          onPressed: () => onTurn(true),
        ),
      ],
    );
  }
}

/// Обёртка контролов для игр с падающими фигурами (Tetris/Puyo): по [scheme]
/// показывает [TetrisPad] (схема `tetrisButtons`) или ничего (жесты).
class TetrisControls extends StatelessWidget {
  const TetrisControls({
    super.key,
    required this.scheme,
    required this.onLeft,
    required this.onRight,
    required this.onRotate,
    required this.onDrop,
    this.accent = const Color(0xFF7C5CFF),
    this.visible = true,
  });

  final ControlScheme scheme;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onRotate;
  final VoidCallback onDrop;
  final Color accent;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (scheme != ControlScheme.tetrisButtons) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TetrisPad(
              onLeft: onLeft,
              onRight: onRight,
              onRotate: onRotate,
              onDrop: onDrop,
              accent: accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Пад для падающих фигур: слева ◄ ►, справа поворот и сброс.
class TetrisPad extends StatelessWidget {
  const TetrisPad({
    super.key,
    required this.onLeft,
    required this.onRight,
    required this.onRotate,
    required this.onDrop,
    required this.accent,
  });

  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onRotate;
  final VoidCallback onDrop;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PadButton(
              icon: Icons.keyboard_arrow_left_rounded,
              accent: accent,
              size: 64,
              onPressed: onLeft,
            ),
            const SizedBox(width: 12),
            _PadButton(
              icon: Icons.keyboard_arrow_right_rounded,
              accent: accent,
              size: 64,
              onPressed: onRight,
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PadButton(
              icon: Icons.rotate_right_rounded,
              accent: accent,
              size: 64,
              onPressed: onRotate,
            ),
            const SizedBox(width: 12),
            _PadButton(
              icon: Icons.keyboard_double_arrow_down_rounded,
              accent: accent,
              size: 64,
              onPressed: onDrop,
            ),
          ],
        ),
      ],
    );
  }
}

const double _kJoyRadius = 62;
const double _kKnob = 54;

/// Плавающий джойстик: зажми и веди. Выдаёт доминирующее направление при его
/// смене (с мёртвой зоной), шар тянется за пальцем и возвращается в центр.
class FloatingJoystick extends StatefulWidget {
  const FloatingJoystick({
    super.key,
    required this.onDir,
    required this.accent,
  });

  final ValueChanged<PadDir> onDir;
  final Color accent;

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
    if (dir != _last) {
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
