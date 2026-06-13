import 'dart:math';

import 'run_config.dart';
import 'tank_entities.dart';
import 'tank_geometry.dart';
import 'tank_grid.dart';
import 'tank_step.dart';

/// Намерение игрока на кадр: направление движения (null — стоять, держа лицо)
/// и флаг выстрела.
class PlayerIntent {
  const PlayerIntent({this.move, this.fire = false});

  final Dir? move;
  final bool fire;

  static const PlayerIntent idle = PlayerIntent();
}

/// Чистая симуляция боя «Танчиков». Только `dart:math`, инъекция [Random].
///
/// Кадр [step]: клампит dt → продвигает таймеры → двигает танки (целыми
/// суб-клетками из накопителя) → стреляет → интегрирует пули свип-субшагом
/// (анти-туннелинг) → разрешает коллизии в фиксированном приоритете → проверяет
/// победу/поражение и возвращает [TankStep] с исходами для «сока».
///
/// Враги/AI/спавн-директор/бонусы подключаются со следующих фаз; здесь —
/// проверяемое движение, стрельба, разрушение, win/lose.
class TanksLogic {
  TanksLogic({
    required this.grid,
    required this.eagle,
    required this.player,
    List<Tank> enemies = const [],
    this.enemiesRemaining = 0,
    this.config = RunConfig.campaign,
    Random? random,
  })  : _rng = random ?? Random(),
        tanks = [player, ...enemies],
        lives = config.startLives {
    _spawnX = player.sx;
    _spawnY = player.sy;
    _spawnDir = player.dir;
  }

  final TerrainGrid grid;
  final Eagle eagle;
  final Tank player;
  final RunConfig config;
  final Random _rng;

  /// Танки в стабильном порядке (игрок — индекс 0). Порядок не менять —
  /// от него зависит детерминизм.
  final List<Tank> tanks;
  final List<Bullet> bullets = [];
  final List<PowerUp> powerUps = [];

  int score = 0;
  int lives;

  /// Сколько врагов ещё предстоит заспавнить (условие зачистки уровня).
  int enemiesRemaining;

  bool over = false;
  bool won = false;

  int _idSeq = 1000;
  late final int _spawnX;
  late final int _spawnY;
  late final Dir _spawnDir;

  static const double _bulletStepCap = 2; // ≤ четверть тайла за субшаг
  static const double _bulletClashRadius = 3;
  static const double _respawnShield = 1.5;

  /// ГПСЧ симуляции (детерминизм «Дейли»). Используется AI/спавном со след. фазы.
  Random get rng => _rng;

  int get enemiesAlive => tanks.where((t) => !t.isPlayer && t.alive).length;

  int _nextId() => ++_idSeq;

  Point<double> _npt(num x, num y) => Point(TankGeo.norm(x), TankGeo.norm(y));

  /// Главный шаг симуляции.
  TankStep step(double dt, PlayerIntent intent) {
    final out = TankStep();
    if (over) return out;
    if (dt <= 0) return out;
    if (dt > 0.05) dt = 0.05;

    _advanceTimers(dt);
    _moveTanks(dt, intent);
    _fire(intent, out);
    _moveBullets(dt, out);
    _advancePowerUps(dt);
    _resolveOutcome(out);
    return out;
  }

  // ── Таймеры ────────────────────────────────────────────────────────────────
  void _advanceTimers(double dt) {
    for (final t in tanks) {
      if (t.fireCooldown > 0) t.fireCooldown -= dt;
      if (t.shieldTimer > 0) t.shieldTimer -= dt;
      if (t.freezeTimer > 0) t.freezeTimer -= dt;
      if (t.decisionTimer > 0) t.decisionTimer -= dt;
    }
  }

  // ── Движение танков ──────────────────────────────────────────────────────
  void _moveTanks(double dt, PlayerIntent intent) {
    _steer(player, player.frozen ? null : intent.move, dt);
    // Враги двигаются в фазе AI; на этой фазе стоят.
  }

  void _steer(Tank t, Dir? desired, double dt) {
    t.moved = false;
    if (t.frozen) return;

    // Дрифт по льду доезжает, даже если игрок отпустил ввод.
    if (t.slideRemaining > 0) {
      if (_tryStep(t)) {
        t.slideRemaining--;
        t.moved = true;
      } else {
        t.slideRemaining = 0;
      }
    }

    if (desired == null) {
      t.moveAccum = 0;
      return;
    }

    if (desired != t.dir) {
      t.dir = desired;
      if (desired.isHorizontal) {
        t.sy = TankGeo.alignToHalf(t.sy).clamp(0, TankGeo.maxOrigin);
      } else {
        t.sx = TankGeo.alignToHalf(t.sx).clamp(0, TankGeo.maxOrigin);
      }
    }

    t.moveAccum += t.spec.speed * dt;
    while (t.moveAccum >= 1) {
      if (_tryStep(t)) {
        t.moveAccum -= 1;
        t.moved = true;
      } else {
        t.moveAccum = 0;
        break;
      }
    }
  }

  /// Попытка сдвинуть танк на 1 суб-клетку по его текущему направлению.
  bool _tryStep(Tank t) {
    final nx = t.sx + t.dir.dx;
    final ny = t.sy + t.dir.dy;
    if (nx < 0 || nx > TankGeo.maxOrigin || ny < 0 || ny > TankGeo.maxOrigin) {
      return false;
    }
    if (_terrainBlocks(nx, ny, t.dir)) return false;
    if (_tankBlocks(t, nx, ny)) return false;
    t.sx = nx;
    t.sy = ny;
    return true;
  }

  /// Терреин на ведущей кромке нового AABB.
  bool _terrainBlocks(int nx, int ny, Dir dir) {
    const size = TankGeo.tankSize;
    if (dir.isHorizontal) {
      final x = dir == Dir.right ? nx + size - 1 : nx;
      for (var y = ny; y < ny + size; y++) {
        if (grid.solidForTank(x, y)) return true;
      }
    } else {
      final y = dir == Dir.down ? ny + size - 1 : ny;
      for (var x = nx; x < nx + size; x++) {
        if (grid.solidForTank(x, y)) return true;
      }
    }
    return false;
  }

  bool _tankBlocks(Tank self, int nx, int ny) {
    const size = TankGeo.tankSize;
    for (final o in tanks) {
      if (identical(o, self) || !o.alive) continue;
      if (nx < o.sx + size &&
          nx + size > o.sx &&
          ny < o.sy + size &&
          ny + size > o.sy) {
        return true;
      }
    }
    return false;
  }

  // ── Стрельба ─────────────────────────────────────────────────────────────
  void _fire(PlayerIntent intent, TankStep out) {
    if (!player.frozen &&
        intent.fire &&
        player.fireCooldown <= 0 &&
        _bulletsOf(player.id) < _maxBullets(player)) {
      _spawnBullet(player, out);
      player.fireCooldown = player.spec.fireCooldown;
    }
    // Враги стреляют в фазе AI.
  }

  int _bulletsOf(int ownerId) =>
      bullets.where((b) => !b.dead && b.ownerId == ownerId).length;

  int _maxBullets(Tank t) => (t.isPlayer && t.tier >= 2) ? 2 : 1;

  void _spawnBullet(Tank t, TankStep out) {
    const muzzle = TankGeo.tankSize / 2;
    final x = t.cx + t.dir.dx * muzzle;
    final y = t.cy + t.dir.dy * muzzle;
    final power = (t.isPlayer && t.tier >= 3) ? kSteelBreakPower : 1;
    bullets.add(Bullet(
      id: _nextId(),
      ownerId: t.id,
      owner: t.isPlayer ? BulletOwner.player : BulletOwner.enemy,
      x: x.toDouble(),
      y: y.toDouble(),
      dir: t.dir,
      speed: t.spec.bulletSpeed,
      power: power,
    ));
    out.bulletsSpawned.add(BulletSpawned(
      center: _npt(x, y),
      dir: t.dir,
      byPlayer: t.isPlayer,
    ));
  }

  // ── Пули: свип-субшаг + коллизии ─────────────────────────────────────────
  void _moveBullets(double dt, TankStep out) {
    for (final b in bullets) {
      if (b.dead) continue;
      final dist = b.speed * dt;
      final steps = max(1, (dist / _bulletStepCap).ceil());
      final h = dist / steps;
      for (var i = 0; i < steps && !b.dead; i++) {
        b.x += b.dir.dx * h;
        b.y += b.dir.dy * h;
        _resolveBullet(b, out);
      }
    }
    bullets.removeWhere((b) => b.dead);
  }

  void _resolveBullet(Bullet b, TankStep out) {
    // 1. Границы поля.
    if (b.x < 0 || b.x >= TankGeo.field || b.y < 0 || b.y >= TankGeo.field) {
      b.dead = true;
      return;
    }
    // 2. Пуля ↔ встречная пуля (свои проходят насквозь).
    for (final o in bullets) {
      if (o.dead || identical(o, b) || o.owner == b.owner) continue;
      if ((o.x - b.x).abs() < _bulletClashRadius &&
          (o.y - b.y).abs() < _bulletClashRadius) {
        b.dead = true;
        o.dead = true;
        out.bulletClashes.add(_npt(b.x, b.y));
        return;
      }
    }
    // 3. Пуля ↔ танк (только встречная сторона; дружественный огонь выключен).
    for (final t in tanks) {
      if (!t.alive || t.isPlayer == b.byPlayer) continue;
      if (b.x >= t.sx &&
          b.x < t.sx + TankGeo.tankSize &&
          b.y >= t.sy &&
          b.y < t.sy + TankGeo.tankSize) {
        b.dead = true;
        _hitTank(t, b, out);
        return;
      }
    }
    // 4. База / терреин.
    final fx = b.x.floor();
    final fy = b.y.floor();
    final tx = fx ~/ TankGeo.sub;
    final ty = fy ~/ TankGeo.sub;
    if (!eagle.destroyed && tx == eagle.tileX && ty == eagle.tileY) {
      b.dead = true;
      eagle.destroyed = true;
      out.baseHit = true;
      return;
    }
    final type = grid.typeAt(tx, ty);
    if (type == TerrainType.brick) {
      if (grid.chipBrick(fx, fy)) {
        b.dead = true;
        out.bricksHit.add(BrickHit(_npt(b.x, b.y)));
      }
    } else if (type == TerrainType.steel) {
      b.dead = true;
      if (b.power >= kSteelBreakPower) {
        grid.breakSteel(tx, ty);
        out.bricksHit.add(BrickHit(_npt(b.x, b.y)));
      } else {
        out.steelHits.add(SteelHit(_npt(b.x, b.y)));
      }
    } else if (type == TerrainType.base) {
      b.dead = true;
      eagle.destroyed = true;
      out.baseHit = true;
    }
    // empty / water / forest / ice — пуля пролетает.
  }

  void _hitTank(Tank t, Bullet b, TankStep out) {
    if (t.isPlayer) {
      if (t.shielded) return;
      out.playerHit = true;
      lives--;
      if (lives <= 0) {
        t.hp = 0;
      } else {
        _respawnPlayer(t);
      }
    } else {
      t.hp--;
      if (!t.alive) {
        out.tanksDestroyed.add(TankDestroyed(
          kind: t.kind,
          center: t.centerNorm,
          byPlayer: b.byPlayer,
          score: t.spec.score,
        ));
        score += t.spec.score;
        out.gainedScore += t.spec.score;
      }
    }
  }

  void _respawnPlayer(Tank t) {
    t.sx = _spawnX;
    t.sy = _spawnY;
    t.dir = _spawnDir;
    t.moveAccum = 0;
    t.slideRemaining = 0;
    t.shieldTimer = _respawnShield;
    if (t.tier > 0) t.tier--; // мягче аркады: минус один тир, не полный сброс
  }

  // ── Бонусы (истечение; подбор/эффекты — в фазе 3) ────────────────────────
  void _advancePowerUps(double dt) {
    for (final p in powerUps) {
      p.timer -= dt;
      p.blink += dt;
    }
    powerUps.removeWhere((p) => p.timer <= 0);
  }

  // ── Победа/поражение ─────────────────────────────────────────────────────
  void _resolveOutcome(TankStep out) {
    tanks.removeWhere((t) => !t.isPlayer && !t.alive);

    if (eagle.destroyed || !player.alive) {
      _end(out, win: false);
      return;
    }
    if (enemiesAlive == 0 && enemiesRemaining == 0) {
      out.waveCleared = true;
      _end(out, win: true);
    }
  }

  void _end(TankStep out, {required bool win}) {
    if (over) return;
    over = true;
    won = win;
    out.gameOver = true;
    if (win) out.win = true;
  }
}
