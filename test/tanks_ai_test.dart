import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_ai.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_entities.dart';

AiContext _ctx({
  int baseX = 52,
  int baseY = 96,
  int playerX = 52,
  int playerY = 96,
  bool playerAlive = true,
  bool fire = false,
}) =>
    AiContext(
      baseX: baseX,
      baseY: baseY,
      playerX: playerX,
      playerY: playerY,
      playerAlive: playerAlive,
      shouldFire: (_) => fire,
    );

Tank _enemy({int sx = 48, int sy = 0, Dir dir = Dir.down}) =>
    Tank(id: 1, kind: TankKind.basic, sx: sx, sy: sy, dir: dir, isPlayer: false);

void main() {
  group('decideAi', () {
    test('детерминировано при одинаковом seed', () {
      final c = _ctx();
      final a = decideAi(_enemy(), c, Random(5));
      final b = decideAi(_enemy(), c, Random(5));
      expect(a.turnTo, b.turnTo);
      expect(a.fire, b.fire);
    });

    test('враг сверху чаще едет к базе вниз (доминантная ось)', () {
      final c = _ctx(baseX: 52, baseY: 96, playerAlive: false);
      var down = 0;
      for (var s = 0; s < 200; s++) {
        if (decideAi(_enemy(), c, Random(s)).turnTo == Dir.down) down++;
      }
      expect(down, greaterThan(80),
          reason: 'доминанта — движение к базе вниз');
    });

    test('shouldFire=true → всегда огонь', () {
      final cmd = decideAi(_enemy(sy: 40), _ctx(fire: true), Random(1));
      expect(cmd.fire, isTrue);
    });

    test('всегда выбирает какое-то направление', () {
      for (var s = 0; s < 50; s++) {
        expect(decideAi(_enemy(), _ctx(), Random(s)).turnTo, isNotNull);
      }
    });
  });
}
