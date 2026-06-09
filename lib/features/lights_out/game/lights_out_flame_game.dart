import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/lights_out_logic.dart';

/// Состояние партии — управляет тем, какой оверлей показан.
enum LightsOutPhase { ready, running, won }

/// Flame-игра «Lights Out» с упором на «сок»: тап инвертирует крест из лампочек
/// со вспышкой затронутых клеток, при победе — салют и вспышка экрана.
///
/// Чистая механика — в [LightsOutLogic]; здесь только ввод, рендер и фидбек.
/// «Лучшее» — МЕНЬШЕ ходов (партия меряется счётчиком ходов).
class LightsOutFlameGame extends FlameGame {
  LightsOutFlameGame({required this.onWin, this.gridSize = 5});

  /// Вызывается при победе с числом сделанных ходов (меньше — лучше).
  final void Function(int moves) onWin;

  /// Сторона квадратного поля.
  final int gridSize;

  late LightsOutLogic _logic = LightsOutLogic(size: gridSize);
  final Random _rng = Random();

  // Наблюдаемое для HUD/оверлеев.
  final ValueNotifier<int> moves = ValueNotifier(0);
  final ValueNotifier<int> lit = ValueNotifier(0);
  final ValueNotifier<LightsOutPhase> phase =
      ValueNotifier(LightsOutPhase.ready);
  final ValueNotifier<double> fps = ValueNotifier(0);

  // ВАЖНО: у FlameGame есть свой `paused`, поэтому свой нотифаер паузы
  // называем именно isPaused, чтобы не конфликтовать с членом базового класса.
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  bool get _running => phase.value == LightsOutPhase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  // Резерв сверху под HUD и снизу под подсказку, чтобы поле не налезало
  // на оверлеи.
  static const double _topInset = 116;
  static const double _bottomInset = 48;

  // Эффекты «сока».
  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  final List<_Pulse> _pulses = [];
  double _shake = 0;
  double _flash = 0;
  Color _flashColor = Colors.white;
  double _glow = 0; // мягкая фоновая пульсация горящих клеток

  // Сглаженный FPS для отладочного индикатора.
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  // Геометрия поля (считается в render по текущему размеру).
  double _cell = 0;
  Offset _origin = Offset.zero;

  void start() {
    _logic = LightsOutLogic(size: gridSize, random: _rng);
    moves.value = 0;
    lit.value = _logic.litCount;
    _sparks.clear();
    _popups.clear();
    _pulses.clear();
    _shake = 0;
    _flash = 0;
    _glow = 0;
    isPaused.value = false;
    phase.value = LightsOutPhase.running;
  }

  /// Координаты клетки под локальной точкой тача или null вне поля.
  Point<int>? cellAt(Offset local) {
    if (_cell <= 0) return null;
    final gx = ((local.dx - _origin.dx) / _cell).floor();
    final gy = ((local.dy - _origin.dy) / _cell).floor();
    if (gx < 0 || gy < 0 || gx >= gridSize || gy >= gridSize) return null;
    return Point(gx, gy);
  }

  /// Тап по полю: переключает крест, обновляет HUD и проверяет победу.
  void tapAt(Offset local) {
    if (!_active) return;
    final p = cellAt(local);
    if (p == null) return;
    final res = _logic.tap(p.x, p.y);
    if (!res.applied) return;

    moves.value = _logic.moves;
    lit.value = _logic.litCount;

    for (final c in res.toggled) {
      _pulses.add(_Pulse(c.x, c.y, c.on));
    }

    if (res.won) {
      _onWin();
    } else {
      Haptics.light();
    }
  }

  void _onWin() {
    _flash = 0.6;
    _flashColor = const Color(0xFFA78BFA);
    for (var i = 0; i < 64; i++) {
      _spawnBurst(
        _rng.nextInt(gridSize) + 0.5,
        _rng.nextInt(gridSize) + 0.5,
        _confetti(),
        count: 1,
      );
    }
    _popups.add(_Popup(
      gridX: gridSize / 2,
      gridY: gridSize / 2,
      text: '${_logic.moves} ходов',
    ));
    _shake = max(_shake, 0.4);
    // Сначала отдать результат (экран посчитает рекорд и обновит оверлей),
    // затем сменить фазу — оверлей построится уже с верными цифрами.
    Haptics.heavy();
    onWin(_logic.moves);
    phase.value = LightsOutPhase.won;
  }

  Color _confetti() {
    const palette = [
      Color(0xFFA78BFA),
      Color(0xFFFF6FAE),
      Color(0xFFFFD54F),
      Color(0xFF4ECDC4),
      Color(0xFF5CE08A),
    ];
    return palette[_rng.nextInt(palette.length)];
  }

  void _spawnBurst(double gx, double gy, Color color, {int count = 6}) {
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 50 + _rng.nextDouble() * 180;
      _sparks.add(_Spark(
        gridX: gx,
        gridY: gy,
        vel: Offset(cos(a), sin(a)) * speed,
        life: 0.4 + _rng.nextDouble() * 0.5,
        color: color,
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    _fpsFrames++;
    _fpsAcc += dt;
    if (_fpsAcc >= 0.5) {
      fps.value = _fpsFrames / _fpsAcc;
      _fpsFrames = 0;
      _fpsAcc = 0;
    }

    _glow = (_glow + dt * 3) % (2 * pi);
    _advanceEffects(dt);

    if (!_active) return;
    // Партия чисто пошаговая — постоянной прогрессии нет; геймплейная логика
    // целиком в обработчике тапа. Здесь после гарда могла бы жить физика/таймер.
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.2);
    _flash = max(0, _flash - dt * 1.6);

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.2 * dt), s.vel.dy + 300 * dt);
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);

    for (final p in _pulses) {
      p.age += dt;
    }
    _pulses.removeWhere((p) => p.age >= _Pulse.duration);

    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= _Popup.duration);
  }

  @override
  Color backgroundColor() => const Color(0xFF0E0B1A);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _computeGeometry();

    if (_shake > 0) {
      final m = _shake * _shake * 10;
      canvas.save();
      canvas.translate(
        (_rng.nextDouble() * 2 - 1) * m,
        (_rng.nextDouble() * 2 - 1) * m,
      );
    }

    _drawCells(canvas);
    _drawPulses(canvas);
    _drawSparks(canvas);
    _drawPopups(canvas);

    if (_shake > 0) canvas.restore();

    if (_flash > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = _flashColor.withValues(alpha: _flash * 0.45),
      );
    }
  }

  void _computeGeometry() {
    final availH = size.y - _topInset - _bottomInset;
    _cell = min(size.x / gridSize, availH / gridSize);
    final side = _cell * gridSize;
    _origin = Offset(
      (size.x - side) / 2,
      _topInset + (availH - side) / 2,
    );
  }

  Rect _rect(int x, int y) => Rect.fromLTWH(
        _origin.dx + x * _cell,
        _origin.dy + y * _cell,
        _cell,
        _cell,
      );

  Offset _center(double gx, double gy) =>
      _origin + Offset(gx * _cell, gy * _cell);

  static const Color _onColor = Color(0xFFA78BFA);
  static const Color _offColor = Color(0xFF1B1530);

  void _drawCells(Canvas canvas) {
    final pulse = 0.5 + 0.5 * sin(_glow);
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final on = _logic.grid[y][x];
        final rect = _rect(x, y).deflate(_cell * 0.06);
        final rrect =
            RRect.fromRectAndRadius(rect, Radius.circular(_cell * 0.22));

        if (on) {
          // Свечение горящей лампочки.
          canvas.drawRRect(
            rrect.inflate(_cell * 0.04),
            Paint()
              ..color = _onColor.withValues(alpha: 0.25 + 0.15 * pulse)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
          );
          canvas.drawRRect(rrect, Paint()..color = _onColor);
          // Блик.
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  rect.left, rect.top, rect.width, rect.height * 0.42),
              Radius.circular(_cell * 0.22),
            ),
            Paint()..color = Colors.white.withValues(alpha: 0.22),
          );
        } else {
          canvas.drawRRect(rrect, Paint()..color = _offColor);
          canvas.drawRRect(
            rrect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = _cell * 0.02
              ..color = Colors.white.withValues(alpha: 0.05),
          );
        }
      }
    }
  }

  /// Вспышка переключённых клеток: белая при зажигании, тёмная при гашении.
  void _drawPulses(Canvas canvas) {
    for (final p in _pulses) {
      final k = 1 - p.age / _Pulse.duration;
      final base = p.on ? Colors.white : const Color(0xFF0E0B1A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _rect(p.x, p.y).deflate(_cell * 0.06),
          Radius.circular(_cell * 0.22),
        ),
        Paint()..color = base.withValues(alpha: k * 0.55),
      );
    }
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      canvas.drawCircle(
        _center(s.gridX, s.gridY) + s.pos,
        _cell * 0.13 * k,
        Paint()..color = s.color.withValues(alpha: k),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final center = _center(p.gridX, p.gridY) - Offset(0, _cell * k * 1.2);
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = 1 + 0.4 * (1 - k);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: const Color(0xFFFFD54F).withValues(alpha: alpha),
            fontSize: _cell * 0.45 * scale,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }
}

class _Spark {
  _Spark({
    required this.gridX,
    required this.gridY,
    required this.vel,
    required this.life,
    required this.color,
  });
  final double gridX;
  final double gridY;
  Offset pos = Offset.zero;
  Offset vel;
  final double life;
  final Color color;
  double age = 0;
}

/// Кратковременная вспышка переключённой клетки.
class _Pulse {
  _Pulse(this.x, this.y, this.on);
  static const double duration = 0.35;
  final int x;
  final int y;
  final bool on;
  double age = 0;
}

class _Popup {
  _Popup({required this.gridX, required this.gridY, required this.text});
  static const double duration = 1.1;
  final double gridX;
  final double gridY;
  final String text;
  double age = 0;
}
