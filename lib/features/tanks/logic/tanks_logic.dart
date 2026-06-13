import 'dart:math';

import 'run_config.dart';
import 'spawn_director.dart';
import 'tank_ai.dart';
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
/// Кадр [step]: клампит dt → таймеры → спавн врагов → решения AI → движение
/// (игрок + враги) → стрельба → пули (свип-субшаг, анти-туннелинг) → бонусы →
/// укрепление базы → итог (победа/поражение). Возвращает [TankStep] с исходами
/// для «сока». Итерация по стабильному индексу — детерминизм для «Дейли»/тестов.
class TanksLogic {
  TanksLogic({
    required this.grid,
    required this.eagle,
    required this.player,
    List<Tank> enemies = const [],
    int enemiesRemaining = 0,
    SpawnDirector? director,
    this.config = RunConfig.campaign,
    Random? random,
  })  : _rng = random ?? Random(),
        _director = director,
        _staticRemaining = enemiesRemaining,
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
  final SpawnDirector? _director;

  /// Танки в стабильном порядке (игрок — индекс 0). Порядок не менять.
  final List<Tank> tanks;
  final List<Bullet> bullets = [];
  final List<PowerUp> powerUps = [];

  int score = 0;
  int lives;

  bool over = false;
  bool won = false;

  final int _staticRemaining;
  int _idSeq = 1000;
  late final int _spawnX;
  late final int _spawnY;
  late final Dir _spawnDir;

  // Бонус «лопата»: укрепление базы сталью на время.
  double _shovelTimer = 0;
  final List<List<int>> _shovelSaved = []; // [tx, ty, typeIndex, quad]

  static const double _bulletStepCap = 2; // ≤ четверть тайла за субшаг
  static const double _bulletClashRadius = 3;
  static const double _respawnShield = 1.5;
  static const double _spawnShield = 2.0;

  /// ГПСЧ симуляции (детерминизм «Дейли»).
  Random get rng => _rng;

  SpawnDirector? get director => _director;

  /// Сколько врагов ещё предстоит заспавнить.
  int get enemiesRemaining => _director?.remaining ?? _staticRemaining;

  int get enemiesAlive => tanks.where((t) => !t.isPlayer && t.alive).length;

  int _nextId() => ++_idSeq;

  Point<double> _npt(num x, num y) => Point(TankGeo.norm(x), TankGeo.norm(y));

  // ── Главный шаг ───────────────────────────────────────────────────────────
  TankStep step(double dt, PlayerIntent intent) {
    final out = TankStep();
    if (over) return out;
    if (dt <= 0) return out;
    if (dt > 0.05) dt = 0.05;

    _advanceTimers(dt);
    _runSpawns(dt, out);
    _aiDecisions();
    _drive(player, player.frozen ? null : intent.move, dt);
    _moveEnemies(dt);
    _fireAll(intent, out);
    _moveBullets(dt, out);
    _advancePowerUps(dt, out);
    _advanceShovel(dt);
    _resolveOutcome(out);
    return out;
  }

  // ── Таймеры ─────────────────────────────────────────────────────────────
  void _advanceTimers(double dt) {
    for (final t in tanks) {
      if (t.fireCooldown > 0) t.fireCooldown -= dt;
      if (t.shieldTimer > 0) t.shieldTimer -= dt;
      if (t.freezeTimer > 0) t.freezeTimer -= dt;
      if (t.decisionTimer > 0) t.decisionTimer -= dt;
    }
  }

  // ── Спавн врагов ──────────────────────────────────────────────────────────
  void _runSpawns(double dt, TankStep out) {
    final d = _director;
    if (d == null) return;
    if (!d.ready(dt, enemiesAlive)) return;
    final tile = _freeSpawnTile(d.spawnTiles);
    if (tile == null) return;
    final kind = d.next();
    final e = Tank(
      id: _nextId(),
      kind: kind,
      sx: tile.x * TankGeo.sub,
      sy: tile.y * TankGeo.sub,
      dir: Dir.down,
      isPlayer: false,
    )
      ..shieldTimer = _spawnShield
      ..fireCooldown = kTankSpecs[kind]!.fireCooldown
      ..carriesBonus = _rng.nextDouble() < 0.28;
    tanks.add(e);
    out.spawnFlashes.add(e.centerNorm);
  }

  Point<int>? _freeSpawnTile(List<Point<int>> tiles) {
    for (final t in tiles) {
      if (!_areaOccupied(t.x * TankGeo.sub, t.y * TankGeo.sub)) return t;
    }
    return null;
  }

  bool _areaOccupied(int sx, int sy) {
    const size = TankGeo.tankSize;
    for (final o in tanks) {
      if (!o.alive) continue;
      if (sx < o.sx + size &&
          sx + size > o.sx &&
          sy < o.sy + size &&
          sy + size > o.sy) {
        return true;
      }
    }
    return false;
  }

  // ── Решения AI ────────────────────────────────────────────────────────────
  void _aiDecisions() {
    AiContext? ctx;
    for (final t in tanks) {
      if (t.isPlayer || !t.alive || t.frozen || t.decisionTimer > 0) continue;
      ctx ??= _buildAiContext();
      final cmd = decideAi(t, ctx, _rng);
      if (cmd.turnTo != null) _turn(t, cmd.turnTo!);
      t.wantsFire = cmd.fire;
      t.decisionTimer = 0.32 + _rng.nextDouble() * 0.42;
    }
  }

  AiContext _buildAiContext() => AiContext(
        baseX: eagle.tileX * TankGeo.sub + TankGeo.sub ~/ 2,
        baseY: eagle.tileY * TankGeo.sub + TankGeo.sub ~/ 2,
        playerX: player.cx,
        playerY: player.cy,
        playerAlive: player.alive,
        shouldFire: _shouldFire,
      );

  /// Луч вперёд: стрелять, если впереди база, игрок или кирпич (рыть); сталь —
  /// нет смысла.
  bool _shouldFire(Tank self) {
    var x = self.cx;
    var y = self.cy;
    for (var i = 0; i < TankGeo.tiles * 2; i++) {
      x += self.dir.dx * TankGeo.half;
      y += self.dir.dy * TankGeo.half;
      if (x < 0 || x >= TankGeo.field || y < 0 || y >= TankGeo.field) {
        return false;
      }
      final tx = x ~/ TankGeo.sub;
      final ty = y ~/ TankGeo.sub;
      if (tx == eagle.tileX && ty == eagle.tileY) return true;
      if (player.alive &&
          x >= player.sx &&
          x < player.sx + TankGeo.tankSize &&
          y >= player.sy &&
          y < player.sy + TankGeo.tankSize) {
        return true;
      }
      final type = grid.typeAt(tx, ty);
      if (type == TerrainType.steel) return false;
      if (type == TerrainType.brick) return true;
    }
    return false;
  }

  // ── Движение ──────────────────────────────────────────────────────────────
  void _moveEnemies(double dt) {
    for (final t in tanks) {
      if (t.isPlayer || !t.alive) continue;
      _drive(t, t.frozen ? null : t.dir, dt);
      if (!t.frozen && !t.moved && t.slideRemaining == 0) {
        // Упёрся — передумать скоро, но НЕ каждый кадр (иначе ствол «крутится»).
        t.decisionTimer = 0.18;
      }
    }
  }

  void _drive(Tank t, Dir? desired, double dt) {
    final wasMoving = t.wasMoving;
    t.moved = false;
    if (t.frozen) {
      t.wasMoving = false;
      return;
    }

    // Инерция на льду доезжает накопленное.
    if (t.slideRemaining > 0) {
      if (_tryStep(t)) {
        t.slideRemaining--;
        t.moved = true;
      } else {
        t.slideRemaining = 0;
      }
    }

    if (desired != null) {
      _turn(t, desired);
      if (_advance(t, dt)) t.moved = true;
    } else {
      t.moveAccum = 0;
    }

    // Остановка на льду запускает короткий дрифт.
    if (wasMoving && !t.moved && t.slideRemaining == 0 && _onIce(t)) {
      t.slideRemaining = kIceSlide;
    }
    t.wasMoving = t.moved || t.slideRemaining > 0;
  }

  void _turn(Tank t, Dir d) {
    if (t.dir == d) return;
    t.dir = d;
    if (d.isHorizontal) {
      t.sy = TankGeo.alignToHalf(t.sy).clamp(0, TankGeo.maxOrigin);
    } else {
      t.sx = TankGeo.alignToHalf(t.sx).clamp(0, TankGeo.maxOrigin);
    }
    t.moveAccum = 0;
  }

  bool _advance(Tank t, double dt) {
    t.moveAccum += t.spec.speed * dt;
    var moved = false;
    while (t.moveAccum >= 1) {
      if (_tryStep(t)) {
        t.moveAccum -= 1;
        moved = true;
      } else {
        t.moveAccum = 0;
        break;
      }
    }
    return moved;
  }

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

  bool _onIce(Tank t) =>
      grid.typeAt(t.cx ~/ TankGeo.sub, t.cy ~/ TankGeo.sub) == TerrainType.ice;

  // ── Стрельба ──────────────────────────────────────────────────────────────
  void _fireAll(PlayerIntent intent, TankStep out) {
    if (!player.frozen &&
        intent.fire &&
        player.fireCooldown <= 0 &&
        _bulletsOf(player.id) < _maxBullets(player)) {
      _spawnBullet(player, out);
      player.fireCooldown = player.spec.fireCooldown;
    }
    for (final t in tanks) {
      if (t.isPlayer || !t.alive || t.frozen) continue;
      if (t.wantsFire && t.fireCooldown <= 0 && _bulletsOf(t.id) < 1) {
        _spawnBullet(t, out);
        t.fireCooldown = t.spec.fireCooldown;
      }
    }
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
    if (b.x < 0 || b.x >= TankGeo.field || b.y < 0 || b.y >= TankGeo.field) {
      b.dead = true;
      return;
    }
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
        if (t.carriesBonus) _dropPowerUp(out);
      }
    }
  }

  void _respawnPlayer(Tank t) {
    t.sx = _spawnX;
    t.sy = _spawnY;
    t.dir = _spawnDir;
    t.moveAccum = 0;
    t.slideRemaining = 0;
    t.wasMoving = false;
    t.shieldTimer = _respawnShield;
    if (t.tier > 0) t.tier--; // мягче аркады: минус один тир, не полный сброс
  }

  // ── Бонусы ────────────────────────────────────────────────────────────────
  void _dropPowerUp(TankStep out) {
    final tile = _randomPowerUpTile();
    if (tile == null) return;
    final type = PowerUpType.values[_rng.nextInt(PowerUpType.values.length)];
    final p = PowerUp(type: type, tileX: tile.x, tileY: tile.y);
    powerUps.add(p);
    out.powerUpsSpawned.add(PowerUpEvent(type: type, center: p.centerNorm));
  }

  Point<int>? _randomPowerUpTile() {
    for (var attempt = 0; attempt < 16; attempt++) {
      final tx = _rng.nextInt(TankGeo.tiles);
      final ty = _rng.nextInt(TankGeo.tiles);
      if (tx == eagle.tileX && ty == eagle.tileY) continue;
      final type = grid.typeAt(tx, ty);
      if (type == TerrainType.empty ||
          type == TerrainType.ice ||
          type == TerrainType.forest) {
        return Point(tx, ty);
      }
    }
    return null;
  }

  void _advancePowerUps(double dt, TankStep out) {
    for (final p in powerUps) {
      p.timer -= dt;
      p.blink += dt;
    }
    powerUps.removeWhere((p) => p.timer <= 0);

    if (!player.alive) return;
    for (final p in List<PowerUp>.of(powerUps)) {
      if (_playerOverlapsTile(p.tileX, p.tileY)) {
        _applyPowerUp(p, out);
        powerUps.remove(p);
      }
    }
  }

  bool _playerOverlapsTile(int tx, int ty) {
    final x0 = tx * TankGeo.sub;
    final y0 = ty * TankGeo.sub;
    return player.sx < x0 + TankGeo.sub &&
        player.sx + TankGeo.tankSize > x0 &&
        player.sy < y0 + TankGeo.sub &&
        player.sy + TankGeo.tankSize > y0;
  }

  void _applyPowerUp(PowerUp p, TankStep out) {
    out.powerUpsTaken.add(PowerUpEvent(type: p.type, center: p.centerNorm));
    switch (p.type) {
      case PowerUpType.star:
        if (player.tier < kMaxUpgradeTier) {
          player.tier++;
          out.playerUpgraded = true;
        }
      case PowerUpType.grenade:
        for (final t in tanks) {
          if (!t.isPlayer && t.alive) {
            t.hp = 0;
            out.tanksDestroyed.add(TankDestroyed(
              kind: t.kind,
              center: t.centerNorm,
              byPlayer: true,
              score: t.spec.score,
            ));
            score += t.spec.score;
            out.gainedScore += t.spec.score;
          }
        }
      case PowerUpType.helmet:
        player.shieldTimer = kShieldHelmet;
      case PowerUpType.shovel:
        _fortifyBase();
      case PowerUpType.life:
        lives++;
      case PowerUpType.freeze:
        for (final t in tanks) {
          if (!t.isPlayer && t.alive) t.freezeTimer = kFreezeDuration;
        }
    }
  }

  // ── Укрепление базы (лопата) ──────────────────────────────────────────────
  void _fortifyBase() {
    if (_shovelTimer <= 0) {
      _shovelSaved.clear();
      for (final n in _baseRing()) {
        _shovelSaved
            .add([n.x, n.y, grid.typeAt(n.x, n.y).index, grid.quadMaskAt(n.x, n.y)]);
        grid.setTile(n.x, n.y, TerrainType.steel);
      }
    }
    _shovelTimer = kShovelDuration;
  }

  void _advanceShovel(double dt) {
    if (_shovelTimer <= 0) return;
    _shovelTimer -= dt;
    if (_shovelTimer <= 0) {
      for (final s in _shovelSaved) {
        grid.setTile(s[0], s[1], TerrainType.values[s[2]], quad: s[3]);
      }
      _shovelSaved.clear();
    }
  }

  List<Point<int>> _baseRing() {
    final res = <Point<int>>[];
    for (var dyy = -1; dyy <= 1; dyy++) {
      for (var dxx = -1; dxx <= 1; dxx++) {
        if (dxx == 0 && dyy == 0) continue;
        final tx = eagle.tileX + dxx;
        final ty = eagle.tileY + dyy;
        if (grid.inBounds(tx, ty)) res.add(Point(tx, ty));
      }
    }
    return res;
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
