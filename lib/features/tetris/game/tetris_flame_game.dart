import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/tetris_logic.dart';
import '../ui/tetris_style.dart';

/// Фаза партии — управляет показываемым оверлеем.
enum TetrisPhase { ready, running, dead }

/// Flame-игра «Tetris» с упором на «сок»: сжигание линий со вспышкой и
/// частицами, slam-эффект при hard drop, фигура-призрак, разгон по уровням,
/// всплывающие очки и особая хаптика на комбо/Тетрис.
class TetrisFlameGame extends FlameGame {
  TetrisFlameGame({required this.onGameOver});

  final void Function(int score) onGameOver;

  final TetrisLogic _logic = TetrisLogic();
  final Random _rng = Random();

  // Наблюдаемое для HUD/оверлеев.
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> level = ValueNotifier(1);
  final ValueNotifier<int> lines = ValueNotifier(0);
  final ValueNotifier<int> combo = ValueNotifier(0);
  final ValueNotifier<Tetromino> next = ValueNotifier(Tetromino.i);
  final ValueNotifier<TetrisPhase> phase = ValueNotifier(TetrisPhase.ready);
  final ValueNotifier<double> fps = ValueNotifier(0);
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  int _clearCombo = 0;

  // Гравитация.
  double _acc = 0;
  double get _gravityInterval => max(0.07, 0.85 * pow(0.85, level.value - 1));

  // Геометрия поля.
  static const double _topInset = 124;
  static const double _bottomInset = 44;
  double _cell = 0;
  Offset _origin = Offset.zero;
  double get cellSize => _cell;

  // Эффекты.
  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  final List<_RowFlash> _rowFlashes = [];
  double _shake = 0;
  double _flash = 0;

  // FPS.
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  // ── Управление состоянием ────────────────────────────────────────────────

  void start() {
    _logic.reset();
    score.value = 0;
    level.value = 1;
    lines.value = 0;
    combo.value = 0;
    _clearCombo = 0;
    next.value = _logic.next;
    _acc = 0;
    _sparks.clear();
    _popups.clear();
    _rowFlashes.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = TetrisPhase.running;
  }

  // ── Ввод (вызывается экраном) ────────────────────────────────────────────

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
    final landing = _logic.ghost().cells();
    final res = _logic.hardDrop();
    _shake = max(_shake, 0.45);
    _spawnImpact(landing);
    Haptics.medium();
    _onLock(res);
  }

  void softDrop() {
    if (!_active) return;
    final res = _logic.softDrop();
    score.value = _logic.score;
    if (res != null) {
      Haptics.medium();
      _onLock(res);
    }
  }

  bool get _running => phase.value == TetrisPhase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  void _onLock(LockResult res) {
    final prevLevel = level.value;
    score.value = _logic.score;
    lines.value = _logic.lines;
    level.value = _logic.level;
    next.value = _logic.next;

    if (res.cleared > 0) {
      _clearCombo++;
      combo.value = _clearCombo;
      _onLinesCleared(res);
    } else {
      _clearCombo = 0;
      combo.value = 0;
    }

    if (level.value > prevLevel) {
      _flash = max(_flash, 0.4);
      _popups.add(_Popup(
        gridX: TetrisLogic.cols / 2,
        gridY: TetrisLogic.rows / 2 - 2,
        text: 'LEVEL ${level.value}',
        color: const Color(0xFF4ECDC4),
        big: true,
      ));
      Haptics.heavy();
    }

    if (res.gameOver) {
      phase.value = TetrisPhase.dead;
      _shake = 1;
      _flash = max(_flash, 0.6);
      Haptics.heavy();
      onGameOver(score.value);
    }
  }

  void _onLinesCleared(LockResult res) {
    for (var i = 0; i < res.clearedRows.length; i++) {
      final y = res.clearedRows[i];
      _rowFlashes.add(_RowFlash(row: y));
      _spawnRowBurst(y, res.clearedCells[i]);
    }

    _shake = max(_shake, 0.4 + res.cleared * 0.18);
    _flash = max(_flash, res.tetris ? 0.5 : 0.2);

    final String label;
    final Color color;
    if (res.tetris) {
      label = res.backToBack ? 'BACK-TO-BACK\nQUAD!' : 'QUAD!';
      color = const Color(0xFFFFD54F);
    } else if (res.cleared >= 2) {
      label = '${res.cleared} В РЯД';
      color = const Color(0xFFFF6FAE);
    } else {
      label = '+${res.gained}';
      color = Colors.white;
    }
    _popups.add(_Popup(
      gridX: TetrisLogic.cols / 2,
      gridY: res.clearedRows.first.toDouble(),
      text: label,
      color: color,
      big: res.tetris || res.cleared >= 3,
    ));

    if (res.tetris || _clearCombo >= 2) {
      Haptics.combo(res.tetris ? 5 : _clearCombo);
    } else {
      Haptics.medium();
    }
  }

  // ── Эффекты ───────────────────────────────────────────────────────────────

  void _spawnRowBurst(int row, List<Tetromino> cells) {
    for (var x = 0; x < TetrisLogic.cols; x++) {
      final base = tetrominoColor(cells[x]);
      for (var i = 0; i < 3; i++) {
        final a = _rng.nextDouble() * 2 * pi;
        final speed = 60 + _rng.nextDouble() * 160;
        _sparks.add(_Spark(
          gridX: x + 0.5,
          gridY: row + 0.5,
          vel: Offset(cos(a), sin(a)) * speed,
          life: 0.4 + _rng.nextDouble() * 0.5,
          color: base,
        ));
      }
    }
  }

  void _spawnImpact(List<Point<int>> cells) {
    // Пыль по нижней кромке приземлившейся фигуры.
    var maxY = 0;
    for (final c in cells) {
      maxY = max(maxY, c.y);
    }
    for (final c in cells.where((c) => c.y == maxY)) {
      for (var i = 0; i < 4; i++) {
        _sparks.add(_Spark(
          gridX: c.x + 0.5,
          gridY: c.y + 0.9,
          vel: Offset((_rng.nextDouble() * 2 - 1) * 90, -_rng.nextDouble() * 80),
          life: 0.25 + _rng.nextDouble() * 0.25,
          color: Colors.white,
        ));
      }
    }
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.2);
    _flash = max(0, _flash - dt * 1.8);

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.4 * dt), s.vel.dy + 320 * dt); // гравитация
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);

    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= _Popup.duration);

    for (final f in _rowFlashes) {
      f.age += dt;
    }
    _rowFlashes.removeWhere((f) => f.age >= _RowFlash.duration);
  }

  // ── Игровой цикл ───────────────────────────────────────────────────────────

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
    while (_acc >= _gravityInterval) {
      _acc -= _gravityInterval;
      final res = _logic.gravityTick();
      if (res != null) _onLock(res);
      if (!_running) break;
    }
  }

  // ── Рендер ───────────────────────────────────────────────────────────────

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
    if (_running) {
      _drawGhost(canvas);
      _drawPiece(canvas);
    }
    _drawRowFlashes(canvas);
    _drawSparks(canvas);
    _drawPopups(canvas);

    if (_shake > 0) canvas.restore();

    if (_flash > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = Colors.white.withValues(alpha: _flash * 0.4),
      );
    }
  }

  void _computeGeometry() {
    final availH = size.y - _topInset - _bottomInset;
    _cell = min(size.x / (TetrisLogic.cols + 2), availH / TetrisLogic.rows);
    final w = _cell * TetrisLogic.cols;
    final h = _cell * TetrisLogic.rows;
    _origin = Offset((size.x - w) / 2, _topInset + (availH - h) / 2);
  }

  Rect _cellRect(num gx, num gy) => Rect.fromLTWH(
        _origin.dx + gx * _cell,
        _origin.dy + gy * _cell,
        _cell,
        _cell,
      );

  Offset _point(double gx, double gy) =>
      _origin + Offset(gx * _cell, gy * _cell);

  void _drawWell(Canvas canvas) {
    final w = _cell * TetrisLogic.cols;
    final h = _cell * TetrisLogic.rows;
    final rect = RRect.fromRectAndRadius(
      (_origin & Size(w, h)).inflate(_cell * 0.15),
      Radius.circular(_cell * 0.3),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF161126));

    final grid = Paint()
      ..color = const Color(0xFF221A3A)
      ..strokeWidth = 1;
    for (var x = 1; x < TetrisLogic.cols; x++) {
      canvas.drawLine(_point(x.toDouble(), 0),
          _point(x.toDouble(), TetrisLogic.rows.toDouble()), grid);
    }
    for (var y = 1; y < TetrisLogic.rows; y++) {
      canvas.drawLine(_point(0, y.toDouble()),
          _point(TetrisLogic.cols.toDouble(), y.toDouble()), grid);
    }
  }

  void _drawBlock(Canvas canvas, num gx, num gy, Color color,
      {double alpha = 1, bool glow = false}) {
    final rect = _cellRect(gx, gy).deflate(_cell * 0.06);
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(_cell * 0.22));
    if (glow) {
      canvas.drawRRect(
        rrect.inflate(2),
        Paint()
          ..color = color.withValues(alpha: 0.5 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: alpha));
    // Лёгкий блик сверху для объёма.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.32),
        Radius.circular(_cell * 0.22),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.18 * alpha),
    );
  }

  void _drawStack(Canvas canvas) {
    for (var y = 0; y < TetrisLogic.rows; y++) {
      for (var x = 0; x < TetrisLogic.cols; x++) {
        final t = _logic.board[y][x];
        if (t != null) _drawBlock(canvas, x, y, tetrominoColor(t));
      }
    }
  }

  void _drawGhost(Canvas canvas) {
    final color = tetrominoColor(_logic.current.type);
    for (final c in _logic.ghost().cells()) {
      if (c.y < 0) continue;
      final rrect = RRect.fromRectAndRadius(
        _cellRect(c.x, c.y).deflate(_cell * 0.18),
        Radius.circular(_cell * 0.18),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.35),
      );
    }
  }

  void _drawPiece(Canvas canvas) {
    final color = tetrominoColor(_logic.current.type);
    for (final c in _logic.current.cells()) {
      if (c.y < 0) continue;
      _drawBlock(canvas, c.x, c.y, color, glow: true);
    }
  }

  void _drawRowFlashes(Canvas canvas) {
    for (final f in _rowFlashes) {
      final k = 1 - f.age / _RowFlash.duration;
      canvas.drawRect(
        _point(0, f.row.toDouble()) &
            Size(_cell * TetrisLogic.cols, _cell),
        Paint()..color = Colors.white.withValues(alpha: k * 0.85),
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
      final center = _point(p.gridX, p.gridY) - Offset(0, k * _cell * 1.5);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(alpha: alpha),
            fontSize: _cell * scale,
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

class _RowFlash {
  _RowFlash({required this.row});
  static const double duration = 0.35;
  final int row;
  double age = 0;
}
