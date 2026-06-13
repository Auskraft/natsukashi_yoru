import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/tanks/logic/spawn_director.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_entities.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_geometry.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_grid.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tanks_logic.dart';

void main() {
  group('SpawnDirector', () {
    test('выдаёт ровно весь ростер при свободном месте', () {
      final d = SpawnDirector(
        spawnTiles: const [Point(0, 0)],
        roster: List.filled(6, TankKind.basic),
        maxConcurrent: 4,
        interval: 1.0,
        firstDelay: 0.5,
      );
      expect(d.total, 6);
      var spawned = 0;
      for (var i = 0; i < 5000 && !d.done; i++) {
        if (d.ready(0.05, 0)) {
          d.next();
          spawned++;
        }
      }
      expect(spawned, 6);
      expect(d.done, isTrue);
      expect(d.remaining, 0);
    });

    test('не выдаёт при заполненном лимите', () {
      final d = SpawnDirector(
        spawnTiles: const [Point(0, 0)],
        roster: List.filled(6, TankKind.basic),
        maxConcurrent: 2,
      );
      for (var i = 0; i < 200; i++) {
        expect(d.ready(0.05, 2), isFalse);
      }
      expect(d.done, isFalse);
      expect(d.remaining, 6);
    });
  });

  group('TanksLogic + директор', () {
    test('враги появляются со временем; remaining/alive согласованы', () {
      final player = Tank(
          id: 0,
          kind: TankKind.player,
          sx: 2 * TankGeo.sub,
          sy: TankGeo.maxOrigin,
          dir: Dir.up,
          isPlayer: true);
      final d = SpawnDirector(
        spawnTiles: const [Point(0, 0), Point(6, 0)],
        roster: List.filled(4, TankKind.basic),
        maxConcurrent: 4,
        interval: 0.5,
        firstDelay: 0.3,
      );
      final g = TanksLogic(
        grid: TerrainGrid(),
        eagle: Eagle(tileX: 6, tileY: 12),
        player: player,
        director: d,
        random: Random(3),
      );
      expect(g.enemiesAlive, 0);
      expect(g.enemiesRemaining, 4);

      for (var i = 0; i < 20; i++) {
        g.step(0.05, PlayerIntent.idle);
      }
      expect(g.over, isFalse);
      expect(g.enemiesAlive, greaterThan(0));
      expect(g.enemiesAlive + g.enemiesRemaining, lessThanOrEqualTo(4));
    });

    test('никогда не превышает лимит одновременно живых', () {
      final player = Tank(
          id: 0,
          kind: TankKind.player,
          sx: 0,
          sy: TankGeo.maxOrigin,
          dir: Dir.up,
          isPlayer: true);
      // Кольцо стали вокруг базы, чтобы партия не закончилась слишком быстро.
      final grid = TerrainGrid();
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          grid.setTile(6 + dx, 12 + dy, TerrainType.steel);
        }
      }
      grid.setTile(6, 12, TerrainType.base);
      final d = SpawnDirector(
        spawnTiles: const [Point(0, 0), Point(6, 0), Point(11, 0)],
        roster: List.filled(20, TankKind.basic),
        maxConcurrent: 3,
        interval: 0.2,
        firstDelay: 0.1,
      );
      final g = TanksLogic(
        grid: grid,
        eagle: Eagle(tileX: 6, tileY: 12),
        player: player,
        director: d,
        random: Random(11),
      );
      var maxSeen = 0;
      for (var i = 0; i < 80 && !g.over; i++) {
        g.step(0.05, PlayerIntent.idle);
        maxSeen = maxSeen > g.enemiesAlive ? maxSeen : g.enemiesAlive;
      }
      expect(maxSeen, lessThanOrEqualTo(3));
    });
  });
}
