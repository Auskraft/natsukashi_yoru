import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/sokoban_logic.dart';

/// Фаза партии — управляет показываемым оверлеем.
///
/// «Сокобан» завершается победой над уровнем (проигрыша нет), поэтому к
/// общему скелету {ready, running} добавлена только [won].
enum SokobanPhase { ready, running, won }

/// Flame-игра «Сокобан» с упором на «сок»: лёгкая хаптика на каждый шаг,
/// акцент-вспышка и частицы, когда ящик встаёт на цель, салют и тряска на
/// победе уровня. Чистая механика — в [SokobanLogic]; здесь тайминг, ввод,
/// рендер и фидбек.
class SokobanFlameGame extends FlameGame {
  SokobanFlameGame({required this.onLevelSolved});

  /// Вызывается при прохождении уровня: число ходов на этом уровне
  /// (для рекорда «меньше — лучше») и пройденный номер уровня.
  final void Function(int moves, int level) onLevelSolved;

  final SokobanLogic _logic = SokobanLogic();
  final Random _rng = Random();

  // Наблюдаемое для HUD/оверлеев.
  final ValueNotifier<int> moves = ValueNotifier(0);
  final ValueNotifier<int> level = ValueNotifier(1);
  final ValueNotifier<int> boxesOnGoal = ValueNotifier(0);
  final ValueNotifier<int> goalCount = ValueNotifier(0);
  final ValueNotifier<SokobanPhase> phase = ValueNotifier(SokobanPhase.ready);
  final ValueNotifier<double> fps = ValueNotifier(0);
  // ВАЖНО: именно isPaused, чтобы не конфликтовать с FlameGame.paused.
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  bool get _running => phase.value == SokobanPhase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  // Геометрия поля (считается в render по текущему размеру и размеру уровня).
  // Резерв сверху под HUD, снизу — небольшой отступ.
  static const double _topInset = 104;
  static const double _bottomInset = 36;
  double _cell = 0;
  Offset _origin = Offset.zero;

  /// Размер клетки в пикселях (для жестов экрана); 0 до первого рендера.
  double get cellSize => _cell;

  // Эффекты «сока».
  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  double _shake = 0;
  double _flash = 0;
  Color _flashColor = const Color(0xFF22D3EE);

  // Сглаженный FPS для отладочного индикатора.
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  // ── Управление состоянием ────────────────────────────────────────────────

  /// Старт новой игры с первого уровня. Сбрасывает всё, включая паузу.
  void start() {
    _logic.reset();
    _syncStats();
    _sparks.clear();
    _popups.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = SokobanPhase.running;
  }

  /// Перезапустить текущий уровень (после победы — заново тот же; в паузе —
  /// «Заново»). Возвращает игру в фазу running.
  void restartLevel() {
    _logic.restartLevel();
    _syncStats();
    _sparks.clear();
    _popups.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = SokobanPhase.running;
  }

  /// Перейти на следующий уровень после победы. Если уровней больше нет —
  /// начинает игру заново с первого.
  void advanceLevel() {
    if (!_logic.nextLevel()) {
      start();
      return;
    }
    _syncStats();
    _sparks.clear();
    _popups.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = SokobanPhase.running;
  }

  void _syncStats() {
    moves.value = _logic.moves;
    level.value = _logic.levelNumber;
    boxesOnGoal.value = _logic.boxesOnGoal;
    goalCount.value = _logic.goalCount;
  }

  // ── Ввод (вызывается экраном) ────────────────────────────────────────────

  /// Сделать ход в направлении [dir] с фидбеком. Гард — только в активной игре.
  void step(SokoDir dir) {
    if (!_active) return;
    final res = _logic.move(dir);
    switch (res.kind) {
      case SokoMoveKind.blocked:
        return; // ничего не изменилось — без счётчика и хаптики
      case SokoMoveKind.walked:
        moves.value = _logic.moves;
        Haptics.light();
      case SokoMoveKind.pushed:
      case SokoMoveKind.pushedOffGoal:
        moves.value = _logic.moves;
        Haptics.medium();
      case SokoMoveKind.pushedOntoGoal:
        moves.value = _logic.moves;
        boxesOnGoal.value = _logic.boxesOnGoal;
        _onBoxOnGoal(res.box!);
    }

    if (res.kind == SokoMoveKind.pushedOffGoal) {
      boxesOnGoal.value = _logic.boxesOnGoal;
    }

    if (res.solved) _onSolved();
  }

  void _onBoxOnGoal(Point<int> cell) {
    // Акцент-вспышка и искры, когда ящик встаёт на цель.
    _flash = max(_flash, 0.4);
    _flashColor = const Color(0xFF22D3EE);
    _spawnBurst(cell.x + 0.5, cell.y + 0.5, const Color(0xFF22D3EE), count: 12);
    _popups.add(_Popup(gridX: cell.x + 0.5, gridY: cell.y + 0.5, text: '✓'));
    Haptics.medium();
  }

  void _onSolved() {
    phase.value = SokobanPhase.won;
    _shake = max(_shake, 0.4);
    _flash = 0.5;
    _flashColor = const Color(0xFF5CE08A);
    // Салют по всему полю.
    for (var i = 0; i < 64; i++) {
      _spawnBurst(
        _rng.nextInt(_logic.cols) + 0.5,
        _rng.nextInt(_logic.rows) + 0.5,
        _confetti(),
        count: 1,
      );
    }
    Haptics.heavy();
    onLevelSolved(_logic.moves, _logic.levelNumber);
  }

  Color _confetti() {
    const palette = [
      Color(0xFF22D3EE),
      Color(0xFFFFD54F),
      Color(0xFFFF6FAE),
      Color(0xFF7C5CFF),
      Color(0xFF5CE08A),
    ];
    return palette[_rng.nextInt(palette.length)];
  }

  void _spawnBurst(double gx, double gy, Color color, {int count = 6}) {
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 50 + _rng.nextDouble() * 170;
      _sparks.add(_Spark(
        gridX: gx,
        gridY: gy,
        vel: Offset(cos(a), sin(a)) * speed,
        life: 0.4 + _rng.nextDouble() * 0.5,
        color: color,
      ));
    }
  }

  // ── Цикл обновления ───────────────────────────────────────────────────────

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
    // У «Сокобана» нет автономной прогрессии (всё пошагово по вводу), поэтому
    // здесь после гейта _active никакой таймерной логики нет.
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.2);
    _flash = max(0, _flash - dt * 1.8);

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.2 * dt), s.vel.dy + 260 * dt);
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

    if (_shake > 0) {
      final m = _shake * _shake * 10;
      canvas.save();
      canvas.translate(
        (_rng.nextDouble() * 2 - 1) * m,
        (_rng.nextDouble() * 2 - 1) * m,
      );
    }

    _drawBoard(canvas);
    _drawPlayer(canvas);
    _drawSparks(canvas);
    _drawPopups(canvas);

    if (_shake > 0) canvas.restore();

    if (_flash > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = _flashColor.withValues(alpha: _flash * 0.42),
      );
    }
  }

  void _computeGeometry() {
    final cols = _logic.cols;
    final rows = _logic.rows;
    if (cols == 0 || rows == 0) return;
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

  void _drawBoard(Canvas canvas) {
    for (var y = 0; y < _logic.rows; y++) {
      for (var x = 0; x < _logic.cols; x++) {
        final tile = _logic.board[y][x];
        switch (tile) {
          case SokoTile.wall:
            _drawWall(canvas, x, y);
          case SokoTile.floor:
            _drawFloor(canvas, x, y);
          case SokoTile.goal:
            _drawFloor(canvas, x, y);
            _drawGoal(canvas, x, y);
          case SokoTile.box:
            _drawFloor(canvas, x, y);
            _drawBox(canvas, x, y, onGoal: false);
          case SokoTile.boxOnGoal:
            _drawFloor(canvas, x, y);
            _drawGoal(canvas, x, y);
            _drawBox(canvas, x, y, onGoal: true);
        }
      }
    }
  }

  void _drawFloor(Canvas canvas, int x, int y) {
    final rect = _rect(x, y).deflate(_cell * 0.03);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(_cell * 0.12));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF161126));
  }

  void _drawWall(Canvas canvas, int x, int y) {
    final rect = _rect(x, y).deflate(_cell * 0.02);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(_cell * 0.16));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF2A2147));
    // Тонкий «глянец» сверху для объёма.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.4),
        Radius.circular(_cell * 0.16),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );
  }

  void _drawGoal(Canvas canvas, int x, int y) {
    final c = _rect(x, y).center;
    final r = _cell * 0.16;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _cell * 0.06
        ..color = const Color(0xFF22D3EE).withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      c,
      r * 0.45,
      Paint()..color = const Color(0xFF22D3EE).withValues(alpha: 0.5),
    );
  }

  void _drawBox(Canvas canvas, int x, int y, {required bool onGoal}) {
    final rect = _rect(x, y).deflate(_cell * 0.14);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(_cell * 0.14));
    final base =
        onGoal ? const Color(0xFF22D3EE) : const Color(0xFFFF9F45);
    if (onGoal) {
      canvas.drawRRect(
        rrect.inflate(_cell * 0.04),
        Paint()
          ..color = base.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawRRect(rrect, Paint()..color = base);
    // Крестовина-перетяжка ящика.
    final cross = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = _cell * 0.05;
    canvas.drawLine(rect.topLeft, rect.bottomRight, cross);
    canvas.drawLine(rect.topRight, rect.bottomLeft, cross);
  }

  void _drawPlayer(Canvas canvas) {
    final p = _logic.player;
    final c = _rect(p.x, p.y).center;
    final r = _cell * 0.32;
    canvas.drawCircle(
      c,
      r * 1.6,
      Paint()
        ..color = const Color(0xFF7C5CFF).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF7C5CFF));
    // Блик.
    canvas.drawCircle(
      c - Offset(r * 0.3, r * 0.3),
      r * 0.32,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      canvas.drawCircle(
        _center(s.gridX, s.gridY) + s.pos,
        _cell * 0.12 * k,
        Paint()..color = s.color.withValues(alpha: k),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final center =
          _center(p.gridX, p.gridY) - Offset(0, _cell * (0.2 + k * 1.2));
      final alpha = (1 - k).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: const Color(0xFF22D3EE).withValues(alpha: alpha),
            fontSize: _cell * 0.6 * (1 + 0.3 * (1 - k)),
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
  _Popup({required this.gridX, required this.gridY, required this.text});
  static const double duration = 0.8;
  final double gridX;
  final double gridY;
  final String text;
  double age = 0;
}
