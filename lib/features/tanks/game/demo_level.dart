import 'dart:math';

import '../logic/run_config.dart';
import '../logic/spawn_director.dart';
import '../logic/tank_entities.dart';
import '../logic/tank_geometry.dart';
import '../logic/tank_grid.dart';
import '../logic/tanks_logic.dart';

/// Временный демо-уровень для фаз 2–3 (пока нет парсера уровней из фазы 4).
///
/// Враги спавнятся волнами сверху (директор), едут к базе/игроку и стреляют (AI),
/// часть несёт бонусы. Позволяет пощупать на устройстве полный цикл боя и «сок».
TanksLogic buildDemoLevel({Random? random}) {
  final grid = TerrainGrid();

  // База-орёл внизу-центре в кирпичном кольце.
  const ex = 6, ey = 12;
  grid.setTile(ex, ey, TerrainType.base);
  for (final t in const [
    [5, 11],
    [6, 11],
    [7, 11],
    [5, 12],
    [7, 12],
  ]) {
    grid.setTile(t[0], t[1], TerrainType.brick);
  }

  // Кирпичные кластеры.
  for (var x = 2; x <= 4; x++) {
    grid.setTile(x, 8, TerrainType.brick);
  }
  for (var x = 8; x <= 10; x++) {
    grid.setTile(x, 8, TerrainType.brick);
  }
  grid
    ..setTile(2, 4, TerrainType.brick)
    ..setTile(3, 4, TerrainType.brick)
    ..setTile(9, 4, TerrainType.brick)
    ..setTile(10, 4, TerrainType.brick);

  // Сталь по центру, вода и лёд по краям, лес-укрытие.
  grid.setTile(6, 6, TerrainType.steel);
  grid
    ..setTile(0, 9, TerrainType.water)
    ..setTile(1, 9, TerrainType.water)
    ..setTile(11, 9, TerrainType.water)
    ..setTile(12, 9, TerrainType.water)
    ..setTile(3, 10, TerrainType.ice)
    ..setTile(4, 10, TerrainType.ice)
    ..setTile(6, 3, TerrainType.forest)
    ..setTile(6, 4, TerrainType.forest);

  final player = Tank(
    id: 0,
    kind: TankKind.player,
    sx: 2 * TankGeo.sub,
    sy: TankGeo.maxOrigin,
    dir: Dir.up,
    isPlayer: true,
  )..shieldTimer = 4; // фора в начале партии

  final director = SpawnDirector(
    spawnTiles: const [Point(0, 0), Point(6, 0), Point(11, 0)],
    roster: const [
      TankKind.basic,
      TankKind.basic,
      TankKind.fast,
      TankKind.basic,
      TankKind.power,
      TankKind.basic,
      TankKind.fast,
      TankKind.armor,
    ],
    maxConcurrent: 3,
    interval: 2.8,
    firstDelay: 1.8,
  );

  return TanksLogic(
    grid: grid,
    eagle: Eagle(tileX: ex, tileY: ey),
    player: player,
    director: director,
    config: RunConfig.campaign,
    random: random,
  );
}
