import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/puyo_puyo_logic.dart';

enum PuyoPhase { ready, running, dead }

/// Цвет пуйо по индексу (0..3).
Color puyoColor(int color) {
  const palette = [
    Color(0xFFFF5370), // red
    Color(0xFF5CE08A), // green
    Color(0xFF4ECDC4), // blue
    Color(0xFFFFD54F), // yellow
  ];
  return palette[color % palette.length];
}

/// Flame-игра «Puyo Puyo»: падающая пара шариков, группы 4+ лопаются,
/// цепочки дают растущий множитель. Управление как в Tetris: тап — поворот,
/// тяга — сдвиг, свайп вниз — hard drop.
class PuyoPuyoFlameGame extends FlameGame {
  PuyoPuyoFlameGame({required this.onGameOver, this.bottomInset = 40});

  final void Function(int score) onGameOver;

  /// Резерв снизу под экранные контролы (задаёт экран-хост по схеме).
  final double bottomInset;

  final PuyoPuyoLogic _logic = PuyoPuyoLogic();
  final Random _rng = Random();

  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> chain = ValueNotifier(0);
  final ValueNotifier<List<int>> next = ValueNotifier(const [0, 0]);
  final ValueNotifier<PuyoPhase> phase = ValueNotifier(PuyoPhase.ready);
  final ValueNotifier<double> fps = ValueNotifier(0);
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  double _acc = 0;
  static const double _gravity = 0.5;

  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  double _shake = 0;
  double _flash = 0;
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  static const double _topInset = 136;
  double _cell = 0;
  Offset _origin = Offset.zero;
  double get cellSize => _cell;

  bool get _running => phase.value == PuyoPhase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  void start() {
    _logic.reset();
    score.value = 0;
    chain.value = 0;
    next.value = List<int>.from(_logic.next);
    _acc = 0;
    _sparks.clear();
    _popups.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = PuyoPhase.running;
  }

  void moveLeft() {
    if (_active && _logic.moveLeft()) Haptics.select();
  }

  void moveRight() {
    if (_active && _logic.moveRight()) Haptics.select();
  }

  void rotate() {
    if (_active && _logic.rotateCW()) Haptics.light();
  }

  void hardDrop() {
    if (!_active) return;
    final res = _logic.hardDrop();
    _shake = max(_shake, 0.35);
    Haptics.medium();
    if (res != null) _onLock(res);
  }

  void softDrop() {
    if (!_active) return;
    final res = _logic.softDrop();
    score.value = _logic.score;
    if (res != null) _onLock(res);
  }

  void _onLock(PuyoLockResult res) {
    score.value = _logic.score;
    next.value = List<int>.from(_logic.next);

    if (res.waves.isNotEmpty) {
      var total = 0;
      for (final w in res.waves) {
        for (final cell in w.popped) {
          _spawnBurst(cell.x + 0.5, cell.y + 0.5, puyoColor(cell.color));
          total++;
        }
      }
      final chainLen = res.chainLength;
      chain.value = chainLen;
      _shake = max(_shake, 0.35 + total * 0.02 + chainLen * 0.1);
      _flash = max(_flash, chainLen >= 3 ? 0.4 : 0.15);
      _popups.add(_Popup(
        gridX: PuyoPuyoLogic.cols / 2,
        gridY: PuyoPuyoLogic.rows / 2,
        text: chainLen >= 2 ? '$chainLen-CHAIN!\n+${res.gained}' : '+${res.gained}',
        color: chainLen >= 2 ? const Color(0xFFFFD54F) : Colors.white,
        big: chainLen >= 2,
      ));
      if (chainLen >= 2) {
        Haptics.combo(chainLen);
      } else {
        Haptics.medium();
      }
    } else {
      chain.value = 0;
    }

    if (res.gameOver) {
      phase.value = PuyoPhase.dead;
      _shake = 1;
      _flash = max(_flash, 0.5);
      Haptics.heavy();
      onGameOver(score.value);
    }
  }

  void _spawnBurst(double gx, double gy, Color color) {
    for (var i = 0; i < 9; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 60 + _rng.nextDouble() * 170;
      _sparks.add(_Spark(
        gridX: gx,
        gridY: gy,
        vel: Offset(cos(a), sin(a)) * speed,
        life: 0.4 + _rng.nextDouble() * 0.4,
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

    _advanceEffects(dt);
    if (!_active) return;

    _acc += dt;
    while (_acc >= _gravity) {
      _acc -= _gravity;
      final res = _logic.gravityTick();
      if (res != null) _onLock(res);
      if (!_running) break;
    }
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.2);
    _flash = max(0, _flash - dt * 1.8);
    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.4 * dt), s.vel.dy + 300 * dt);
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

    _drawWell(canvas);
    _drawStack(canvas);
    if (_running) _drawPair(canvas);
    _drawSparks(canvas);
    _drawPopups(canvas);

    if (_shake > 0) canvas.restore();

    if (_flash > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = Colors.white.withValues(alpha: _flash * 0.32),
      );
    }
  }

  void _computeGeometry() {
    final c = buildContext;
    final safeTop = c == null ? 0.0 : (MediaQuery.maybeOf(c)?.padding.top ?? 0.0);
    final top = _topInset + safeTop;
    final availH = size.y - top - bottomInset;
    _cell = min(size.x / (PuyoPuyoLogic.cols + 1), availH / PuyoPuyoLogic.rows);
    final w = _cell * PuyoPuyoLogic.cols;
    final h = _cell * PuyoPuyoLogic.rows;
    _origin = Offset((size.x - w) / 2, top + (availH - h) / 2);
  }

  Offset _center(double gx, double gy) =>
      _origin + Offset((gx + 0.5) * _cell, (gy + 0.5) * _cell);

  void _drawWell(Canvas canvas) {
    final w = _cell * PuyoPuyoLogic.cols;
    final h = _cell * PuyoPuyoLogic.rows;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (_origin & Size(w, h)).inflate(_cell * 0.14),
        Radius.circular(_cell * 0.3),
      ),
      Paint()..color = const Color(0xFF161126),
    );
  }

  void _drawPuyo(Canvas canvas, double gx, double gy, Color color,
      {double alpha = 1}) {
    final c = _center(gx, gy);
    final r = _cell * 0.44;
    canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: alpha));
    // Глянцевый блик.
    canvas.drawCircle(
      c - Offset(r * 0.3, r * 0.35),
      r * 0.3,
      Paint()..color = Colors.white.withValues(alpha: 0.45 * alpha),
    );
  }

  void _drawStack(Canvas canvas) {
    for (var y = 0; y < PuyoPuyoLogic.rows; y++) {
      for (var x = 0; x < PuyoPuyoLogic.cols; x++) {
        final c = _logic.board[y][x];
        if (c != null) _drawPuyo(canvas, x.toDouble(), y.toDouble(), puyoColor(c));
      }
    }
  }

  void _drawPair(Canvas canvas) {
    final p = _logic.current;
    if (p == null) return;
    if (p.axisY >= 0) {
      _drawPuyo(canvas, p.axisX.toDouble(), p.axisY.toDouble(),
          puyoColor(p.axisColor));
    }
    final s = p.satellite;
    if (s.y >= 0) {
      _drawPuyo(canvas, s.x.toDouble(), s.y.toDouble(),
          puyoColor(p.satelliteColor));
    }
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      canvas.drawCircle(
        _center(s.gridX - 0.5, s.gridY - 0.5) + s.pos,
        _cell * 0.16 * k,
        Paint()..color = s.color.withValues(alpha: k),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = (p.big ? 1.0 : 0.7) * (1 + 0.3 * (1 - k));
      final center = _center(p.gridX - 0.5, p.gridY - 0.5) -
          Offset(0, k * _cell * 1.6);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(alpha: alpha),
            fontSize: _cell * 0.7 * scale,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        textAlign: TextAlign.center,
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
  static const double duration = 1.1;
  final double gridX;
  final double gridY;
  final String text;
  final Color color;
  final bool big;
  double age = 0;
}
