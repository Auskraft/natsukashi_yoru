import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/snake/components/snake_logic.dart';

void main() {
  group('SnakeLogic', () {
    test('старт: длина 3, движется вправо, голова по центру', () {
      final s = SnakeLogic(cols: 10, rows: 10);
      expect(s.length, 3);
      expect(s.direction, Direction.right);
      expect(s.head, const Point(5, 5));
    });

    test('обычный шаг двигает голову и сохраняет длину', () {
      final s = SnakeLogic(cols: 10, rows: 10);
      final before = s.head;
      expect(s.step(), StepOutcome.moved);
      expect(s.head, Point(before.x + 1, before.y));
      expect(s.length, 3);
    });

    test('нельзя развернуться на 180°', () {
      final s = SnakeLogic(cols: 10, rows: 10);
      s.steer(Direction.left); // противоположно right — игнор
      s.step();
      expect(s.direction, Direction.right);
    });

    test('врезание в стену убивает', () {
      final s = SnakeLogic(cols: 8, rows: 8);
      var out = StepOutcome.moved;
      for (var i = 0; i < 8; i++) {
        out = s.step();
        if (out == StepOutcome.died) break;
      }
      expect(out, StepOutcome.died);
      expect(s.dead, isTrue);
    });

    test('поедание еды растит змейку', () {
      // Поле 5x1: змейка занимает x=0..2, движется вправо. Свободные клетки —
      // только x=3 и x=4, обе впереди, поэтому еда будет съедена за <=2 шага
      // при любом зерне rng.
      final s = SnakeLogic(cols: 5, rows: 1, random: Random(1));
      expect(s.length, 3);

      var ate = false;
      for (var i = 0; i < 2; i++) {
        if (s.step() == StepOutcome.ate) {
          ate = true;
          break;
        }
      }
      expect(ate, isTrue, reason: 'змейка должна была съесть еду');
      expect(s.length, 4);
    });
  });
}
