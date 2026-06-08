import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/bejeweled_logic.dart';

enum BejeweledPhase { ready, running, dead }

/// Цвет камня по индексу (0..5) в палитре проекта.
Color bejeweledColor(int color) {
  const palette = [
    Color(0xFFFF5370), // 0
    Color(0xFFFF9F45), // 1
    Color(0xFFFFD54F), // 2
    Color(0xFF5CE08A), // 3
    Color(0xFF4ECDC4), // 4
    Color(0xFF7C5CFF), // 5
  ];
  return palette[color % palette.length];
}

/// Flame-игра «Bejeweled»: свайп-обмен соседних камней, особые камни
/// (матч-4 — линейный, матч-5 — цвет-бомба) и каскады. Режим — бюджет из
/// 25 ходов: каждый удачный обмен тратит ход, ради рекорда и ретеншна.
class BejeweledFlameGame extends FlameGame {
  BejeweledFlameGame({required this.onGameOver});

  final void Function(int score) onGameOver;

  final BejeweledLogic _logic = BejeweledLogic();
  final Random _rng = Random();

  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> combo = ValueNotifier(0);
  final ValueNotifier<int> movesLeft = ValueNotifier(_startMoves);
  final ValueNotifier<BejeweledPhase> phase = ValueNotifier(BejeweledPhase.ready);
  final ValueNotifier<double> fps = ValueNotifier(0);

  static const int _startMoves = 25;

  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  double _shake = 0;
  double _flash = 0;
  double _pulse = 0;
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  static const double _topInset = 128;
  static const double _bottomInset = 36;
  double _cell = 0;
  Offset _origin = Offset.zero;

  bool get _running => phase.value == BejeweledPhase.running;

  void start() {
    _logic.reset();
    score.value = 0;
    combo.value = 0;
    movesLeft.value = _startMoves;
    _sparks.clear();
    _popups.clear();
    _shake = 0;
    _flash = 0;
    phase.value = BejeweledPhase.running;
  }

  Point<int>? cellAt(Offset local) {
    if (_cell <= 0) return null;
    final gx = ((local.dx - _origin.dx) / _cell).floor();
    final gy = ((local.dy - _origin.dy) / _cell).floor();
    if (gx < 0 || gy < 0 || gx >= _logic.cols || gy >= _logic.rows) return null;
    return Point(gx, gy);
  }

  void trySwapCells(Point<int> a, Point<int> b) {
    if (!_running) return;
    final res = _logic.trySwap(a, b);
    score.value = _logic.score;

    if (!res.swapped) {
      if (res.reverted) {
        _shake = max(_shake, 0.22);
        Haptics.light();
      }
      combo.value = 0;
      return;
    }

    movesLeft.value -= 1;
    combo.value = res.cascadeLength;

    var total = 0;
    for (final step in res.steps) {
      for (final c in step.cleared) {
        _spawnBurst(c.pos.x + 0.5, c.pos.y + 0.5, bejeweledColor(c.color));
        total++;
      }
      for (final cs in step.created) {
        _spawnBurst(cs.pos.x + 0.5, cs.pos.y + 0.5, Colors.white, strong: true);
      }
    }
    _shake = max(_shake, 0.3 + total * 0.02);
    _flash = max(_flash, res.cascadeLength >= 3 ? 0.3 : 0.12);
    _popups.add(_Popup(
      gridX: a.x + 0.5,
      gridY: a.y + 0.5,
      text: '+${res.gained}',
      color: Colors.white,
      big: res.cascadeLength >= 3,
    ));
    if (res.cascadeLength >= 2) {
      _popups.add(_Popup(
        gridX: _logic.cols / 2,
        gridY: _logic.rows / 2,
        text: 'x${res.cascadeLength} CHAIN',
        color: const Color(0xFFFFD54F),
        big: true,
      ));
      Haptics.combo(res.cascadeLength);
    } else {
      Haptics.medium();
    }

    if (movesLeft.value <= 0 || res.gameOver) {
      movesLeft.value = max(0, movesLeft.value);
      phase.value = BejeweledPhase.dead;
      _flash = max(_flash, 0.4);
      Haptics.heavy();
      onGameOver(score.value);
    }
  }

  void _spawnBurst(double gx, double gy, Color color, {bool strong = false}) {
    final count = strong ? 14 : 7;
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 60 + _rng.nextDouble() * (strong ? 220 : 150);
      _sparks.add(_Spark(
        gridX: gx,
        gridY: gy,
        vel: Offset(cos(a), sin(a)) * speed,
        life: 0.35 + _rng.nextDouble() * 0.4,
        color: color,
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse = (_pulse + dt * 4) % (2 * pi);

    _fpsFrames++;
    _fpsAcc += dt;
    if (_fpsAcc >= 0.5) {
      fps.value = _fpsFrames / _fpsAcc;
      _fpsFrames = 0;
      _fpsAcc = 0;
    }

    _shake = max(0, _shake - dt * 2.4);
    _flash = max(0, _flash - dt * 1.8);
    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = s.vel * (1 - 2.4 * dt);
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);
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
      final m = _shake * _shake * 9;
      canvas.save();
      canvas.translate(
        (_rng.nextDouble() * 2 - 1) * m,
        (_rng.nextDouble() * 2 - 1) * m,
      );
    }

    _drawBoard(canvas);
    _drawGems(canvas);
    _drawSparks(canvas);
    _drawPopups(canvas);

    if (_shake > 0) canvas.restore();

    if (_flash > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = Colors.white.withValues(alpha: _flash * 0.35),
      );
    }
  }

  void _computeGeometry() {
    final availH = size.y - _topInset - _bottomInset;
    _cell = min(size.x / _logic.cols, availH / _logic.rows);
    final w = _cell * _logic.cols;
    final h = _cell * _logic.rows;
    _origin = Offset((size.x - w) / 2, _topInset + (availH - h) / 2);
  }

  Offset _point(double gx, double gy) =>
      _origin + Offset(gx * _cell, gy * _cell);

  void _drawBoard(Canvas canvas) {
    final w = _cell * _logic.cols;
    final h = _cell * _logic.rows;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (_origin & Size(w, h)).inflate(_cell * 0.12),
        Radius.circular(_cell * 0.3),
      ),
      Paint()..color = const Color(0xFF161126),
    );
  }

  void _drawGems(Canvas canvas) {
    for (var y = 0; y < _logic.rows; y++) {
      for (var x = 0; x < _logic.cols; x++) {
        final gem = _logic.board[y][x];
        final color = bejeweledColor(gem.color);
        final rect = Rect.fromLTWH(
          _origin.dx + x * _cell,
          _origin.dy + y * _cell,
          _cell,
          _cell,
        ).deflate(_cell * 0.1);
        final rrect =
            RRect.fromRectAndRadius(rect, Radius.circular(_cell * 0.28));
        canvas.drawRRect(rrect, Paint()..color = color);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.34),
            Radius.circular(_cell * 0.28),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.2),
        );
        if (gem.isSpecial) _drawSpecial(canvas, rect, gem.special);
      }
    }
  }

  void _drawSpecial(Canvas canvas, Rect rect, Special s) {
    final glow = 0.5 + 0.5 * sin(_pulse);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55 + 0.35 * glow)
      ..strokeWidth = rect.width * 0.09
      ..style = PaintingStyle.stroke;
    switch (s) {
      case Special.none:
        break;
      case Special.lineH:
        canvas.drawLine(
          Offset(rect.left, rect.center.dy),
          Offset(rect.right, rect.center.dy),
          paint,
        );
      case Special.lineV:
        canvas.drawLine(
          Offset(rect.center.dx, rect.top),
          Offset(rect.center.dx, rect.bottom),
          paint,
        );
      case Special.colorBomb:
        canvas.drawCircle(rect.center, rect.width * 0.3, paint);
        canvas.drawCircle(
          rect.center,
          rect.width * 0.12,
          Paint()..color = Colors.white.withValues(alpha: 0.8 * glow),
        );
    }
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      canvas.drawCircle(
        _point(s.gridX, s.gridY) + s.pos,
        _cell * 0.14 * k,
        Paint()..color = s.color.withValues(alpha: k),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = (p.big ? 1.0 : 0.7) * (1 + 0.3 * (1 - k));
      final center = _point(p.gridX, p.gridY) - Offset(0, k * _cell * 1.6);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(alpha: alpha),
            fontSize: _cell * scale,
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

class _Popup {
  _Popup({
    required this.gridX,
    required this.gridY,
    required this.text,
    required this.color,
    this.big = false,
  });
  static const double duration = 1.0;
  final double gridX;
  final double gridY;
  final String text;
  final Color color;
  final bool big;
  double age = 0;
}
