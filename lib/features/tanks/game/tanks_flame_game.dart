import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../logic/tank_entities.dart';
import '../logic/tank_geometry.dart';
import '../logic/tank_grid.dart';
import '../logic/tank_step.dart';
import '../logic/tanks_logic.dart';
import 'demo_level.dart';

/// Фаза партии (управляет показываемым оверлеем).
enum TanksPhase { ready, running, dead }

/// Flame-слой «Танчиков»: гоняет [TanksLogic] и рисует поле/танки/пули с «соком».
/// Вся симуляция — в чистой логике; здесь только тайминг, ввод, рендер и фидбек.
///
/// ВАЖНО: нотифаер паузы — [isPaused] (не `paused`: конфликт с `FlameGame.paused`).
class TanksFlameGame extends FlameGame {
  TanksFlameGame({required this.onGameOver});

  /// Вызывается при конце партии: счёт и победа/поражение (для рекордов/оверлея).
  final void Function(int score, bool win) onGameOver;

  late TanksLogic _logic;
  final Random _rng = Random();

  // ── HUD-нотифаеры ──────────────────────────────────────────────────────────
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> lives = ValueNotifier(3);
  final ValueNotifier<int> enemiesLeft = ValueNotifier(0);
  final ValueNotifier<int> stage = ValueNotifier(1);
  final ValueNotifier<double> fps = ValueNotifier(0);
  final ValueNotifier<TanksPhase> phase = ValueNotifier(TanksPhase.ready);
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  bool get _running => phase.value == TanksPhase.running;
  bool get _active => _running && !isPaused.value;

  // ── Ввод ───────────────────────────────────────────────────────────────────
  Dir? _moveDir;
  bool _fireHeld = false;

  void setMoveDir(Dir? d) => _moveDir = d;
  void setFire(bool held) => _fireHeld = held;

  // ── Эффекты («сок») ─────────────────────────────────────────────────────────
  final List<_Spark> _sparks = [];
  final List<_Popup> _popups = [];
  double _shake = 0;
  double _flash = 0;
  Color _flashColor = Colors.white;
  double _time = 0;

  double _fpsAcc = 0;
  int _fpsFrames = 0;

  // ── Геометрия (пиксели) ──────────────────────────────────────────────────────
  double _u = 0; // пикселей на суб-клетку
  double _fieldPx = 0;
  Offset _origin = Offset.zero;

  static const double _topInset = 92;
  static const double _bottomInset = 196;

  @override
  Future<void> onLoad() async {
    _logic = buildDemoLevel(random: _rng);
    enemiesLeft.value = _logic.enemiesAlive + _logic.enemiesRemaining;
    await super.onLoad();
  }

  // ── Управление состоянием ────────────────────────────────────────────────────
  void start() {
    _logic = buildDemoLevel(random: _rng);
    score.value = 0;
    lives.value = _logic.lives;
    enemiesLeft.value = _logic.enemiesAlive + _logic.enemiesRemaining;
    stage.value = 1;
    _moveDir = null;
    _fireHeld = false;
    _sparks.clear();
    _popups.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = TanksPhase.running;
  }

  void togglePause() {
    if (!_running) return;
    isPaused.value = !isPaused.value;
    if (isPaused.value) {
      _moveDir = null;
      _fireHeld = false;
    }
  }

  /// Вернуться на стартовый экран (используется кнопкой «В меню», пока нет
  /// домашней витрины из фазы 5). Готовит свежий уровень как фон.
  void toReady() {
    _logic = buildDemoLevel(random: _rng);
    enemiesLeft.value = _logic.enemiesAlive + _logic.enemiesRemaining;
    score.value = 0;
    lives.value = _logic.lives;
    _moveDir = null;
    _fireHeld = false;
    _sparks.clear();
    _popups.clear();
    _shake = 0;
    _flash = 0;
    isPaused.value = false;
    phase.value = TanksPhase.ready;
  }

  // ── Игровой цикл ──────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;

    _fpsFrames++;
    _fpsAcc += dt;
    if (_fpsAcc >= 0.5) {
      fps.value = _fpsFrames / _fpsAcc;
      _fpsFrames = 0;
      _fpsAcc = 0;
    }

    _advanceEffects(dt);
    if (!_active) return;

    final clamped = dt > 0.05 ? 0.05 : dt;
    final res = _logic.step(clamped, PlayerIntent(move: _moveDir, fire: _fireHeld));
    _applyStep(res);
  }

  void _applyStep(TankStep s) {
    if (s.bulletsSpawned.isNotEmpty) {
      for (final b in s.bulletsSpawned) {
        _spawnChips(b.center, const Color(0xFFFFE08A), count: 3, speed: 70);
      }
      Haptics.light();
    }
    for (final d in s.tanksDestroyed) {
      _spawnExplosion(d.center, _kindColor(d.kind));
      _popups.add(_Popup(d.center, '+${d.score}', const Color(0xFFFFD54F), big: true));
      _shake = max(_shake, 0.5);
      Haptics.heavy();
    }
    for (final b in s.bricksHit) {
      _spawnChips(b.center, const Color(0xFFC56A4E), count: 8);
    }
    for (final h in s.steelHits) {
      _spawnChips(h.center, const Color(0xFFB7BECC), count: 5, speed: 120);
      Haptics.select();
    }
    for (final c in s.bulletClashes) {
      _spawnChips(c, Colors.white, count: 7, speed: 130);
    }
    for (final f in s.spawnFlashes) {
      _spawnChips(f, const Color(0xFF8AB4FF), count: 12, speed: 130);
    }
    for (final e in s.powerUpsSpawned) {
      _spawnChips(e.center, _powerColor(e.type), count: 8, speed: 90);
    }
    for (final e in s.powerUpsTaken) {
      _spawnExplosion(e.center, _powerColor(e.type));
      _popups.add(_Popup(e.center, _powerLabel(e.type), _powerColor(e.type),
          big: true));
      Haptics.combo(3);
    }
    if (s.gainedScore > 0) score.value = _logic.score;
    if (s.playerHit) {
      lives.value = _logic.lives;
      _shake = max(_shake, 0.7);
      _flash = max(_flash, 0.5);
      _flashColor = const Color(0xFFFF5370);
      Haptics.heavy();
    }
    if (s.baseHit) {
      _shake = 1;
      _flash = max(_flash, 0.6);
      _flashColor = const Color(0xFFFF5370);
      Haptics.heavy();
    }
    if (s.waveCleared) {
      _flash = max(_flash, 0.4);
      _flashColor = const Color(0xFF5CE08A);
      _popups.add(_Popup(const Point(0.5, 0.42), 'ЗАЧИЩЕНО!', const Color(0xFF5CE08A), big: true));
      Haptics.heavy();
    }
    enemiesLeft.value = _logic.enemiesAlive + _logic.enemiesRemaining;

    if (s.gameOver) {
      onGameOver(_logic.score, _logic.won);
      phase.value = TanksPhase.dead;
    }
  }

  // ── Эффекты ────────────────────────────────────────────────────────────────
  void _spawnExplosion(Point<double> n, Color color) {
    final p = _pxN(n);
    for (var i = 0; i < 20; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final sp = 50 + _rng.nextDouble() * 190;
      _sparks.add(_Spark(p, Offset(cos(a), sin(a)) * sp,
          0.4 + _rng.nextDouble() * 0.5, color));
    }
  }

  void _spawnChips(Point<double> n, Color color, {int count = 8, double speed = 150}) {
    final p = _pxN(n);
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final sp = speed * (0.4 + _rng.nextDouble() * 0.8);
      _sparks.add(_Spark(p, Offset(cos(a), sin(a)) * sp,
          0.25 + _rng.nextDouble() * 0.35, color));
    }
  }

  void _advanceEffects(double dt) {
    _shake = max(0, _shake - dt * 2.4);
    _flash = max(0, _flash - dt * 1.8);
    for (final s in _sparks) {
      s.disp += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.6 * dt), s.vel.dy + 240 * dt);
      s.age += dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);
    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= _Popup.duration);
  }

  // ── Рендер ────────────────────────────────────────────────────────────────
  @override
  Color backgroundColor() => const Color(0xFF0A0814);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _computeGeometry();
    if (_fieldPx <= 0) return;

    if (_shake > 0) {
      final m = _shake * _shake * 9;
      canvas.save();
      canvas.translate(
          (_rng.nextDouble() * 2 - 1) * m, (_rng.nextDouble() * 2 - 1) * m);
    }

    _drawFieldFrame(canvas);
    _drawTerrain(canvas);
    _drawEagle(canvas);
    _drawPowerUps(canvas);
    _drawTanks(canvas);
    _drawBullets(canvas);
    _drawForest(canvas); // полог поверх танков — укрытие
    _drawSparks(canvas);
    _drawPopups(canvas);

    if (_shake > 0) canvas.restore();

    if (_flash > 0) {
      canvas.drawRect(Offset.zero & Size(size.x, size.y),
          Paint()..color = _flashColor.withValues(alpha: _flash * 0.45));
    }
  }

  void _computeGeometry() {
    final availH = size.y - _topInset - _bottomInset;
    if (availH <= 0 || size.x <= 0) {
      _fieldPx = 0;
      return;
    }
    _fieldPx = min(size.x - 20, availH);
    _u = _fieldPx / TankGeo.field;
    _origin = Offset((size.x - _fieldPx) / 2, _topInset + (availH - _fieldPx) / 2);
  }

  Offset _px(num subX, num subY) =>
      _origin + Offset(subX * _u, subY * _u);

  Offset _pxN(Point<double> n) =>
      _origin + Offset(n.x * _fieldPx, n.y * _fieldPx);

  double get _tilePx => TankGeo.sub * _u;

  void _drawFieldFrame(Canvas canvas) {
    final rect = _origin & Size(_fieldPx, _fieldPx);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(_u * 2));
    canvas.drawRRect(rr, Paint()..color = const Color(0xFF120F22));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF241B3E));
  }

  void _drawTerrain(Canvas canvas) {
    final g = _logic.grid;
    final tp = _tilePx;
    for (var ty = 0; ty < TankGeo.tiles; ty++) {
      for (var tx = 0; tx < TankGeo.tiles; tx++) {
        final o = _px(tx * TankGeo.sub, ty * TankGeo.sub);
        switch (g.typeAt(tx, ty)) {
          case TerrainType.brick:
            _drawBrick(canvas, o, tp, g.quadMaskAt(tx, ty));
          case TerrainType.steel:
            _drawSteel(canvas, o, tp);
          case TerrainType.water:
            _drawWater(canvas, o, tp);
          case TerrainType.ice:
            _drawIce(canvas, o, tp);
          case TerrainType.empty:
          case TerrainType.forest:
          case TerrainType.base:
            break;
        }
      }
    }
  }

  void _drawBrick(Canvas canvas, Offset o, double tp, int mask) {
    final q = tp / 2;
    for (var i = 0; i < 4; i++) {
      if ((mask & (1 << i)) == 0) continue;
      final qx = i % 2;
      final qy = i ~/ 2;
      final r = Rect.fromLTWH(o.dx + qx * q, o.dy + qy * q, q, q).deflate(0.7);
      canvas.drawRect(r, Paint()..color = const Color(0xFFB5563C));
      canvas.drawRect(
          Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.34),
          Paint()..color = const Color(0xFFD17A55).withValues(alpha: 0.55));
    }
  }

  void _drawSteel(Canvas canvas, Offset o, double tp) {
    final r = Rect.fromLTWH(o.dx, o.dy, tp, tp).deflate(0.8);
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(tp * 0.12)),
        Paint()..color = const Color(0xFF8A93A8));
    canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(tp * 0.18), Radius.circular(tp * 0.1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.35));
  }

  void _drawWater(Canvas canvas, Offset o, double tp) {
    final r = Rect.fromLTWH(o.dx, o.dy, tp, tp);
    canvas.drawRect(r, Paint()..color = const Color(0xFF173A8C));
    final band = 0.5 + 0.5 * sin(_time * 2 + o.dx * 0.05);
    canvas.drawRect(
        Rect.fromLTWH(o.dx, o.dy + tp * 0.3 * band, tp, tp * 0.18),
        Paint()..color = const Color(0xFF4F7BE0).withValues(alpha: 0.5));
  }

  void _drawIce(Canvas canvas, Offset o, double tp) {
    final r = Rect.fromLTWH(o.dx, o.dy, tp, tp).deflate(0.5);
    // Полупрозрачная «наледь» + лёгкая окантовка и блик — читается как пол,
    // по которому можно ехать (а не сплошной блок-стена).
    canvas.drawRect(
        r, Paint()..color = const Color(0xFFBFE9FF).withValues(alpha: 0.28));
    canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF9CD7F5).withValues(alpha: 0.5));
    canvas.drawLine(
        Offset(r.left, r.top + tp * 0.32),
        Offset(r.left + tp * 0.32, r.top),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..strokeWidth = 1.2);
  }

  void _drawForest(Canvas canvas) {
    final g = _logic.grid;
    final tp = _tilePx;
    for (var ty = 0; ty < TankGeo.tiles; ty++) {
      for (var tx = 0; tx < TankGeo.tiles; tx++) {
        if (g.typeAt(tx, ty) != TerrainType.forest) continue;
        final o = _px(tx * TankGeo.sub, ty * TankGeo.sub);
        canvas.drawRect(Rect.fromLTWH(o.dx, o.dy, tp, tp),
            Paint()..color = const Color(0xFF1E7A3E).withValues(alpha: 0.82));
      }
    }
  }

  void _drawEagle(Canvas canvas) {
    final e = _logic.eagle;
    final o = _px(e.tileX * TankGeo.sub, e.tileY * TankGeo.sub);
    final tp = _tilePx;
    final r = Rect.fromLTWH(o.dx, o.dy, tp, tp).deflate(tp * 0.1);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(tp * 0.14));
    if (e.destroyed) {
      canvas.drawRRect(rr, Paint()..color = const Color(0xFF3A3340));
      final p = Paint()
        ..color = const Color(0xFF8A2030)
        ..strokeWidth = tp * 0.12
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(r.topLeft, r.bottomRight, p);
      canvas.drawLine(r.topRight, r.bottomLeft, p);
      return;
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(2), Radius.circular(tp * 0.14)),
        Paint()
          ..color = const Color(0xFFFFD54F).withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawRRect(rr, Paint()..color = const Color(0xFFFFD54F));
    canvas.drawCircle(r.center, tp * 0.2, Paint()..color = const Color(0xFF2A1E05));
  }

  void _drawTanks(Canvas canvas) {
    for (final t in _logic.tanks) {
      _drawTank(canvas, t);
    }
  }

  void _drawTank(Canvas canvas, Tank t) {
    // Плавное движение: рисуем с учётом накопленной дробной части шага — иначе
    // целочисленные суб-клетки дают рывки («резкое» управление).
    final fx = t.sx + t.moveAccum * t.dir.dx;
    final fy = t.sy + t.moveAccum * t.dir.dy;
    final o = _px(fx, fy);
    final s = TankGeo.tankSize * _u;
    final rect = Rect.fromLTWH(o.dx, o.dy, s, s).deflate(s * 0.09);
    final color = t.isPlayer ? const Color(0xFF4ECDC4) : _kindColor(t.kind);
    final c = rect.center;

    if (t.isPlayer || t.kind == TankKind.boss) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(2), Radius.circular(s * 0.18)),
          Paint()
            ..color = color.withValues(alpha: 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }

    // Корпус + тонкая тёмная окантовка (чтобы танк не сливался с терреином).
    final hull = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.16));
    canvas.drawRRect(hull, Paint()..color = color);
    canvas.drawRRect(
        hull,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1, s * 0.045)
          ..color = Colors.black.withValues(alpha: 0.4));
    // Гусеницы (тонкие тёмные полосы по бокам относительно направления).
    final tread = Paint()..color = Colors.black.withValues(alpha: 0.26);
    if (t.dir.isHorizontal) {
      canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.12), tread);
      canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.bottom - rect.height * 0.12, rect.width,
              rect.height * 0.12),
          tread);
    } else {
      canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, rect.width * 0.12, rect.height), tread);
      canvas.drawRect(
          Rect.fromLTWH(rect.right - rect.width * 0.12, rect.top,
              rect.width * 0.12, rect.height),
          tread);
    }
    // Башня (компактнее).
    canvas.drawCircle(
        c, s * 0.15, Paint()..color = Colors.black.withValues(alpha: 0.32));
    // Ствол (тоньше и короче).
    final dir = Offset(t.dir.dx.toDouble(), t.dir.dy.toDouble());
    canvas.drawLine(
        c,
        c + dir * (s * 0.42),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..strokeWidth = s * 0.085
          ..strokeCap = StrokeCap.round);
    // Щит.
    if (t.shielded) {
      canvas.drawCircle(
          c,
          s * 0.64,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF8AB4FF)
                .withValues(alpha: 0.45 + 0.35 * sin(_time * 7).abs()));
    }
  }

  void _drawBullets(Canvas canvas) {
    for (final b in _logic.bullets) {
      final p = _px(b.x, b.y);
      final r = max(2.0, _u * 1.7);
      final dir = Offset(b.dir.dx.toDouble(), b.dir.dy.toDouble());
      canvas.drawLine(
          p,
          p - dir * (r * 3.2),
          Paint()
            ..color = const Color(0xFFFFE08A).withValues(alpha: 0.5)
            ..strokeWidth = r
            ..strokeCap = StrokeCap.round);
      canvas.drawCircle(p, r, Paint()..color = Colors.white);
    }
  }

  void _drawSparks(Canvas canvas) {
    for (final s in _sparks) {
      final k = (1 - s.age / s.life).clamp(0.0, 1.0);
      canvas.drawCircle(s.start + s.disp, max(1.0, _u * 1.4) * k,
          Paint()..color = s.color.withValues(alpha: k));
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final pp in _popups) {
      final k = pp.age / _Popup.duration;
      final alpha = (1 - k).clamp(0.0, 1.0);
      final scale = (pp.big ? 1.0 : 0.7) * (1 + 0.3 * (1 - k));
      final center = _pxN(pp.pos) - Offset(0, k * _fieldPx * 0.06);
      final tp = TextPainter(
        text: TextSpan(
          text: pp.text,
          style: TextStyle(
            color: pp.color.withValues(alpha: alpha),
            fontSize: _fieldPx * 0.05 * scale,
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

  void _drawPowerUps(Canvas canvas) {
    final tp = _tilePx;
    for (final p in _logic.powerUps) {
      final o = _px(p.tileX * TankGeo.sub, p.tileY * TankGeo.sub);
      final r = Rect.fromLTWH(o.dx, o.dy, tp, tp).deflate(tp * 0.12);
      final blink = 0.5 + 0.5 * sin(p.blink * 6);
      final color = _powerColor(p.type);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(2), Radius.circular(tp * 0.2)),
          Paint()
            ..color = color.withValues(alpha: 0.35 * blink)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(tp * 0.18)),
          Paint()..color = color.withValues(alpha: 0.9));
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.deflate(tp * 0.24), Radius.circular(tp * 0.1)),
          Paint()..color = Colors.white.withValues(alpha: 0.9));
    }
  }

  Color _powerColor(PowerUpType t) => switch (t) {
        PowerUpType.star => const Color(0xFFFFD54F),
        PowerUpType.grenade => const Color(0xFFFF5370),
        PowerUpType.helmet => const Color(0xFF8AB4FF),
        PowerUpType.shovel => const Color(0xFFB7BECC),
        PowerUpType.life => const Color(0xFF5CE08A),
        PowerUpType.freeze => const Color(0xFF4ECDC4),
      };

  String _powerLabel(PowerUpType t) => switch (t) {
        PowerUpType.star => 'СИЛА',
        PowerUpType.grenade => 'БУМ!',
        PowerUpType.helmet => 'ЩИТ',
        PowerUpType.shovel => 'БРОНЯ',
        PowerUpType.life => '+ЖИЗНЬ',
        PowerUpType.freeze => 'СТОП',
      };

  Color _kindColor(TankKind k) => switch (k) {
        TankKind.player => const Color(0xFF4ECDC4),
        TankKind.basic => const Color(0xFFD6B789),
        TankKind.fast => const Color(0xFFFF9F45),
        TankKind.power => const Color(0xFFFF5370),
        TankKind.armor => const Color(0xFFB388FF),
        TankKind.boss => const Color(0xFFFF6FAE),
      };
}

/// Частица «сока»: стартовая точка (пиксели) + накопленное смещение, скорость,
/// время жизни, цвет.
class _Spark {
  _Spark(this.start, this.vel, this.life, this.color);

  final Offset start;
  Offset disp = Offset.zero;
  Offset vel;
  final double life;
  final Color color;
  double age = 0;
}

/// Всплывающий текст (очки/«зачищено»). Позиция — нормализованная.
class _Popup {
  _Popup(this.pos, this.text, this.color, {this.big = false});

  static const double duration = 1.0;

  final Point<double> pos;
  final String text;
  final Color color;
  final bool big;
  double age = 0;
}
