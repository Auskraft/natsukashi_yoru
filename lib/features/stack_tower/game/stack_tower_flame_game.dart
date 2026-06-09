import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../components/stack_tower_logic.dart';

/// Фаза партии — управляет показываемым оверлеем.
enum StackPhase { ready, running, dead }

/// Flame-игра «Stack»: блок ездит горизонтально над вершиной башни; тап —
/// фиксация. Перекрытие задаёт ширину нового блока, свисающая часть отрезается
/// и падает частицами; нет перекрытия — обвал и конец. Идеальная установка даёт
/// серию, лёгкое расширение, вспышку и комбо-хаптику. Камера плавно едет вверх.
///
/// Чистая механика (ширина/край/скорость, расчёт фиксации) — в [StackTowerLogic];
/// здесь только реалтайм-движение, ввод, рендер и «сок».
class StackFlameGame extends FlameGame {
  StackFlameGame({required this.onGameOver});

  /// Вызывается при обвале со счётом партии (для рекордов/оверлея).
  final void Function(int score) onGameOver;

  final StackTowerLogic _logic = StackTowerLogic();
  final Random _rng = Random();

  // Наблюдаемое для HUD/оверлеев.
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> combo = ValueNotifier(0);
  final ValueNotifier<double> speed = ValueNotifier(1);
  final ValueNotifier<double> fps = ValueNotifier(0);
  final ValueNotifier<StackPhase> phase = ValueNotifier(StackPhase.ready);

  // ВАЖНО: у FlameGame уже есть свой `paused` — поэтому свой нотифаер паузы
  // называем именно isPaused, чтобы не конфликтовать.
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  bool get _running => phase.value == StackPhase.running;
  bool get _active => _running && !isPaused.value;

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
  }

  // ── Сколько блоков видно и геометрия поля ────────────────────────────────

  /// Сколько верхних блоков показываем (камера держит вершину снизу экрана).
  static const int _visibleRows = 12;

  // Резерв сверху под HUD, снизу — лёгкий отступ, чтобы основание не липло.
  static const double _topInset = 96;
  static const double _bottomInset = 36;

  /// Высота одной «полки» блока на экране (в пикселях, считается по размеру).
  double _rowHeight = 0;

  /// Масштаб единиц поля логики в пиксели по горизонтали.
  double _scaleX = 0;

  /// Левый отступ игровой колонки на экране.
  double _fieldLeft = 0;

  /// Плавно отслеживаемая «высота камеры» (в блоках) для приятного доезда.
  double _camHeight = 0;

  // ── Эффекты ──────────────────────────────────────────────────────────────

  final List<_Spark> _sparks = [];
  final List<_Slab> _slabs = []; // падающие отрезанные куски
  final List<_Popup> _popups = [];
  double _shake = 0;
  double _flash = 0;

  double _fpsAcc = 0;
  int _fpsFrames = 0;

  // ── Управление состоянием ────────────────────────────────────────────────

  void start() {
    _logic.reset();
    score.value = 0;
    combo.value = 0;
    speed.value = 1;
    _camHeight = 0;
    _sparks.clear();
    _slabs.clear();
    _popups.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = StackPhase.running;
  }

  /// Тап — зафиксировать движущийся блок. Гард через [_active].
  void drop() {
    if (!_active) return;
    final out = _logic.drop();
    _handleOutcome(out);
  }

  void _handleOutcome(DropOutcome out) {
    if (out.isGameOver) {
      _onCollapse(out);
      return;
    }

    score.value = _logic.height;
    speed.value = _logic.currentSpeed / _logic.baseSpeed;
    combo.value = out.perfectStreak;

    if (out.isPerfect) {
      _flash = max(_flash, 0.35);
      _shake = max(_shake, 0.22);
      _spawnPerfectBurst(out);
      _popups.add(_Popup(
        towerY: _logic.height.toDouble(),
        fieldX: out.placedLeft + out.placedWidth / 2,
        text: out.perfectStreak >= 2 ? 'ИДЕАЛ x${out.perfectStreak}' : 'ИДЕАЛ',
        color: const Color(0xFFFFD54F),
        big: out.perfectStreak >= 2,
      ));
      if (out.perfectStreak >= 2) {
        Haptics.combo(out.perfectStreak);
      } else {
        Haptics.medium();
      }
    } else {
      _shake = max(_shake, 0.18);
      _spawnFallingSlab(out);
      Haptics.light();
    }
  }

  void _onCollapse(DropOutcome out) {
    // Падающий «промах» целиком — для эффекта обрушения.
    _spawnFallingSlab(out, full: true);
    _shake = 1;
    _flash = max(_flash, 0.5);
    Haptics.heavy();
    // Сначала отдать счёт (экран посчитает рекорд), затем сменить фазу.
    onGameOver(score.value);
    phase.value = StackPhase.dead;
  }

  // ── Эффекты: спавн ─────────────────────────────────────────────────────────

  void _spawnPerfectBurst(DropOutcome out) {
    final cx = out.placedLeft + out.placedWidth / 2;
    final towerY = _logic.height.toDouble();
    const count = 16;
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final sp = 50 + _rng.nextDouble() * 140;
      _sparks.add(_Spark(
        fieldX: cx,
        towerY: towerY,
        vel: Offset(cos(a), sin(a)) * sp,
        life: 0.4 + _rng.nextDouble() * 0.4,
        color: const Color(0xFFFFD54F),
      ));
    }
  }

  void _spawnFallingSlab(DropOutcome out, {bool full = false}) {
    if (full) {
      // Весь несостоявшийся блок: падает с лёгким горизонтальным сносом.
      _slabs.add(_Slab(
        fieldX: out.placedLeft,
        towerY: _logic.height.toDouble() + 1,
        width: out.placedWidth,
        vx: out.placedLeft < _logic.fieldWidth / 2 ? -40 : 40,
        color: _blockColor(_logic.height + 1),
      ));
      return;
    }
    if (out.cutWidth <= 0) return;
    // Отрезанная свисающая часть улетает в сторону свеса.
    final vx = out.cutSide == CutSide.left ? -70.0 : 70.0;
    _slabs.add(_Slab(
      fieldX: out.cutLeft,
      towerY: _logic.height.toDouble(),
      width: out.cutWidth,
      vx: vx,
      color: _blockColor(_logic.height),
    ));
    // Немного искр в месте среза.
    final edgeX = out.cutSide == CutSide.left ? out.cutLeft + out.cutWidth
        : out.cutLeft;
    for (var i = 0; i < 8; i++) {
      _sparks.add(_Spark(
        fieldX: edgeX,
        towerY: _logic.height.toDouble(),
        vel: Offset(vx * (0.4 + _rng.nextDouble() * 0.6),
            -_rng.nextDouble() * 60),
        life: 0.3 + _rng.nextDouble() * 0.3,
        color: Colors.white,
      ));
    }
  }

  // ── Эффекты: апдейт ──────────────────────────────────────────────────────

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.4);
    _flash = max(0, _flash - dt * 1.8);

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.4 * dt), s.vel.dy + 320 * dt);
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);

    for (final s in _slabs) {
      s.vy += 520 * dt; // гравитация
      s.fallY += s.vy * dt;
      s.fallX += s.vx * dt;
      s.age += dt;
    }
    _slabs.removeWhere((s) => s.age >= _Slab.duration);

    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= _Popup.duration);
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

    // Камера плавно доезжает до текущей высоты даже на паузе/в конце —
    // ощущается как мягкий «доводчик», не влияет на прогрессию.
    _camHeight += (_logic.height - _camHeight) * min(1, dt * 6);

    if (!_active) return;

    // Реалтайм-движение блока. Скорость растёт с высотой (в самой логике).
    _logic.advance(dt);
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

    _drawTower(canvas);
    if (_running) _drawMover(canvas);
    _drawSlabs(canvas);
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
    _rowHeight = availH / _visibleRows;
    // Поле занимает по ширине почти весь экран с небольшими полями.
    final fieldPx = size.x * 0.86;
    _scaleX = fieldPx / _logic.fieldWidth;
    _fieldLeft = (size.x - fieldPx) / 2;
  }

  /// Экранный прямоугольник блока по его уровню в башне (towerY, 0 — основание)
  /// и горизонтали в единицах поля. Камера держит вершину у низа экрана.
  Rect _blockRect(double towerY, double fieldX, double width) {
    final baseY = size.y - _bottomInset;
    // Сколько блок ниже камеры (в строках): отрицательное — выше камеры.
    final rowsBelowCam = _camHeight - towerY;
    final top = baseY - (rowsBelowCam + 1) * _rowHeight;
    return Rect.fromLTWH(
      _fieldLeft + fieldX * _scaleX,
      top,
      width * _scaleX,
      _rowHeight,
    );
  }

  /// Палитра блоков по высоте — мягкий радужный градиент по башне.
  Color _blockColor(int towerY) {
    final hue = (200 + towerY * 14) % 360;
    return HSVColor.fromAHSV(1, hue.toDouble(), 0.55, 0.95).toColor();
  }

  void _drawBlock(Canvas canvas, Rect rect, Color color, {bool glow = false}) {
    final inset = rect.deflate(min(2, _rowHeight * 0.08));
    final rr =
        RRect.fromRectAndRadius(inset, Radius.circular(_rowHeight * 0.18));
    if (glow) {
      canvas.drawRRect(
        rr.inflate(2),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawRRect(rr, Paint()..color = color);
    // Блик сверху для объёма.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(inset.left, inset.top, inset.width, inset.height * 0.34),
        Radius.circular(_rowHeight * 0.18),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  void _drawTower(Canvas canvas) {
    final tower = _logic.tower;
    // Рисуем только видимый диапазон уровней (+ запас на доводчик камеры).
    final lowest = max(0, _camHeight.floor() - _visibleRows);
    for (var y = lowest; y < tower.length; y++) {
      final b = tower[y];
      _drawBlock(canvas, _blockRect(y.toDouble(), b.left, b.width),
          _blockColor(y));
    }
  }

  void _drawMover(Canvas canvas) {
    _drawBlock(
      canvas,
      _blockRect(_logic.height.toDouble() + 1, _logic.currentLeft,
          _logic.currentWidth),
      _blockColor(_logic.height + 1),
      glow: true,
    );
  }

  void _drawSlabs(Canvas canvas) {
    for (final s in _slabs) {
      final k = (1 - s.age / _Slab.duration).clamp(0.0, 1.0);
      final base = _blockRect(s.towerY, s.fieldX, s.width);
      final rect = base.translate(s.fallX * _scaleX, s.fallY);
      final rr = RRect.fromRectAndRadius(
        rect.deflate(min(2, _rowHeight * 0.08)),
        Radius.circular(_rowHeight * 0.18),
      );
      canvas.drawRRect(rr, Paint()..color = s.color.withValues(alpha: k));
    }
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      final base = _blockRect(s.towerY, s.fieldX, 0);
      final center = Offset(base.left, base.center.dy) + s.pos;
      canvas.drawCircle(
        center,
        _rowHeight * 0.14 * k,
        Paint()..color = s.color.withValues(alpha: k.clamp(0.0, 1.0)),
      );
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in _popups) {
      final k = p.age / _Popup.duration;
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = (p.big ? 1.0 : 0.7) * (1 + 0.3 * (1 - k));
      final base = _blockRect(p.towerY, p.fieldX, 0);
      final center =
          Offset(base.left, base.center.dy) - Offset(0, k * _rowHeight * 1.6);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(alpha: alpha),
            fontSize: _rowHeight * 0.9 * scale,
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
    required this.fieldX,
    required this.towerY,
    required this.vel,
    required this.life,
    required this.color,
  });
  final double fieldX;
  final double towerY;
  Offset pos = Offset.zero;
  Offset vel;
  final double life;
  final Color color;
  double age = 0;
}

/// Падающий отрезанный кусок (или весь промах) — рисуется со смещением вниз.
class _Slab {
  _Slab({
    required this.fieldX,
    required this.towerY,
    required this.width,
    required this.vx,
    required this.color,
  });
  static const double duration = 1.1;
  final double fieldX;
  final double towerY;
  final double width;
  final Color color;
  double vx; // снос по горизонтали (единиц поля/сек)
  double vy = 0; // падение (пиксели/сек)
  double fallX = 0; // накопленный снос (единиц поля)
  double fallY = 0; // накопленное падение (пиксели)
  double age = 0;
}

class _Popup {
  _Popup({
    required this.towerY,
    required this.fieldX,
    required this.text,
    required this.color,
    this.big = false,
  });
  static const double duration = 1.0;
  final double towerY;
  final double fieldX;
  final String text;
  final Color color;
  final bool big;
  double age = 0;
}
