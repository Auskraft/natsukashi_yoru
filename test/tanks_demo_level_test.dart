import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/tanks/game/demo_level.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_geometry.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tanks_logic.dart';

void main() {
  group('демо-уровень (фазы 2–3)', () {
    test('структура: ростер врагов, база цела, в начале на поле никого', () {
      final g = buildDemoLevel(random: Random(1));
      expect(g.enemiesAlive, 0);
      expect(g.enemiesRemaining, 8);
      expect(g.eagle.destroyed, isFalse);
      expect(g.over, isFalse);
    });

    test('игрок стартует не внутри стены', () {
      final g = buildDemoLevel(random: Random(1));
      final p = g.player;
      const last = TankGeo.tankSize - 1;
      expect(g.grid.solidForTank(p.sx, p.sy), isFalse);
      expect(g.grid.solidForTank(p.sx + last, p.sy), isFalse);
      expect(g.grid.solidForTank(p.sx, p.sy + last), isFalse);
      expect(g.grid.solidForTank(p.sx + last, p.sy + last), isFalse);
    });

    test('через ~2.5 c появляются враги (спавн-директор работает)', () {
      final g = buildDemoLevel(random: Random(1));
      for (var i = 0; i < 50; i++) {
        g.step(0.05, PlayerIntent.idle);
      }
      expect(g.over, isFalse, reason: 'база переживает первые секунды');
      expect(g.enemiesAlive, greaterThan(0));
    });

    test('структура раскладки не зависит от seed', () {
      final a = buildDemoLevel(random: Random(1));
      final b = buildDemoLevel(random: Random(99));
      expect(a.enemiesRemaining, b.enemiesRemaining);
      expect(a.eagle.tileX, b.eagle.tileX);
      expect(a.player.sx, b.player.sx);
    });
  });
}
