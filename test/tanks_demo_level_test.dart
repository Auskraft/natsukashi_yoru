import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/tanks/game/demo_level.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_geometry.dart';

void main() {
  group('демо-уровень (фаза 2)', () {
    test('структура: 3 врага на поле, база цела', () {
      final g = buildDemoLevel(random: Random(1));
      expect(g.enemiesAlive, 3);
      expect(g.eagle.destroyed, isFalse);
      expect(g.over, isFalse);
    });

    test('игрок стартует не внутри стены', () {
      final g = buildDemoLevel(random: Random(1));
      final p = g.player;
      // Проверяем все 4 угла AABB игрока — ни один не в солидном терреине.
      const last = TankGeo.tankSize - 1;
      expect(g.grid.solidForTank(p.sx, p.sy), isFalse);
      expect(g.grid.solidForTank(p.sx + last, p.sy), isFalse);
      expect(g.grid.solidForTank(p.sx, p.sy + last), isFalse);
      expect(g.grid.solidForTank(p.sx + last, p.sy + last), isFalse);
    });

    test('структура не зависит от seed (детерминированная раскладка)', () {
      final a = buildDemoLevel(random: Random(1));
      final b = buildDemoLevel(random: Random(99));
      expect(a.enemiesAlive, b.enemiesAlive);
      expect(a.eagle.tileX, b.eagle.tileX);
      expect(a.player.sx, b.player.sx);
    });
  });
}
