import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/breakout_logic.dart';

/// Фаза партии — управляет показываемым оверлеем.
enum BreakoutPhase { ready, running, dead }

/// Flame-игра «Breakout/Арканоид» с упором на «сок»: частицы разбитого кирпича
/// в его цвет, вспышка и тряска при потере мяча, всплывающие очки, комбо за
/// серию кирпичей без касания ракетки и хаптика на отскоках/потере.
///
/// Чистая физика — в [BreakoutLogic]; здесь только тайминг, ввод, рендер
/// и фидбек. Реалтайм-симуляция идёт в [update] при `_active`.
class BreakoutFlameGame extends FlameGame {
  BreakoutFlameGame({
    required this.onGameOver,
    this.cols = 8,
    this.bottomInset = 28,
  });

  /// Вызывается при конце партии со счётом (для рекордов/оверлея).
  final void Function(int score) onGameOver;

  /// Число колонок кирпичей (передаётся в логику).
  final int cols;

  /// Резерв снизу под экранные контролы (задаёт экран-хост по схеме).
  final double bottomInset;

  late final BreakoutLogic _logic =
      BreakoutLogic(cols: cols, fieldHeight: _fieldAspect);
  final Random _rng = Random();

  /// Высота поля в долях ширины (портретное поле под мобильный экран).
  static const double _fieldAspect = 1.45;

  // Скорость кнопочного движения ракетки (доля поля в секунду).
  static const double _kPaddleKeySpeed = 1.6;

  // Наблюдаемое для HUD/оверлеев.
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> lives = ValueNotifier(BreakoutLogic.startLives);
  final ValueNotifier<int> level = ValueNotifier(1);
  final ValueNotifier<int> combo = ValueNotifier(0);
  final ValueNotifier<double> fps = ValueNotifier(0);
  final ValueNotifier<BreakoutPhase> phase =
      ValueNotifier(BreakoutPhase.ready);

  // ВАЖНО: у FlameGame уже есть member `paused`, поэтому нотифаер паузы —
  // именно `isPaused`, чтобы не было конфликта имён.
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  bool get _running => phase.value == BreakoutPhase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  // Целевая позиция ракетки по X (нормализованная). Ведётся пальцем; если за
  // кадр игрок не двигал — держим текущую позицию логики.
  late double _targetPaddleX = 0.5;

  // Направление кнопочного движения ракетки: -1..1 (0 — стоп). Задаётся
  // экранными кнопками; применяется в [update].
  double _paddleDir = 0;

  // Комбо: серия кирпичей без касания ракетки.
  int _chain = 0;

  // Резерв сверху под HUD; снизу — [bottomInset] (под контролы, задаёт хост).
  static const double _topInset = 92;

  // Эффекты.
  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  double _shake = 0;
  double _flash = 0;
  Color _flashColor = Colors.white;

  // FPS.
  double _fpsAcc = 0;
  int _fpsFrames = 0;

  // Геометрия поля (считается в render по текущему размеру).
  double _scale = 0; // пикселей на 1 единицу поля (по ширине поля)
  Offset _origin = Offset.zero; // левый-верхний угол поля в пикселях
  double _fieldW = 0;
  double _fieldH = 0;

  /// Палитра рядов кирпичей (индекс цвета из логики маппится сюда циклически).
  static const List<Color> _rowColors = [
    Color(0xFFFF5370), // красный
    Color(0xFFFF9F45), // оранжевый
    Color(0xFFFFD54F), // жёлтый
    Color(0xFF5CE08A), // зелёный
    Color(0xFF4ECDC4), // бирюзовый
    Color(0xFF5C8CFF), // синий
    Color(0xFF7C5CFF), // фиолетовый
    Color(0xFFFF6FAE), // розовый
  ];

  Color _rowColor(int index) => _rowColors[index % _rowColors.length];

  // ── Управление состоянием ──────────────────────────────────────────────────

  void start() {
    _logic.reset();
    score.value = 0;
    lives.value = _logic.lives;
    level.value = _logic.level;
    combo.value = 0;
    _chain = 0;
    _targetPaddleX = _logic.paddleX;
    _sparks.clear();
    _popups.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = BreakoutPhase.running;
  }

  // ── Ввод (вызывается экраном) ──────────────────────────────────────────────

  /// Навести ракетку на горизонтальную позицию пальца (в пикселях экрана).
  void aimAt(double globalX) {
    if (!_active) return;
    if (_scale <= 0) return;
    _targetPaddleX = ((globalX - _origin.dx) / _fieldW).clamp(0.0, 1.0);
  }

  /// Запустить приклеенный мяч (тап по экрану).
  void launch() {
    if (!_active) return;
    if (_logic.ballOnPaddle) {
      _logic.launch();
      Haptics.light();
    }
  }

  /// Кнопочное управление ракеткой: [dir] -1..1 (0 — стоп). Применяется в update.
  void setPaddleDir(double dir) => _paddleDir = dir.clamp(-1.0, 1.0);

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

    // Ограничиваем dt, чтобы при подвисании кадра физика не «прыгнула».
    final clamped = dt > 0.05 ? 0.05 : dt;
    if (_paddleDir != 0) {
      _targetPaddleX =
          (_targetPaddleX + _paddleDir * _kPaddleKeySpeed * clamped)
              .clamp(0.0, 1.0);
    }
    final res = _logic.step(clamped, _targetPaddleX);
    _applyResult(res);
  }

  void _applyResult(StepResult res) {
    if (res.brokenBricks.isNotEmpty) {
      score.value = _logic.score;
      for (final b in res.brokenBricks) {
        _chain++;
        _spawnBrickBurst(b);
        _popups.add(_Popup(
          pos: b.center,
          text: '+${b.points}',
          color: _rowColor(b.colorIndex),
          big: _chain >= 4,
        ));
      }
      combo.value = _chain;
      _shake = max(_shake, 0.12 + res.brokenBricks.length * 0.05);
      if (_chain >= 4) {
        Haptics.combo((_chain ~/ 2).clamp(2, 5));
      } else {
        Haptics.light();
      }
    } else {
      // Касание ракетки обрывает серию-комбо.
      if (res.hasBounce(BounceKind.paddle)) {
        _chain = 0;
        combo.value = 0;
        Haptics.select();
      } else if (res.hasBounce(BounceKind.wall) ||
          res.hasBounce(BounceKind.ceiling)) {
        Haptics.light();
      }
    }

    if (res.levelCleared) {
      level.value = _logic.level;
      _flash = max(_flash, 0.4);
      _flashColor = const Color(0xFF5CE08A);
      _chain = 0;
      combo.value = 0;
      _popups.add(_Popup(
        pos: Point(0.5, _logic.fieldHeight * 0.42),
        text: 'УРОВЕНЬ ${_logic.level}',
        color: const Color(0xFF4ECDC4),
        big: true,
      ));
      Haptics.heavy();
    }

    if (res.ballLost) {
      lives.value = _logic.lives;
      _shake = max(_shake, 0.8);
      _flash = max(_flash, 0.5);
      _flashColor = const Color(0xFFFF5370);
      _chain = 0;
      combo.value = 0;
      if (!res.gameOver) {
        _targetPaddleX = _logic.paddleX;
        Haptics.heavy();
      }
    }

    if (res.gameOver) {
      _shake = 1;
      Haptics.heavy();
      // Сначала отдать счёт (экран посчитает рекорд), затем сменить фазу.
      onGameOver(score.value);
      phase.value = BreakoutPhase.dead;
    }
  }

  // ── Эффекты ───────────────────────────────────────────────────────────────

  void _spawnBrickBurst(BrokenBrick b) {
    final color = _rowColor(b.colorIndex);
    for (var i = 0; i < 12; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 60 + _rng.nextDouble() * 170;
      _sparks.add(_Spark(
        cell: b.center,
        vel: Offset(cos(a), sin(a)) * speed,
        life: 0.35 + _rng.nextDouble() * 0.45,
        color: color,
      ));
    }
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.4);
    _flash = max(0, _flash - dt * 1.8);

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.4 * dt), s.vel.dy + 220 * dt);
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

    _drawField(canvas);
    _drawBricks(canvas);
    _drawPaddle(canvas);
    _drawBall(canvas);
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
    final availH = size.y - _topInset - bottomInset;
    if (availH <= 0 || size.x <= 0) return;
    // Поле имеет соотношение 1 : fieldHeight. Вписываем по меньшей стороне.
    _scale = min(size.x, availH / _logic.fieldHeight);
    _fieldW = _scale;
    _fieldH = _scale * _logic.fieldHeight;
    _origin = Offset(
      (size.x - _fieldW) / 2,
      _topInset + (availH - _fieldH) / 2,
    );
  }

  Offset _toPx(Point<double> p) =>
      _origin + Offset(p.x * _scale, p.y * _scale);

  Offset _toPxXY(double x, double y) =>
      _origin + Offset(x * _scale, y * _scale);

  void _drawField(Canvas canvas) {
    final rect = RRect.fromRectAndRadius(
      _origin & Size(_fieldW, _fieldH),
      Radius.circular(_scale * 0.03),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF161126));
    // Тонкая рамка для глубины.
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF221A3A),
    );
  }

  void _drawBricks(Canvas canvas) {
    final bw = _logic.brickWidth * _scale;
    final bh = BreakoutLogic.brickHeight * _scale;
    for (var row = 0; row < _logic.rows; row++) {
      for (var col = 0; col < _logic.cols; col++) {
        if (!_logic.bricks[row][col]) continue;
        final c = _toPx(_logic.brickCenter(col, row));
        final rect = Rect.fromCenter(center: c, width: bw, height: bh)
            .deflate(bw * 0.04);
        final rrect =
            RRect.fromRectAndRadius(rect, Radius.circular(bh * 0.32));
        final color = _rowColor(row);
        canvas.drawRRect(rrect, Paint()..color = color);
        // Блик сверху для объёма.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.4),
            Radius.circular(bh * 0.32),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.2),
        );
      }
    }
  }

  void _drawPaddle(Canvas canvas) {
    final center = _toPxXY(_logic.paddleX, _logic.paddleY);
    final w = _logic.paddleHalfWidth * 2 * _scale;
    final h = BreakoutLogic.paddleHeight * _scale;
    final rect = Rect.fromCenter(center: center, width: w, height: h);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.5));
    // Свечение.
    canvas.drawRRect(
      rrect.inflate(3),
      Paint()
        ..color = const Color(0xFF5C8CFF).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF7C5CFF), Color(0xFF5C8CFF)],
        ).createShader(rect),
    );
  }

  void _drawBall(Canvas canvas) {
    final center = _toPx(_logic.ball);
    final r = BreakoutLogic.ballRadius * _scale;
    canvas.drawCircle(
      center,
      r * 2.2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(center, r, Paint()..color = Colors.white);
    canvas.drawCircle(
      center - Offset(r * 0.3, r * 0.3),
      r * 0.4,
      Paint()..color = Colors.white,
    );
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      canvas.drawCircle(
        _toPx(s.cell) + s.pos,
        BreakoutLogic.ballRadius * _scale * 0.7 * k,
        Paint()..color = s.color.withValues(alpha: k),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = (p.big ? 1.0 : 0.62) * (1 + 0.3 * (1 - k));
      final center =
          _toPx(p.pos) - Offset(0, k * _scale * 0.06);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(alpha: alpha),
            fontSize: _scale * 0.06 * scale,
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

/// Частица разбитого кирпича. [cell] — стартовая точка в координатах поля,
/// [pos] — накопленное смещение в пикселях (как в snake/tetris-слоях).
class _Spark {
  _Spark({
    required this.cell,
    required this.vel,
    required this.life,
    required this.color,
  });

  /// Стартовая точка в координатах поля.
  final Point<double> cell;

  /// Накопленное смещение от интегрирования (в пикселях).
  Offset pos = Offset.zero;
  Offset vel;
  final double life;
  final Color color;
  double age = 0;
}

class _Popup {
  _Popup({
    required this.pos,
    required this.text,
    required this.color,
    this.big = false,
  });
  static const double duration = 1.0;

  /// Позиция в координатах поля.
  final Point<double> pos;
  final String text;
  final Color color;
  final bool big;
  double age = 0;
}
