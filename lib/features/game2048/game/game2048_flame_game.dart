import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/game2048_logic.dart';

/// Фаза партии — управляет показываемым оверлеем.
enum Game2048Phase { ready, running, dead }

/// Flame-игра «2048» с упором на «сок»: pop новой плитки, вспышка и частицы
/// «в цвет» при слиянии, особый акцент при появлении 2048, тряска на крупных
/// слияниях и всплывающие очки.
///
/// Чистая механика — в [Game2048Logic]; здесь только ввод, рендер и фидбек.
class Game2048FlameGame extends FlameGame {
  Game2048FlameGame({required this.onGameOver, this.gridSize = 4});

  /// Вызывается при конце игры со счётом партии (для рекордов/оверлея).
  final void Function(int score) onGameOver;

  /// Сторона квадратной сетки. (Не `size` — у FlameGame это Vector2 экрана.)
  final int gridSize;

  late final Game2048Logic _logic = Game2048Logic(size: gridSize);
  final Random _rng = Random();

  // Наблюдаемое для HUD/оверлеев.
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> maxTile = ValueNotifier(0);
  final ValueNotifier<double> fps = ValueNotifier(0);
  final ValueNotifier<Game2048Phase> phase =
      ValueNotifier(Game2048Phase.ready);
  // ВНИМАНИЕ: именно isPaused — у FlameGame уже есть собственный member paused.
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  bool get _running => phase.value == Game2048Phase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  // Геометрия поля.
  static const double _topInset = 110;
  static const double _bottomInset = 44;
  double _cell = 0;
  Offset _origin = Offset.zero;
  double _boardSize = 0;

  // Эффекты.
  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  // Анимации появления плиток: индекс клетки -> прогресс «pop» (0..1).
  final Map<int, double> _pops = {};
  double _shake = 0;
  double _flash = 0;
  Color _flashColor = Colors.white;

  // FPS.
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  // ── Управление состоянием ────────────────────────────────────────────────

  void start() {
    _logic.reset();
    score.value = 0;
    maxTile.value = _logic.maxTile;
    _sparks.clear();
    _popups.clear();
    _pops.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = Game2048Phase.running;
  }

  // ── Ввод (вызывается экраном) ────────────────────────────────────────────

  void swipe(SlideDirection dir) {
    if (!_active) return;
    final res = _logic.move(dir);
    if (!res.moved) return;
    _onMove(res);
  }

  void _onMove(MoveResult res) {
    score.value = _logic.score;
    maxTile.value = _logic.maxTile;

    // Появление новой плитки — короткий «pop».
    final spawn = res.spawned;
    if (spawn != null) {
      _pops[spawn.y * gridSize + spawn.x] = 0;
    }

    if (res.merges.isEmpty) {
      Haptics.light();
    } else {
      var biggest = 0;
      for (final m in res.merges) {
        biggest = max(biggest, m.value);
        _spawnMergeBurst(m);
        _popups.add(_Popup(
          gridX: m.x + 0.5,
          gridY: m.y + 0.5,
          text: '+${m.value}',
          color: _tileColor(m.value),
          big: m.value >= 128,
        ));
      }

      // Крупные слияния ощущаются телом сильнее и трясут экран.
      _shake = max(_shake, biggest >= 128 ? 0.6 : 0.3);
      if (res.merges.length >= 2 || biggest >= 128) {
        Haptics.combo((res.merges.length + 1).clamp(2, 5));
      } else {
        Haptics.medium();
      }
    }

    // Особый акцент на первой 2048.
    if (res.reached2048) {
      _flash = 0.7;
      _flashColor = const Color(0xFFFFD54F);
      _shake = max(_shake, 0.8);
      _popups.add(_Popup(
        gridX: gridSize / 2,
        gridY: gridSize / 2,
        text: '2048!',
        color: const Color(0xFFFFD54F),
        big: true,
      ));
      for (var i = 0; i < 60; i++) {
        _spawnConfetti();
      }
      Haptics.combo(5);
    }

    if (_logic.isGameOver) {
      phase.value = Game2048Phase.dead;
      _shake = max(_shake, 0.7);
      _flash = max(_flash, 0.5);
      _flashColor = const Color(0xFFFF5370);
      Haptics.heavy();
      onGameOver(score.value);
    }
  }

  // ── Эффекты ───────────────────────────────────────────────────────────────

  void _spawnMergeBurst(Merge m) {
    final base = _tileColor(m.value);
    final count = 8 + (log(m.value) / log(2)).round();
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 60 + _rng.nextDouble() * 150;
      _sparks.add(_Spark(
        gridX: m.x + 0.5,
        gridY: m.y + 0.5,
        vel: Offset(cos(a), sin(a)) * speed,
        life: 0.4 + _rng.nextDouble() * 0.4,
        color: base,
      ));
    }
  }

  void _spawnConfetti() {
    const palette = [
      Color(0xFFFF6FAE),
      Color(0xFFFFD54F),
      Color(0xFF4ECDC4),
      Color(0xFF7C5CFF),
      Color(0xFF5CE08A),
    ];
    final a = _rng.nextDouble() * 2 * pi;
    final speed = 80 + _rng.nextDouble() * 200;
    _sparks.add(_Spark(
      gridX: _rng.nextInt(gridSize) + 0.5,
      gridY: _rng.nextInt(gridSize) + 0.5,
      vel: Offset(cos(a), sin(a)) * speed,
      life: 0.6 + _rng.nextDouble() * 0.6,
      color: palette[_rng.nextInt(palette.length)],
    ));
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.2);
    _flash = max(0, _flash - dt * 1.6);

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.4 * dt), s.vel.dy + 280 * dt);
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);

    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= _Popup.duration);

    // Прогресс «pop» появившихся плиток.
    final done = <int>[];
    _pops.updateAll((key, value) => value + dt / _popDuration);
    _pops.forEach((key, value) {
      if (value >= 1) done.add(key);
    });
    for (final k in done) {
      _pops.remove(k);
    }
  }

  static const double _popDuration = 0.18;

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

    // У «2048» нет автономной прогрессии (ходы дискретны), но держим контракт:
    // вся будущая физика/таймеры идут только после этого гарда.
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
    _drawTiles(canvas);
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
    _boardSize = min(size.x - 24, availH);
    _cell = _boardSize / gridSize;
    _origin = Offset(
      (size.x - _boardSize) / 2,
      _topInset + (availH - _boardSize) / 2,
    );
  }

  Rect _cellRect(int x, int y) => Rect.fromLTWH(
        _origin.dx + x * _cell,
        _origin.dy + y * _cell,
        _cell,
        _cell,
      );

  Offset _point(double gx, double gy) =>
      _origin + Offset(gx * _cell, gy * _cell);

  void _drawBoard(Canvas canvas) {
    final rect = RRect.fromRectAndRadius(
      (_origin & Size(_boardSize, _boardSize)).inflate(_cell * 0.06),
      Radius.circular(_cell * 0.18),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF161126));

    // Пустые гнёзда.
    final slot = Paint()..color = const Color(0xFF221A3A);
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final r = _cellRect(x, y).deflate(_cell * 0.06);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(_cell * 0.16)),
          slot,
        );
      }
    }
  }

  void _drawTiles(Canvas canvas) {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final v = _logic.tileAt(x, y);
        if (v == 0) continue;
        _drawTile(canvas, x, y, v);
      }
    }
  }

  void _drawTile(Canvas canvas, int x, int y, int value) {
    final base = _cellRect(x, y).deflate(_cell * 0.06);

    // «Pop» появления: плитка слегка вырастает с лёгким перелётом.
    final pop = _pops[y * gridSize + x];
    var rect = base;
    if (pop != null) {
      final t = Curves.easeOutBack.transform(pop.clamp(0.0, 1.0));
      final scale = 0.2 + 0.8 * t;
      final cx = base.center.dx;
      final cy = base.center.dy;
      rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: base.width * scale,
        height: base.height * scale,
      );
    }

    final color = _tileColor(value);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(_cell * 0.16));

    // Свечение для крупных плиток.
    if (value >= 128) {
      canvas.drawRRect(
        rrect.inflate(3),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawRRect(rrect, Paint()..color = color);
    // Блик сверху для объёма.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.34),
        Radius.circular(_cell * 0.16),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );

    _drawTileText(canvas, rect, value);
  }

  void _drawTileText(Canvas canvas, Rect rect, int value) {
    final text = '$value';
    // Чем длиннее число, тем мельче шрифт, чтобы влезало.
    final fit = text.length <= 2
        ? 0.42
        : text.length == 3
            ? 0.34
            : text.length == 4
                ? 0.26
                : 0.2;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _tileTextColor(value),
          fontSize: _cell * fit,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      canvas.drawCircle(
        _point(s.gridX, s.gridY) + s.pos,
        _cell * 0.12 * k,
        Paint()..color = s.color.withValues(alpha: k),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = (p.big ? 1.0 : 0.7) * (1 + 0.3 * (1 - k));
      final center = _point(p.gridX, p.gridY) - Offset(0, k * _cell * 1.2);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(alpha: alpha),
            fontSize: _cell * 0.5 * scale,
            fontWeight: FontWeight.w900,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  // ── Палитра плиток ─────────────────────────────────────────────────────────

  /// Цвет плитки по её величине: тёплая прогрессия от мягкого к яркому.
  Color _tileColor(int value) {
    switch (value) {
      case 2:
        return const Color(0xFF3A2F5C);
      case 4:
        return const Color(0xFF4A3A78);
      case 8:
        return const Color(0xFF7C5CFF);
      case 16:
        return const Color(0xFF9C6CFF);
      case 32:
        return const Color(0xFFFF6FAE);
      case 64:
        return const Color(0xFFFF8A65);
      case 128:
        return const Color(0xFFFFB74D);
      case 256:
        return const Color(0xFFFFC947);
      case 512:
        return const Color(0xFFFFD54F);
      case 1024:
        return const Color(0xFF4ECDC4);
      default:
        // 2048 и выше — самый яркий золотой акцент.
        return const Color(0xFFFFE082);
    }
  }

  /// Цвет цифр: на тёмных мелких плитках — приглушённо-светлый, на ярких — тёмный.
  Color _tileTextColor(int value) =>
      value <= 4 ? const Color(0xFFEDEAFB) : const Color(0xFF1A1330);
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
  static const double duration = 0.95;
  final double gridX;
  final double gridY;
  final String text;
  final Color color;
  final bool big;
  double age = 0;
}
