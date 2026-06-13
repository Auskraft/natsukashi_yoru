import 'package:flutter/material.dart';

/// Дискретный 4-направленный D-pad + кнопка огня для аркадных игр (танки).
///
/// Не свободный стик: направление фиксируется, пока кнопка зажата, и сбрасывается
/// при отпускании. Мультитач (держать направление + жать огонь) — через [Listener]
/// (сырые указатели): D-pad и огонь — две независимые зоны, поэтому одновременное
/// нажатие работает. Использует [AxisDirection] (тип Flutter), чтобы `core/` не
/// зависел от фич; экран-хост маппит его в игровое направление.
class DpadControl extends StatefulWidget {
  const DpadControl({
    super.key,
    required this.onDirection,
    required this.onFireChanged,
    this.accent = const Color(0xFF4ECDC4),
  });

  /// Текущее зажатое направление (null — отпущено).
  final ValueChanged<AxisDirection?> onDirection;

  /// Зажата (true) либо отпущена (false) кнопка огня.
  final ValueChanged<bool> onFireChanged;

  final Color accent;

  @override
  State<DpadControl> createState() => _DpadControlState();
}

class _DpadControlState extends State<DpadControl> {
  AxisDirection? _dir;
  bool _firing = false;

  void _press(AxisDirection d) {
    if (_dir == d) return;
    setState(() => _dir = d);
    widget.onDirection(d);
  }

  void _release(AxisDirection d) {
    if (_dir != d) return;
    setState(() => _dir = null);
    widget.onDirection(null);
  }

  void _fire(bool on) {
    if (_firing == on) return;
    setState(() => _firing = on);
    widget.onFireChanged(on);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [_buildDpad(), _buildFire()],
      ),
    );
  }

  Widget _buildDpad() {
    const cell = 50.0;
    return SizedBox(
      width: cell * 3,
      height: cell * 3,
      child: Stack(
        children: [
          Positioned(
              left: cell,
              top: 0,
              child: _dirButton(AxisDirection.up, Icons.keyboard_arrow_up, cell)),
          Positioned(
              left: cell,
              bottom: 0,
              child:
                  _dirButton(AxisDirection.down, Icons.keyboard_arrow_down, cell)),
          Positioned(
              left: 0,
              top: cell,
              child:
                  _dirButton(AxisDirection.left, Icons.keyboard_arrow_left, cell)),
          Positioned(
              right: 0,
              top: cell,
              child: _dirButton(
                  AxisDirection.right, Icons.keyboard_arrow_right, cell)),
        ],
      ),
    );
  }

  Widget _dirButton(AxisDirection d, IconData icon, double size) {
    final active = _dir == d;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _press(d),
      onPointerUp: (_) => _release(d),
      onPointerCancel: (_) => _release(d),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active
              ? widget.accent.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Icon(
          icon,
          color: active ? Colors.black : Colors.white.withValues(alpha: 0.7),
          size: 30,
        ),
      ),
    );
  }

  Widget _buildFire() {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _fire(true),
      onPointerUp: (_) => _fire(false),
      onPointerCancel: (_) => _fire(false),
      child: AnimatedScale(
        scale: _firing ? 0.92 : 1,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [widget.accent, const Color(0xFF7C5CFF)],
            ),
            boxShadow: [
              BoxShadow(color: widget.accent.withValues(alpha: 0.5), blurRadius: 18),
            ],
          ),
          child: const Icon(Icons.bolt, color: Colors.white, size: 42),
        ),
      ),
    );
  }
}
