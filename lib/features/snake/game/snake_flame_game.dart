import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/snake_logic.dart';

/// Состояние партии — управляет тем, какой оверлей показан.
enum SnakePhase { ready, running, dead }

/// Flame-игра «Snake» с упором на «сок»: частицы при еде, тряска и вспышка
/// при смерти, всплывающие очки, комбо за быструю еду и разгон скорости.
///
/// Чистая механика — в [SnakeLogic]; здесь только тайминг, ввод, рендер и фидбек.
class SnakeFlameGame extends FlameGame {
  SnakeFlameGame({
    required this.onGameOver,
    this.cols = 15,
    this.rows = 25,
    this.bottomInset = 28,
  });

  /// Вызывается при смерти со счётом партии (для рекордов/оверлея).
  final void Function(int score) onGameOver;
  final int cols;
  final int rows;

  /// Резерв снизу под экранные контролы (крестовина/джойстик). Мал для жестов,
  /// большой для пада — задаёт экран-хост по выбранной схеме.
  final double bottomInset;

  late final SnakeLogic _logic = SnakeLogic(cols: cols, rows: rows);
  final Random _rng = Random();

  // Наблюдаемое для оверлеев/HUD.
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> combo = ValueNotifier(0);
  final ValueNotifier<int> length = ValueNotifier(3);
  final ValueNotifier<double> speed = ValueNotifier(1);
  final ValueNotifier<double> fps = ValueNotifier(0);
  final ValueNotifier<SnakePhase> phase = ValueNotifier(SnakePhase.ready);
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  bool get _running => phase.value == SnakePhase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  // Тайминг шага: старт спокойнее, разгон мягче (фидбек: «уровень 1 быстроват»).
  double _acc = 0;
  static const double _baseStep = 0.2;
  static const double _minStep = 0.09;

  // Резерв сверху под HUD (счёт + перенесённая наверх строка статистики).
  static const double _topInset = 128;

  // Комбо.
  double _sinceEat = 0;
  static const double _comboWindow = 2.2;

  // Эффекты.
  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  double _shake = 0;
  double _flash = 0;
  double _foodPulse = 0;

  // Сглаженный FPS для отладочного индикатора.
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  // Геометрия поля (считается в render по текущему размеру).
  double _cell = 0;
  Offset _origin = Offset.zero;

  double get _stepInterval =>
      max(_minStep, _baseStep - _logic.length * 0.0018);

  void start() {
    _logic.reset();
    score.value = 0;
    combo.value = 0;
    length.value = _logic.length;
    speed.value = 1;
    _acc = 0;
    _sinceEat = 0;
    _sparks.clear();
    _popups.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = SnakePhase.running;
  }

  void steer(Direction d) {
    if (_active) {
      _logic.steer(d);
      Haptics.select();
    }
  }

  /// Относительный поворот: [clockwise] — вправо (по часовой), иначе влево.
  /// Крутим от уже введённого направления, чтобы быстрые повороты копились.
  void turn(bool clockwise) {
    final d = _logic.intendedDirection;
    steer(clockwise ? _rotateCw(d) : _rotateCcw(d));
  }

  static Direction _rotateCw(Direction d) => switch (d) {
        Direction.up => Direction.right,
        Direction.right => Direction.down,
        Direction.down => Direction.left,
        Direction.left => Direction.up,
      };

  static Direction _rotateCcw(Direction d) => switch (d) {
        Direction.up => Direction.left,
        Direction.left => Direction.down,
        Direction.down => Direction.right,
        Direction.right => Direction.up,
      };

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

    _foodPulse = (_foodPulse + dt * 4) % (2 * pi);
    _advanceEffects(dt);

    if (!_active) return;

    _sinceEat += dt;
    _acc += dt;
    while (_acc >= _stepInterval) {
      _acc -= _stepInterval;
      _tick();
      if (phase.value != SnakePhase.running) break;
    }
  }

  void _tick() {
    final outcome = _logic.step();
    switch (outcome) {
      case StepOutcome.moved:
        break;
      case StepOutcome.ate:
        _onEat();
      case StepOutcome.died:
        _onDeath();
    }
  }

  void _onEat() {
    combo.value = _sinceEat <= _comboWindow ? combo.value + 1 : 1;
    _sinceEat = 0;
    final gain = combo.value;
    score.value += gain;
    length.value = _logic.length;
    speed.value = _baseStep / _stepInterval;

    _spawnBurst(_logic.head, gain);
    _popups.add(_Popup(cell: _logic.head, text: '+$gain', combo: combo.value));
    _foodPulse = 0;

    if (combo.value >= 2) {
      Haptics.combo(combo.value); // особый нарастающий паттерн на комбо
    } else {
      Haptics.light();
    }
  }

  void _onDeath() {
    _shake = 1;
    _flash = 1;
    Haptics.heavy();
    // Сначала отдать счёт (экран посчитает рекорд и обновит данные оверлея),
    // затем сменить фазу — оверлей построится уже с верными цифрами.
    onGameOver(score.value);
    phase.value = SnakePhase.dead;
  }

  // ── Эффекты ────────────────────────────────────────────────────────────

  void _spawnBurst(Point<int> cell, int strength) {
    final count = 10 + strength * 4;
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 60 + _rng.nextDouble() * 140;
      _sparks.add(_Spark(
        cell: cell,
        vel: Offset(cos(a), sin(a)) * speed,
        life: 0.4 + _rng.nextDouble() * 0.4,
        hue: 150 + _rng.nextDouble() * 60, // зелёно-бирюзовые искры
      ));
    }
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.5);
    _flash = max(0, _flash - dt * 1.8);

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = s.vel * (1 - 2.5 * dt); // трение
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);

    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= _Popup.duration);
  }

  // ── Рендер ───────────────────────────────────────────────────────────────

  @override
  Color backgroundColor() => const Color(0xFF0E0B1A);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _computeGeometry();

    // Тряска экрана.
    if (_shake > 0) {
      final m = _shake * _shake * 10;
      canvas.save();
      canvas.translate(
        (_rng.nextDouble() * 2 - 1) * m,
        (_rng.nextDouble() * 2 - 1) * m,
      );
    }

    _drawBoard(canvas);
    _drawFood(canvas);
    _drawSnake(canvas);
    _drawSparks(canvas);
    _drawPopups(canvas);

    if (_shake > 0) canvas.restore();

    // Вспышка смерти поверх всего.
    if (_flash > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = const Color(0xFFFF5370).withValues(alpha: _flash * 0.5),
      );
    }
  }

  void _computeGeometry() {
    final availH = size.y - _topInset - bottomInset;
    _cell = min(size.x / cols, availH / rows);
    final w = _cell * cols;
    final h = _cell * rows;
    _origin = Offset((size.x - w) / 2, _topInset + (availH - h) / 2);
  }

  Offset _cellCenter(Point<int> c) => _origin +
      Offset((c.x + 0.5) * _cell, (c.y + 0.5) * _cell);

  void _drawBoard(Canvas canvas) {
    final w = _cell * cols;
    final h = _cell * rows;
    final rect = RRect.fromRectAndRadius(
      _origin & Size(w, h),
      Radius.circular(_cell * 0.4),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF161126));

    // Тонкая сетка для глубины.
    final grid = Paint()
      ..color = const Color(0xFF221A3A)
      ..strokeWidth = 1;
    for (var x = 1; x < cols; x++) {
      final px = _origin.dx + x * _cell;
      canvas.drawLine(Offset(px, _origin.dy), Offset(px, _origin.dy + h), grid);
    }
    for (var y = 1; y < rows; y++) {
      final py = _origin.dy + y * _cell;
      canvas.drawLine(Offset(_origin.dx, py), Offset(_origin.dx + w, py), grid);
    }
  }

  void _drawFood(Canvas canvas) {
    final center = _cellCenter(_logic.food);
    final pulse = 0.5 + 0.5 * sin(_foodPulse);
    final r = _cell * (0.32 + 0.06 * pulse);

    // Свечение.
    canvas.drawCircle(
      center,
      r * 2.4,
      Paint()
        ..color = const Color(0xFFFF6FAE).withValues(alpha: 0.18 + 0.12 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFFFF6FAE));
    canvas.drawCircle(
      center - Offset(r * 0.3, r * 0.3),
      r * 0.35,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  void _drawSnake(Canvas canvas) {
    final body = _logic.snake;
    for (var i = body.length - 1; i >= 0; i--) {
      final isHead = i == 0;
      final center = _cellCenter(body[i]);
      final t = body.length == 1 ? 1.0 : 1 - i / body.length;
      final size = _cell * (isHead ? 0.92 : 0.62 + 0.28 * t);

      final color = Color.lerp(
        const Color(0xFF4ECDC4),
        const Color(0xFF7C5CFF),
        t,
      )!;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: size, height: size),
        Radius.circular(size * 0.32),
      );

      if (isHead) {
        canvas.drawRRect(
          rrect.inflate(2),
          Paint()
            ..color = color.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawRRect(rrect, Paint()..color = color);

      if (isHead) _drawEyes(canvas, center, size);
    }
  }

  void _drawEyes(Canvas canvas, Offset center, double s) {
    final d = _logic.direction.delta;
    final fwd = Offset(d.x.toDouble(), d.y.toDouble());
    final side = Offset(-fwd.dy, fwd.dx);
    final eyeOff = s * 0.2;
    final r = s * 0.1;
    for (final sgn in [-1.0, 1.0]) {
      final p = center + fwd * (s * 0.18) + side * (eyeOff * sgn);
      canvas.drawCircle(p, r, Paint()..color = Colors.white);
      canvas.drawCircle(
        p + fwd * (r * 0.4),
        r * 0.5,
        Paint()..color = const Color(0xFF0E0B1A),
      );
    }
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      final center = _cellCenter(s.cell) + s.pos;
      canvas.drawCircle(
        center,
        _cell * 0.12 * k,
        Paint()
          ..color = HSVColor.fromAHSV(k, s.hue, 0.7, 1).toColor(),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final center = _cellCenter(p.cell) - Offset(0, _cell * (0.5 + k * 1.5));
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = 1 + (p.combo >= 3 ? 0.5 : 0.2) * (1 - k);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: (p.combo >= 3 ? const Color(0xFFFFD54F) : Colors.white)
                .withValues(alpha: alpha),
            fontSize: _cell * 0.7 * scale,
            fontWeight: FontWeight.w800,
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
    required this.cell,
    required this.vel,
    required this.life,
    required this.hue,
  });
  final Point<int> cell;
  Offset pos = Offset.zero;
  Offset vel;
  final double life;
  final double hue;
  double age = 0;
}

class _Popup {
  _Popup({required this.cell, required this.text, required this.combo});
  static const double duration = 0.9;
  final Point<int> cell;
  final String text;
  final int combo;
  double age = 0;
}
