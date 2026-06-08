import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/minesweeper_logic.dart';

enum MinesweeperPhase { ready, running, won, lost }

/// Flame-«Сапёр»: тап раскрывает клетку (флуд-филл на нуле), лонг-пресс ставит
/// флаг. Сок: «вспышка» раскрытия, взрыв с тряской при подрыве, салют на победе.
class MinesweeperFlameGame extends FlameGame {
  MinesweeperFlameGame({required this.onOver});

  /// Вызывается в конце партии: победа? и время в секундах.
  final void Function(bool won, int seconds) onOver;

  static const int cols = 9;
  static const int rows = 12;
  static const int mineCount = 16;

  late MinesweeperLogic _logic = MinesweeperLogic(cols, rows, mineCount);
  final Random _rng = Random();

  final ValueNotifier<int> minesLeft = ValueNotifier(mineCount);
  final ValueNotifier<int> timeSec = ValueNotifier(0);
  final ValueNotifier<MinesweeperPhase> phase =
      ValueNotifier(MinesweeperPhase.ready);
  final ValueNotifier<double> fps = ValueNotifier(0);

  double _time = 0;

  final List<_Spark> _sparks = [];
  final List<_Reveal> _reveals = [];
  double _shake = 0;
  double _flash = 0;
  Color _flashColor = Colors.white;
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  static const double _topInset = 100;
  static const double _bottomInset = 32;
  double _cell = 0;
  Offset _origin = Offset.zero;

  bool get _running => phase.value == MinesweeperPhase.running;

  void start() {
    _logic = MinesweeperLogic(cols, rows, mineCount, random: _rng);
    minesLeft.value = mineCount;
    timeSec.value = 0;
    _time = 0;
    _sparks.clear();
    _reveals.clear();
    _shake = 0;
    _flash = 0;
    phase.value = MinesweeperPhase.running;
  }

  Point<int>? cellAt(Offset local) {
    if (_cell <= 0) return null;
    final gx = ((local.dx - _origin.dx) / _cell).floor();
    final gy = ((local.dy - _origin.dy) / _cell).floor();
    if (gx < 0 || gy < 0 || gx >= cols || gy >= rows) return null;
    return Point(gx, gy);
  }

  void revealAt(Offset local) {
    if (!_running) return;
    final p = cellAt(local);
    if (p == null) return;
    final res = _logic.reveal(p.x, p.y);
    if (res.revealed.isEmpty && !res.hitMine) return;

    for (final c in res.revealed) {
      _reveals.add(_Reveal(c.x, c.y));
    }

    if (res.hitMine) {
      _shake = 1;
      _flash = 0.7;
      _flashColor = const Color(0xFFFF5370);
      for (final m in res.explodedMines) {
        _spawnBurst(m.x + 0.5, m.y + 0.5, const Color(0xFFFF5370), count: 8);
      }
      Haptics.heavy();
      phase.value = MinesweeperPhase.lost;
      onOver(false, timeSec.value);
      return;
    }

    if (res.cascade >= 6) {
      _shake = max(_shake, 0.25);
    }
    Haptics.light();

    if (res.won) {
      _flash = 0.5;
      _flashColor = const Color(0xFF5CE08A);
      for (var i = 0; i < 60; i++) {
        _spawnBurst(_rng.nextInt(cols) + 0.5, _rng.nextInt(rows) + 0.5,
            _confetti(), count: 1);
      }
      Haptics.combo(5);
      phase.value = MinesweeperPhase.won;
      onOver(true, timeSec.value);
    }
  }

  void flagAt(Offset local) {
    if (!_running) return;
    final p = cellAt(local);
    if (p == null) return;
    if (_logic.toggleFlag(p.x, p.y)) {
      minesLeft.value = _logic.remainingMines;
      Haptics.select();
    }
  }

  Color _confetti() {
    const palette = [
      Color(0xFFFF6FAE),
      Color(0xFFFFD54F),
      Color(0xFF4ECDC4),
      Color(0xFF7C5CFF),
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

    if (_running) {
      _time += dt;
      final s = _time.floor();
      if (s != timeSec.value) timeSec.value = s;
    }

    _shake = max(0, _shake - dt * 2.2);
    _flash = max(0, _flash - dt * 1.6);
    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.2 * dt), s.vel.dy + 300 * dt);
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);
    for (final r in _reveals) {
      r.age += dt;
    }
    _reveals.removeWhere((r) => r.age >= _Reveal.duration);
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
    _drawReveals(canvas);
    _drawSparks(canvas);

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
    _cell = min(size.x / cols, availH / rows);
    final w = _cell * cols;
    final h = _cell * rows;
    _origin = Offset((size.x - w) / 2, _topInset + (availH - h) / 2);
  }

  Rect _rect(int x, int y) => Rect.fromLTWH(
        _origin.dx + x * _cell,
        _origin.dy + y * _cell,
        _cell,
        _cell,
      );

  Offset _center(double gx, double gy) =>
      _origin + Offset(gx * _cell, gy * _cell);

  void _drawCells(Canvas canvas) {
    final revealAll = phase.value == MinesweeperPhase.lost;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final cell = _logic.board[y][x];
        final rect = _rect(x, y).deflate(_cell * 0.04);
        final rrect =
            RRect.fromRectAndRadius(rect, Radius.circular(_cell * 0.18));

        final revealed = cell.state == CellState.revealed ||
            (revealAll && cell.mine);

        if (!revealed) {
          // Скрытая/флаг — «выпуклая» плитка.
          canvas.drawRRect(rrect, Paint()..color = const Color(0xFF2A2147));
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  rect.left, rect.top, rect.width, rect.height * 0.4),
              Radius.circular(_cell * 0.18),
            ),
            Paint()..color = Colors.white.withValues(alpha: 0.08),
          );
          if (cell.state == CellState.flagged) _drawFlag(canvas, rect);
        } else {
          canvas.drawRRect(rrect, Paint()..color = const Color(0xFF161126));
          if (cell.mine) {
            _drawMine(canvas, rect);
          } else if (cell.adjacent > 0) {
            _drawNumber(canvas, rect, cell.adjacent);
          }
        }
      }
    }
  }

  void _drawFlag(Canvas canvas, Rect rect) {
    final c = rect.center;
    final h = rect.height * 0.3;
    final pole = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = rect.width * 0.06;
    canvas.drawLine(Offset(c.dx, c.dy - h), Offset(c.dx, c.dy + h), pole);
    final flag = Path()
      ..moveTo(c.dx, c.dy - h)
      ..lineTo(c.dx + rect.width * 0.26, c.dy - h * 0.5)
      ..lineTo(c.dx, c.dy)
      ..close();
    canvas.drawPath(flag, Paint()..color = const Color(0xFFFF5370));
  }

  void _drawMine(Canvas canvas, Rect rect) {
    final c = rect.center;
    final r = rect.width * 0.26;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFF5370));
    canvas.drawCircle(
      c - Offset(r * 0.3, r * 0.3),
      r * 0.35,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  static const List<Color> _numColors = [
    Color(0xFF5C9CFF), // 1
    Color(0xFF5CE08A), // 2
    Color(0xFFFF5370), // 3
    Color(0xFFB388FF), // 4
    Color(0xFFFF9F45), // 5
    Color(0xFF4ECDC4), // 6
    Color(0xFFFFD54F), // 7
    Color(0xFFBBBBBB), // 8
  ];

  void _drawNumber(Canvas canvas, Rect rect, int n) {
    final tp = TextPainter(
      text: TextSpan(
        text: '$n',
        style: TextStyle(
          color: _numColors[(n - 1).clamp(0, 7)],
          fontSize: _cell * 0.6,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawReveals(Canvas canvas) {
    for (final r in _reveals) {
      final k = 1 - r.age / _Reveal.duration;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _rect(r.x, r.y).deflate(_cell * 0.04),
          Radius.circular(_cell * 0.18),
        ),
        Paint()..color = Colors.white.withValues(alpha: k * 0.5),
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

class _Reveal {
  _Reveal(this.x, this.y);
  static const double duration = 0.3;
  final int x;
  final int y;
  double age = 0;
}
