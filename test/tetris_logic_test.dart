import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/tetris/components/tetris_logic.dart';

void main() {
  group('tetrominoCells', () {
    test('у каждой фигуры ровно 4 клетки во всех поворотах', () {
      for (final t in Tetromino.values) {
        for (var r = 0; r < 4; r++) {
          expect(tetrominoCells(t, r).length, 4, reason: '$t rot $r');
        }
      }
    });

    test('O-фигура не меняется при повороте', () {
      final a = tetrominoCells(Tetromino.o, 0).toSet();
      final b = tetrominoCells(Tetromino.o, 1).toSet();
      expect(b, a);
    });
  });

  group('TetrisLogic', () {
    test('старт: есть текущая и следующая, не мертва', () {
      final g = TetrisLogic(random: Random(1));
      expect(g.dead, isFalse);
      expect(g.current.cells().length, 4);
      expect(Tetromino.values.contains(g.next), isTrue);
    });

    test('сдвиги влево/вправо меняют позицию', () {
      final g = TetrisLogic(random: Random(1));
      final x0 = g.current.x;
      expect(g.moveLeft(), isTrue);
      expect(g.current.x, x0 - 1);
      expect(g.moveRight(), isTrue);
      expect(g.current.x, x0);
    });

    test('поворот на пустом поле удаётся', () {
      final g = TetrisLogic(random: Random(1));
      expect(g.rotateCW(), isTrue);
      expect(g.current.rot, 1);
    });

    test('hard drop кладёт фигуру на дно', () {
      final g = TetrisLogic(random: Random(2));
      g.hardDrop();
      // Нижняя строка должна получить часть закреплённых клеток.
      final bottomFilled = g.board[TetrisLogic.rows - 1].any((c) => c != null);
      expect(bottomFilled, isTrue);
    });

    test('полная строка сжигается и даёт очки', () {
      final g = TetrisLogic(random: Random(7));
      // Заполняем нижнюю строку целиком — она сожжётся при ближайшей фиксации.
      for (var x = 0; x < TetrisLogic.cols; x++) {
        g.board[TetrisLogic.rows - 1][x] = Tetromino.i;
      }
      final linesBefore = g.lines;
      final scoreBefore = g.score;
      final res = g.hardDrop();
      expect(res.cleared, greaterThanOrEqualTo(1));
      expect(g.lines, greaterThan(linesBefore));
      expect(g.score, greaterThan(scoreBefore));
    });

    test('переполнение сверху завершает игру', () {
      final g = TetrisLogic(random: Random(3));
      // Занимаем центральные столбцы вверху (но не всю строку — иначе сожжётся),
      // чтобы спавн новой фигуры столкнулся.
      for (final y in [0, 1]) {
        for (final x in [3, 4, 5, 6]) {
          g.board[y][x] = Tetromino.o;
        }
      }
      final res = g.hardDrop();
      expect(res.gameOver, isTrue);
      expect(g.dead, isTrue);
    });

    test('7-bag выдаёт все типы фигур', () {
      final g = TetrisLogic(random: Random(5));
      final seen = <Tetromino>{};
      for (var i = 0; i < 20 && !g.dead; i++) {
        seen.add(g.current.type);
        g.hardDrop();
        // Очищаем поле, чтобы стопка не доросла до верха и игра не кончилась.
        for (var y = 0; y < TetrisLogic.rows; y++) {
          for (var x = 0; x < TetrisLogic.cols; x++) {
            g.board[y][x] = null;
          }
        }
      }
      expect(seen.length, Tetromino.values.length);
    });
  });
}
