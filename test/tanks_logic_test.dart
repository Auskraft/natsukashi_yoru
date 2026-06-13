import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/tanks/logic/run_config.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_entities.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_geometry.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_grid.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tanks_logic.dart';

Tank _player({int sx = 0, int sy = 0, Dir dir = Dir.right}) => Tank(
      id: 0,
      kind: TankKind.player,
      sx: sx,
      sy: sy,
      dir: dir,
      isPlayer: true,
    );

TanksLogic _build({
  TerrainGrid? grid,
  Tank? player,
  List<Tank> enemies = const [],
  int enemiesRemaining = 0,
  Eagle? eagle,
  int seed = 1,
}) {
  return TanksLogic(
    grid: grid ?? TerrainGrid(),
    eagle: eagle ?? Eagle(tileX: 6, tileY: 12),
    player: player ?? _player(),
    enemies: enemies,
    enemiesRemaining: enemiesRemaining,
    random: Random(seed),
  );
}

void _run(TanksLogic g, Dir dir, int frames) {
  for (var i = 0; i < frames; i++) {
    g.step(0.05, PlayerIntent(move: dir));
  }
}

void main() {
  group('старт', () {
    test('начальное состояние: жизни, счёт, не окончено, игрок первый', () {
      final g = _build(enemiesRemaining: 5);
      expect(g.lives, RunConfig.campaign.startLives);
      expect(g.score, 0);
      expect(g.over, isFalse);
      expect(g.tanks.first.isPlayer, isTrue);
    });
  });

  group('движение игрока', () {
    test('едет вправо по вводу и стоит без ввода', () {
      final g = _build(enemiesRemaining: 1);
      final p = g.player;
      g.step(0.05, const PlayerIntent(move: Dir.right));
      final x1 = p.sx;
      expect(x1, greaterThan(0));
      g.step(0.05, PlayerIntent.idle);
      expect(p.sx, x1, reason: 'без ввода танк стоит');
    });

    test('за один кадр проезжает floor(speed*dt) суб-клеток', () {
      final g = _build(enemiesRemaining: 1);
      final p = g.player;
      g.step(0.05, const PlayerIntent(move: Dir.right));
      expect(p.sx, (p.spec.speed * 0.05).floor());
    });

    test('упирается в границу поля', () {
      final g = _build(player: _player(sx: TankGeo.maxOrigin), enemiesRemaining: 1);
      _run(g, Dir.right, 60);
      expect(g.player.sx, TankGeo.maxOrigin);
    });

    test('стальная стена не пускает дальше', () {
      final grid = TerrainGrid()
        ..setTile(4, 0, TerrainType.steel)
        ..setTile(4, 1, TerrainType.steel);
      final g = _build(grid: grid, enemiesRemaining: 1);
      _run(g, Dir.right, 80);
      // Правый край танка упрётся в тайл 4 (суб 32): последний корректный sx = 16.
      expect(g.player.sx, 16);
    });

    test('поворот выравнивает перпендикулярную ось по полу-тайлу', () {
      final g = _build(player: _player(sx: 20, sy: 5, dir: Dir.down), enemiesRemaining: 1);
      g.step(0.001, const PlayerIntent(move: Dir.right));
      expect(g.player.sy % TankGeo.half, 0);
      expect(g.player.sy, 4);
    });
  });

  group('победа/поражение', () {
    test('нет живых врагов и некого спавнить → победа', () {
      final g = _build(enemiesRemaining: 0);
      final s = g.step(0.016, PlayerIntent.idle);
      expect(s.win, isTrue);
      expect(s.waveCleared, isTrue);
      expect(g.over, isTrue);
      expect(g.won, isTrue);
    });

    test('пока есть неспавненные враги — победы нет', () {
      final g = _build(enemiesRemaining: 3);
      final s = g.step(0.016, PlayerIntent.idle);
      expect(s.win, isFalse);
      expect(g.over, isFalse);
    });

    test('шаг после конца игры — пустой (no-op)', () {
      final g = _build(enemiesRemaining: 0);
      g.step(0.016, PlayerIntent.idle);
      final s = g.step(0.05, const PlayerIntent(move: Dir.right, fire: true));
      expect(s.isQuiet, isTrue);
    });
  });
}
