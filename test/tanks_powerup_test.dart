import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_entities.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_geometry.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_grid.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tanks_logic.dart';

TanksLogic _logic(
  int tileX,
  int tileY, {
  Eagle? eagle,
  List<Tank> enemies = const [],
  TerrainGrid? grid,
}) {
  final p = Tank(
    id: 0,
    kind: TankKind.player,
    sx: tileX * TankGeo.sub,
    sy: tileY * TankGeo.sub,
    dir: Dir.up,
    isPlayer: true,
  );
  return TanksLogic(
    grid: grid ?? TerrainGrid(),
    eagle: eagle ?? Eagle(tileX: 0, tileY: 0),
    player: p,
    enemies: enemies,
    enemiesRemaining: 99, // не даём партии закончиться победой
    random: Random(1),
  );
}

Tank _enemy(int id, TankKind kind, int sx) =>
    Tank(id: id, kind: kind, sx: sx, sy: 0, dir: Dir.down, isPlayer: false);

void main() {
  group('бонусы', () {
    test('звезда поднимает тир игрока', () {
      final g = _logic(3, 3);
      g.powerUps.add(PowerUp(type: PowerUpType.star, tileX: 3, tileY: 3));
      final s = g.step(0.016, PlayerIntent.idle);
      expect(g.player.tier, 1);
      expect(s.playerUpgraded, isTrue);
      expect(s.powerUpsTaken, isNotEmpty);
    });

    test('звезда не превышает максимальный тир', () {
      final g = _logic(3, 3)..player.tier = kMaxUpgradeTier;
      g.powerUps.add(PowerUp(type: PowerUpType.star, tileX: 3, tileY: 3));
      g.step(0.016, PlayerIntent.idle);
      expect(g.player.tier, kMaxUpgradeTier);
    });

    test('жизнь добавляет жизнь', () {
      final g = _logic(3, 3);
      final before = g.lives;
      g.powerUps.add(PowerUp(type: PowerUpType.life, tileX: 3, tileY: 3));
      g.step(0.016, PlayerIntent.idle);
      expect(g.lives, before + 1);
    });

    test('шлем даёт щит', () {
      final g = _logic(3, 3);
      expect(g.player.shielded, isFalse);
      g.powerUps.add(PowerUp(type: PowerUpType.helmet, tileX: 3, tileY: 3));
      g.step(0.016, PlayerIntent.idle);
      expect(g.player.shielded, isTrue);
    });

    test('таймер замораживает всех врагов', () {
      final g = _logic(3, 3, enemies: [_enemy(1, TankKind.basic, 80)]);
      g.powerUps.add(PowerUp(type: PowerUpType.freeze, tileX: 3, tileY: 3));
      g.step(0.016, PlayerIntent.idle);
      expect(g.tanks.firstWhere((t) => !t.isPlayer).frozen, isTrue);
    });

    test('граната сносит всех живых врагов и даёт очки', () {
      final g = _logic(3, 3, enemies: [
        _enemy(1, TankKind.basic, 60),
        _enemy(2, TankKind.fast, 80),
      ]);
      g.powerUps.add(PowerUp(type: PowerUpType.grenade, tileX: 3, tileY: 3));
      final s = g.step(0.016, PlayerIntent.idle);
      expect(s.tanksDestroyed.length, 2);
      expect(g.enemiesAlive, 0);
      expect(g.score,
          kTankSpecs[TankKind.basic]!.score + kTankSpecs[TankKind.fast]!.score);
    });

    test('лопата укрепляет кольцо базы сталью', () {
      final g = _logic(1, 1, eagle: Eagle(tileX: 6, tileY: 6));
      g.powerUps.add(PowerUp(type: PowerUpType.shovel, tileX: 1, tileY: 1));
      g.step(0.016, PlayerIntent.idle);
      expect(g.grid.typeAt(5, 5), TerrainType.steel);
      expect(g.grid.typeAt(6, 5), TerrainType.steel);
      expect(g.grid.typeAt(7, 7), TerrainType.steel);
    });
  });
}
