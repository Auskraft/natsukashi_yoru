import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_entities.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_grid.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tanks_logic.dart';

Tank _player({int sx = 0, int sy = 0, Dir dir = Dir.right}) =>
    Tank(id: 0, kind: TankKind.player, sx: sx, sy: sy, dir: dir, isPlayer: true);

TanksLogic _build({
  TerrainGrid? grid,
  Tank? player,
  List<Tank> enemies = const [],
  int enemiesRemaining = 0,
  Eagle? eagle,
}) {
  return TanksLogic(
    grid: grid ?? TerrainGrid(),
    eagle: eagle ?? Eagle(tileX: 6, tileY: 12),
    player: player ?? _player(),
    enemies: enemies,
    enemiesRemaining: enemiesRemaining,
    random: Random(7),
  );
}

Bullet _playerBullet({
  required double x,
  required double y,
  required Dir dir,
  double speed = 150,
  int power = 1,
  int id = 1,
}) =>
    Bullet(
      id: id,
      ownerId: 0,
      owner: BulletOwner.player,
      x: x,
      y: y,
      dir: dir,
      speed: speed,
      power: power,
    );

void main() {
  group('стрельба', () {
    test('тир 0: одновременно только одна пуля игрока', () {
      final g = _build(enemiesRemaining: 99);
      final s1 = g.step(0.05, const PlayerIntent(fire: true));
      expect(s1.bulletsSpawned, hasLength(1));
      final s2 = g.step(0.05, const PlayerIntent(fire: true));
      expect(s2.bulletsSpawned, isEmpty, reason: 'кулдаун + лимит пуль');
      expect(g.bullets.where((b) => !b.dead).length, lessThanOrEqualTo(1));
    });
  });

  group('коллизии пуль', () {
    test('быстрая пуля при большом dt всё равно попадает в кирпич '
        '(анти-туннелинг)', () {
      final grid = TerrainGrid()
        ..setTile(8, 0, TerrainType.brick)
        ..setTile(8, 1, TerrainType.brick);
      final g = _build(grid: grid, enemiesRemaining: 99);
      // Без субшага скачок 250 суб/кадр перепрыгнул бы стену на тайле 8.
      g.bullets.add(_playerBullet(x: 10, y: 6, dir: Dir.right, speed: 5000));
      final s = g.step(0.05, PlayerIntent.idle);
      expect(s.bricksHit, isNotEmpty);
      expect(g.bullets, isEmpty, reason: 'пуля погибла на кирпиче');
    });

    test('пуля игрока уничтожает basic с одного попадания и даёт очки', () {
      final enemy = Tank(
          id: 5, kind: TankKind.basic, sx: 40, sy: 0, dir: Dir.down, isPlayer: false);
      final g = _build(
          player: _player(sx: 0, sy: 40), enemies: [enemy], enemiesRemaining: 0);
      g.bullets.add(_playerBullet(x: 30, y: 6, dir: Dir.right, speed: 200));
      var destroyed = false;
      for (var i = 0; i < 10 && !destroyed; i++) {
        if (g.step(0.05, PlayerIntent.idle).tanksDestroyed.isNotEmpty) {
          destroyed = true;
        }
      }
      expect(destroyed, isTrue);
      expect(g.score, kTankSpecs[TankKind.basic]!.score);
    });

    test('armor выдерживает 4 попадания', () {
      final enemy = Tank(
          id: 5, kind: TankKind.armor, sx: 40, sy: 0, dir: Dir.down, isPlayer: false);
      final g = _build(
          player: _player(sx: 0, sy: 40), enemies: [enemy], enemiesRemaining: 99);

      void shoot() {
        g.bullets.add(_playerBullet(x: 30, y: 6, dir: Dir.right, speed: 300, id: 0));
        for (var i = 0; i < 4; i++) {
          g.step(0.05, PlayerIntent.idle);
        }
      }

      shoot();
      shoot();
      shoot();
      expect(enemy.alive, isTrue, reason: '3 попадания недостаточно');
      expect(enemy.hp, 1);

      var destroyed = false;
      g.bullets.add(_playerBullet(x: 30, y: 6, dir: Dir.right, speed: 300, id: 0));
      for (var i = 0; i < 4 && !destroyed; i++) {
        if (g.step(0.05, PlayerIntent.idle).tanksDestroyed.isNotEmpty) {
          destroyed = true;
        }
      }
      expect(destroyed, isTrue);
    });

    test('встречные пули взаимно уничтожаются', () {
      final g = _build(enemiesRemaining: 99);
      g.bullets.add(_playerBullet(x: 50, y: 50, dir: Dir.right, speed: 100));
      g.bullets.add(Bullet(
          id: 2,
          ownerId: 9,
          owner: BulletOwner.enemy,
          x: 55,
          y: 50,
          dir: Dir.left,
          speed: 100,
          power: 1));
      final s = g.step(0.05, PlayerIntent.idle);
      expect(s.bulletClashes, isNotEmpty);
      expect(g.bullets, isEmpty);
    });

    test('сталь держит обычную пулю (рикошет), но ломается силой 2', () {
      final grid = TerrainGrid()
        ..setTile(8, 0, TerrainType.steel)
        ..setTile(8, 1, TerrainType.steel);
      final g = _build(grid: grid, enemiesRemaining: 99);
      // Скорость подобрана так, чтобы пуля долетела до тайла 8 за один кадр.
      g.bullets.add(_playerBullet(x: 10, y: 6, dir: Dir.right, speed: 2000, power: 1));
      final s1 = g.step(0.05, PlayerIntent.idle);
      expect(s1.steelHits, isNotEmpty);
      expect(grid.typeAt(8, 0), TerrainType.steel, reason: 'сталь цела');

      g.bullets.add(_playerBullet(x: 10, y: 6, dir: Dir.right, speed: 2000, power: 2));
      g.step(0.05, PlayerIntent.idle);
      expect(grid.typeAt(8, 0), TerrainType.empty, reason: 'сила 2 ломает сталь');
    });

    test('пуля, попавшая в базу, — поражение (даже своя)', () {
      final eagle = Eagle(tileX: 6, tileY: 6);
      final g = _build(eagle: eagle, enemiesRemaining: 99);
      g.bullets.add(_playerBullet(x: 48, y: 52, dir: Dir.right, speed: 200));
      var lost = false;
      for (var i = 0; i < 6 && !lost; i++) {
        if (g.step(0.05, PlayerIntent.idle).baseHit) lost = true;
      }
      expect(lost, isTrue);
      expect(g.over, isTrue);
      expect(g.won, isFalse);
    });
  });
}
