import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/whack_a_mole_logic.dart';

/// Состояние партии — управляет тем, какой оверлей показан.
enum WhackPhase { ready, running, dead }

/// Flame-игра «Whack-a-Mole» в режиме 30-секундного блица: кроты вылезают из
/// нор 3×3 на короткое время, тап по «вылезшему» = попадание (+очки ×комбо),
/// тап по пустой норе = промах (сброс комбо). Темп появления растёт со временем.
///
/// Чистая механика (спавн/попадание/комбо) — в [WhackAMoleLogic]; здесь только
/// таймер партии, ввод, рендер и «сок»: «бам»-частицы и попап на попадании,
/// лёгкая тряска на промахе, акцент-вспышка в конце, комбо-хаптика.
class WhackaMoleFlameGame extends FlameGame {
  WhackaMoleFlameGame({required this.onGameOver});

  /// Вызывается в конце блица со счётом партии (для рекордов/оверлея).
  final void Function(int score) onGameOver;

  final WhackAMoleLogic _logic = WhackAMoleLogic();
  final Random _rng = Random();

  // Наблюдаемое для оверлеев/HUD.
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> combo = ValueNotifier(0);
  final ValueNotifier<int> hits = ValueNotifier(0);
  final ValueNotifier<double> timeLeft = ValueNotifier(_roundTime);
  final ValueNotifier<WhackPhase> phase = ValueNotifier(WhackPhase.ready);
  final ValueNotifier<double> fps = ValueNotifier(0);
  // ВАЖНО: имя именно isPaused — у FlameGame уже есть свой member `paused`.
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  static const double _roundTime = 30;

  bool get _running => phase.value == WhackPhase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  // Эффекты.
  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  // Анимация «вылезания»/«прятания» крота по норам (0 — в норе, 1 — наверху).
  late final List<double> _pop = List.filled(_logic.count, 0);
  double _shake = 0;
  double _flash = 0;
  Color _flashColor = Colors.white;
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  // Геометрия: запас сверху под HUD (счёт/рекорд/таймер), снизу — под подпись.
  static const double _topInset = 150;
  static const double _bottomInset = 40;
  double _cell = 0;
  Offset _origin = Offset.zero;

  int get cols => _logic.cols;
  int get rows => _logic.rows;

  void start() {
    _logic.reset();
    score.value = 0;
    combo.value = 0;
    hits.value = 0;
    timeLeft.value = _roundTime;
    _sparks.clear();
    _popups.clear();
    for (var i = 0; i < _pop.length; i++) {
      _pop[i] = 0;
    }
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = WhackPhase.running;
  }

  /// Перевод точки касания в индекс норы (или null вне поля/вне нор).
  int? holeAt(Offset local) {
    if (_cell <= 0) return null;
    final gx = ((local.dx - _origin.dx) / _cell).floor();
    final gy = ((local.dy - _origin.dy) / _cell).floor();
    if (gx < 0 || gy < 0 || gx >= cols || gy >= rows) return null;
    return gy * cols + gx;
  }

  /// Удар по норе под точкой касания. Гардится через [_active].
  void whackAt(Offset local) {
    if (!_active) return;
    final index = holeAt(local);
    if (index == null) return;
    _whack(index);
  }

  void _whack(int index) {
    final res = _logic.hit(index);
    if (res.ignored) return;

    final center = _holeCenter(index);

    if (res.hit) {
      score.value += res.gained;
      combo.value = res.combo;
      hits.value = _logic.hits;

      _spawnBurst(center, res.combo);
      _popups.add(_Popup(
        pos: center,
        text: '+${res.gained}',
        big: res.combo >= 3,
      ));
      _flash = max(_flash, res.combo >= 3 ? 0.22 : 0.1);

      if (res.combo >= 2) {
        Haptics.combo(res.combo);
      } else {
        Haptics.medium();
      }
    } else {
      // Промах по пустой норе: серия прервана, лёгкая тряска.
      combo.value = 0;
      _shake = max(_shake, 0.28);
      _popups.add(_Popup(
        pos: center,
        text: 'мимо',
        big: false,
        color: const Color(0xFFFF5370),
      ));
      Haptics.light();
    }
  }

  void _spawnBurst(Offset pos, int strength) {
    final n = 10 + strength * 4;
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 70 + _rng.nextDouble() * 170;
      _sparks.add(_Spark(
        pos: pos,
        vel: Offset(cos(a), sin(a)) * speed,
        life: 0.35 + _rng.nextDouble() * 0.45,
        color: strength >= 3 ? const Color(0xFFFFD54F) : const Color(0xFFFF9F45),
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

    _advanceEffects(dt);

    if (!_active) return;

    // Прогрессия партии: сначала таймер блица, затем симуляция нор.
    timeLeft.value -= dt;
    if (timeLeft.value <= 0) {
      timeLeft.value = 0;
      _onTimeUp();
      return;
    }

    final events = _logic.tick(dt);
    if (events.isNotEmpty) {
      // Зевок (крот спрятался сам) ломает комбо — отразим в HUD.
      combo.value = _logic.combo;
      for (final e in events) {
        if (e.change == HoleChange.popUp) {
          Haptics.select();
        }
      }
    }
  }

  void _onTimeUp() {
    _flash = max(_flash, 0.45);
    _flashColor = const Color(0xFFFF9F45);
    _shake = max(_shake, 0.4);
    Haptics.heavy();
    // Сначала отдать счёт (экран посчитает рекорд), затем сменить фазу.
    onGameOver(score.value);
    phase.value = WhackPhase.dead;
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.4);
    _flash = max(0, _flash - dt * 1.8);

    // Плавная анимация крота к целевой высоте (наверху/в норе).
    for (var i = 0; i < _pop.length; i++) {
      final target = _logic.holes[i].up ? 1.0 : 0.0;
      final speed = target > _pop[i] ? 12.0 : 9.0; // вылезает резче, прячется мягче
      _pop[i] += (target - _pop[i]).clamp(-speed * dt, speed * dt);
    }

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.4 * dt), s.vel.dy + 320 * dt);
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);

    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= _Popup.duration);
  }

  // ── Рендер ─────────────────────────────────────────────────────────────────

  @override
  Color backgroundColor() => const Color(0xFF0E0B1A);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _computeGeometry();

    if (_shake > 0) {
      final m = _shake * _shake * 9;
      canvas.save();
      canvas.translate(
        (_rng.nextDouble() * 2 - 1) * m,
        (_rng.nextDouble() * 2 - 1) * m,
      );
    }

    _drawHoles(canvas);
    _drawSparks(canvas);
    _drawPopups(canvas);

    if (_shake > 0) canvas.restore();

    if (_flash > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = _flashColor.withValues(alpha: _flash * 0.4),
      );
    }
  }

  void _computeGeometry() {
    final availH = size.y - _topInset - _bottomInset;
    _cell = min(size.x / cols, availH / rows);
    final w = _cell * cols;
    final h = _cell * rows;
    _origin = Offset((size.x - w) / 2, _topInset + (availH - h) / 2);
  }

  Offset _holeCenter(int index) {
    final gx = index % cols;
    final gy = index ~/ cols;
    return _origin + Offset((gx + 0.5) * _cell, (gy + 0.5) * _cell);
  }

  void _drawHoles(Canvas canvas) {
    for (var i = 0; i < _logic.count; i++) {
      final center = _holeCenter(i);
      final r = _cell * 0.34;
      // Передняя кромка норы — линия, из-за которой «выезжает» крот.
      final holeLineY = center.dy + r * 0.4;
      final holeW = r * 2.1;

      // Задняя стенка норы (тёмный овал) — видна над линией.
      final backRect = Rect.fromCenter(
        center: Offset(center.dx, holeLineY),
        width: holeW,
        height: r * 1.2,
      );
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, size.x, holeLineY));
      canvas.drawOval(backRect, Paint()..color = const Color(0xFF0B0816));
      canvas.restore();

      final pop = _pop[i].clamp(0.0, 1.0);
      if (pop > 0.01) {
        _drawMole(canvas, center.dx, holeLineY, r, pop);
      }

      // Передний бортик норы поверх крота — создаёт эффект «вылезания».
      final lip = Rect.fromCenter(
        center: Offset(center.dx, holeLineY),
        width: holeW,
        height: r * 0.7,
      );
      canvas.drawArc(lip, 0, pi, true, Paint()..color = const Color(0xFF1B1530));
      canvas.drawArc(
        lip,
        0,
        pi,
        false,
        Paint()
          ..color = const Color(0xFF2A2147)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.1,
      );
    }
  }

  /// Крот выезжает снизу вверх из линии норы [holeLineY]; рисуем его обрезанным
  /// сверху по этой линии (видна только вылезшая часть).
  void _drawMole(Canvas canvas, double cx, double holeLineY, double r,
      double pop) {
    final rise = r * 1.25;
    // pop=0 — центр на линии (скрыт); pop=1 — центр на [rise] выше (виден весь).
    final body = Offset(cx, holeLineY - pop * rise);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.x, holeLineY));

    final bodyR = r * 0.9;
    // Тело.
    canvas.drawCircle(body, bodyR, Paint()..color = const Color(0xFF8C6E5C));
    // Мордочка светлее.
    canvas.drawCircle(
      body + Offset(0, bodyR * 0.2),
      bodyR * 0.6,
      Paint()..color = const Color(0xFFC9A98F),
    );
    // Глаза.
    final eyeDx = bodyR * 0.32;
    final eyeY = body - Offset(0, bodyR * 0.22);
    for (final sgn in [-1.0, 1.0]) {
      final p = eyeY + Offset(eyeDx * sgn, 0);
      canvas.drawCircle(p, bodyR * 0.13, Paint()..color = Colors.white);
      canvas.drawCircle(
        p + Offset(0, bodyR * 0.02),
        bodyR * 0.06,
        Paint()..color = const Color(0xFF0E0B1A),
      );
    }
    // Нос.
    canvas.drawCircle(
      body + Offset(0, bodyR * 0.18),
      bodyR * 0.1,
      Paint()..color = const Color(0xFFFF6FAE),
    );

    canvas.restore();
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      canvas.drawCircle(
        s.pos,
        _cell * 0.12 * k,
        Paint()..color = s.color.withValues(alpha: k),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = (p.big ? 1.0 : 0.75) * (1 + 0.3 * (1 - k));
      final center = p.pos - Offset(0, k * _cell * 1.4);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(alpha: alpha),
            fontSize: _cell * 0.5 * scale,
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
    required this.pos,
    required this.vel,
    required this.life,
    required this.color,
  });
  Offset pos;
  Offset vel;
  final double life;
  final Color color;
  double age = 0;
}

class _Popup {
  _Popup({
    required this.pos,
    required this.text,
    this.big = false,
    this.color = Colors.white,
  });
  static const double duration = 0.85;
  final Offset pos;
  final String text;
  final bool big;
  final Color color;
  double age = 0;
}
