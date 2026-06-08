import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/puyo_puyo/components/puyo_puyo_logic.dart';

/// Полностью очистить доску (нижний слой тестов оперирует board напрямую).
void _clear(PuyoPuyoLogic g) {
  for (var y = 0; y < PuyoPuyoLogic.rows; y++) {
    for (var x = 0; x < PuyoPuyoLogic.cols; x++) {
      g.board[y][x] = null;
    }
  }
}

void main() {
  group('PuyoRotation', () {
    test('cw идёт по кругу up -> right -> down -> left -> up', () {
      expect(PuyoRotation.up.cw, PuyoRotation.right);
      expect(PuyoRotation.right.cw, PuyoRotation.down);
      expect(PuyoRotation.down.cw, PuyoRotation.left);
      expect(PuyoRotation.left.cw, PuyoRotation.up);
    });

    test('спутник смещён от оси на delta', () {
      const pair = PuyoPair(
        axisX: 3,
        axisY: 5,
        axisColor: 0,
        satelliteColor: 1,
        rotation: PuyoRotation.up,
      );
      expect(pair.satellite, const Point(3, 4));
    });
  });

  group('PuyoPuyoLogic — старт', () {
    test('после reset: есть текущая пара, не мертва, поле пусто', () {
      final g = PuyoPuyoLogic(random: Random(1));
      expect(g.dead, isFalse);
      expect(g.current, isNotNull);
      expect(g.next.length, 2);
      var filled = 0;
      for (final row in g.board) {
        filled += row.where((c) => c != null).length;
      }
      expect(filled, 0);
      // Цвета в допустимом диапазоне.
      expect(g.current!.axisColor, inInclusiveRange(0, puyoColorCount - 1));
      expect(g.current!.satelliteColor, inInclusiveRange(0, puyoColorCount - 1));
    });
  });

  group('Движение и поворот', () {
    test('сдвиги влево/вправо меняют позицию оси', () {
      final g = PuyoPuyoLogic(random: Random(1));
      final x0 = g.current!.axisX;
      expect(g.moveLeft(), isTrue);
      expect(g.current!.axisX, x0 - 1);
      expect(g.moveRight(), isTrue);
      expect(g.current!.axisX, x0);
    });

    test('у левой стенки сдвиг влево запрещён', () {
      final g = PuyoPuyoLogic(random: Random(1));
      // Догоняем ось до левого края.
      while (g.moveLeft()) {}
      expect(g.current!.axisX, 0);
      expect(g.moveLeft(), isFalse);
      expect(g.current!.axisX, 0);
    });

    test('у правой стенки сдвиг вправо запрещён', () {
      final g = PuyoPuyoLogic(random: Random(1));
      while (g.moveRight()) {}
      // Ось не должна выйти за правую границу с учётом спутника.
      expect(g.current!.axisX, lessThanOrEqualTo(PuyoPuyoLogic.cols - 1));
      expect(g.moveRight(), isFalse);
    });

    test('поворот на пустом поле удаётся и меняет ориентацию', () {
      final g = PuyoPuyoLogic(random: Random(1));
      final r0 = g.current!.rotation;
      expect(g.rotateCW(), isTrue);
      expect(g.current!.rotation, r0.cw);
    });

    test('поворот у стенки отбивает пару внутрь поля (kick)', () {
      final g = PuyoPuyoLogic(random: Random(1));
      while (g.moveLeft()) {}
      expect(g.current!.axisX, 0);
      // Прокручиваем все 4 ориентации — kick не должен дать пару за стену.
      for (var i = 0; i < 4; i++) {
        expect(g.rotateCW(), isTrue);
        final sx = g.current!.satellite.x;
        expect(sx, inInclusiveRange(0, PuyoPuyoLogic.cols - 1));
        expect(g.current!.axisX, inInclusiveRange(0, PuyoPuyoLogic.cols - 1));
      }
    });
  });

  group('Фиксация и падение по столбцам', () {
    test('hard drop кладёт оба пуйо на дно', () {
      final g = PuyoPuyoLogic(random: Random(2));
      _clear(g);
      final res = g.hardDrop();
      expect(res, isNotNull);
      // Без совпадений цепочки нет.
      expect(res!.waves, isEmpty);
      // На дне доски должны оказаться два пуйо.
      var filled = 0;
      for (final row in g.board) {
        filled += row.where((c) => c != null).length;
      }
      expect(filled, 2);
      // Нижняя строка стартового столбца заполнена.
      expect(g.board[PuyoPuyoLogic.rows - 1][PuyoPuyoLogic.spawnColumn],
          isNotNull);
    });

    test('пара в горизонтальной ориентации садится в два столбца', () {
      final g = PuyoPuyoLogic(random: Random(4));
      _clear(g);
      // Поворачиваем в горизонталь (right): ось и спутник в соседних столбцах.
      g.rotateCW();
      final ax = g.current!.axisX;
      final sx = g.current!.satellite.x;
      expect(sx, isNot(ax));
      g.hardDrop();
      final bottom = PuyoPuyoLogic.rows - 1;
      expect(g.board[bottom][ax], isNotNull);
      expect(g.board[bottom][sx], isNotNull);
    });
  });

  group('Лопанье групп и цепочки', () {
    test('группа из 4 одноцветных лопается и даёт очки', () {
      final g = PuyoPuyoLogic(random: Random(7));
      _clear(g);
      const bottom = PuyoPuyoLogic.rows - 1;
      // Кладём 3 пуйо цвета 0 в нижней строке столбцов 0..2,
      // и ещё один над столбцом 0 — итого Г-образная группа из 4.
      g.board[bottom][0] = 0;
      g.board[bottom][1] = 0;
      g.board[bottom][2] = 0;
      g.board[bottom - 1][0] = 0;

      final popsBefore = g.popped;
      final scoreBefore = g.score;
      // Любой ход-фиксация запустит проверку цепочки. Уроним текущую пару
      // в дальний столбец, чтобы она не мешала группе.
      while (g.moveRight()) {}
      final res = g.hardDrop()!;

      expect(res.waves.length, greaterThanOrEqualTo(1));
      final firstWave = res.waves.first;
      expect(firstWave.count, 4);
      expect(firstWave.chain, 1);
      // Все лопнувшие — цвета 0.
      expect(firstWave.popped.every((c) => c.color == 0), isTrue);
      expect(g.popped, popsBefore + 4);
      expect(g.score, greaterThan(scoreBefore));
      // Клетки группы очищены.
      expect(g.board[bottom][1], isNull);
    });

    test('группа из 3 НЕ лопается', () {
      final g = PuyoPuyoLogic(random: Random(7));
      _clear(g);
      const bottom = PuyoPuyoLogic.rows - 1;
      g.board[bottom][0] = 0;
      g.board[bottom][1] = 0;
      g.board[bottom][2] = 0;

      // Уроним пару подальше (в столбцы справа), цвета подобраны так, что
      // не пристроятся к группе из 3.
      while (g.moveRight()) {}
      final res = g.hardDrop()!;
      // Группа из 3 цвета 0 на дне осталась нетронутой.
      expect(g.board[bottom][0], 0);
      expect(g.board[bottom][1], 0);
      expect(g.board[bottom][2], 0);
      // Если пара сама не сложилась в четвёрку — волн нет.
      // (для seed=7 цвета пары не дают совпадений у дальней стенки)
      expect(res.waves, isEmpty);
    });

    test('каскад даёт цепочку из >1 волны', () {
      final g = PuyoPuyoLogic(random: Random(11));
      _clear(g);
      const b = PuyoPuyoLogic.rows - 1; // нижняя строка
      const int a = 0; // цвет A
      const int c = 1; // цвет B

      // Конструируем поле так, чтобы:
      //  1) сначала лопнула вертикальная четвёрка A в столбце 0;
      //  2) после её исчезновения четыре B (три на дне 1..3 + один,
      //     висевший над столбцом 0) обвалились и сложились в четвёрку.
      //
      // Раскладка столбца 0 снизу вверх: A, A, A, A, B
      g.board[b][0] = a;
      g.board[b - 1][0] = a;
      g.board[b - 2][0] = a;
      g.board[b - 3][0] = a;
      g.board[b - 4][0] = c; // B сверху — упадёт на дно столбца 0 после пика

      // Дно столбцов 1..3 — три B.
      g.board[b][1] = c;
      g.board[b][2] = c;
      g.board[b][3] = c;

      // Текущую пару убираем в дальний столбец 5, чтобы не вмешивалась.
      // Цель — чтобы фиксация просто запустила разбор уже готового поля.
      while (g.moveRight()) {}
      final res = g.hardDrop()!;

      expect(res.waves.length, greaterThanOrEqualTo(2),
          reason: 'ожидаем цепочку минимум из двух волн');

      // Первая волна — четвёрка A.
      final w1 = res.waves[0];
      expect(w1.chain, 1);
      expect(w1.popped.every((p) => p.color == a), isTrue);
      expect(w1.count, 4);

      // Вторая волна — четвёрка B, и её множитель больше первого.
      final w2 = res.waves[1];
      expect(w2.chain, 2);
      expect(w2.popped.every((p) => p.color == c), isTrue);
      expect(w2.count, 4);
      expect(w2.multiplier, greaterThan(w1.multiplier));

      // Суммарные очки = сумма по волнам, цепочка зафиксирована в maxChain.
      var sum = 0;
      for (final w in res.waves) {
        sum += w.gained;
      }
      expect(res.gained, sum);
      expect(g.maxChain, greaterThanOrEqualTo(2));
    });

    test('растущий множитель: второе звено дороже первого', () {
      final g = PuyoPuyoLogic(random: Random(11));
      _clear(g);
      const b = PuyoPuyoLogic.rows - 1;
      g.board[b][0] = 0;
      g.board[b - 1][0] = 0;
      g.board[b - 2][0] = 0;
      g.board[b - 3][0] = 0;
      g.board[b - 4][0] = 1;
      g.board[b][1] = 1;
      g.board[b][2] = 1;
      g.board[b][3] = 1;

      while (g.moveRight()) {}
      final res = g.hardDrop()!;
      expect(res.waves.length, 2);
      expect(res.waves[0].multiplier, 1);
      expect(res.waves[1].multiplier, greaterThan(1));
    });
  });

  group('Game over', () {
    test('переполнение стартовой колонки завершает игру', () {
      final g = PuyoPuyoLogic(random: Random(3));
      // Забиваем стартовый столбец доверху — спавн новой пары невозможен.
      for (var y = 0; y < PuyoPuyoLogic.rows; y++) {
        g.board[y][PuyoPuyoLogic.spawnColumn] = y % 2; // полон, но не лопается
      }
      // Текущую пару уроним вбок, чтобы фиксация прошла и вызвала спавн.
      while (g.moveRight()) {}
      final res = g.hardDrop()!;
      expect(res.gameOver, isTrue);
      expect(g.dead, isTrue);
      expect(g.current, isNull);
    });

    test('после game over ходы игнорируются', () {
      final g = PuyoPuyoLogic(random: Random(3));
      for (var y = 0; y < PuyoPuyoLogic.rows; y++) {
        g.board[y][PuyoPuyoLogic.spawnColumn] = y % 2; // полон, но не лопается
      }
      while (g.moveRight()) {}
      g.hardDrop();
      expect(g.dead, isTrue);
      expect(g.moveLeft(), isFalse);
      expect(g.moveRight(), isFalse);
      expect(g.rotateCW(), isFalse);
      expect(g.softDrop(), isNull);
      expect(g.gravityTick(), isNull);
      expect(g.hardDrop(), isNull);
    });
  });

  group('Гравитация по столбцам', () {
    test('softDrop опускает пару на клетку и не фиксирует в воздухе', () {
      final g = PuyoPuyoLogic(random: Random(9));
      _clear(g);
      final y0 = g.current!.axisY;
      final res = g.softDrop();
      expect(res, isNull);
      expect(g.current!.axisY, y0 + 1);
    });

    test('gravityTick в итоге фиксирует пару на дне', () {
      final g = PuyoPuyoLogic(random: Random(9));
      _clear(g);
      PuyoLockResult? res;
      for (var i = 0; i < PuyoPuyoLogic.rows + 2; i++) {
        res = g.gravityTick();
        if (res != null) break;
      }
      expect(res, isNotNull);
      var filled = 0;
      for (final row in g.board) {
        filled += row.where((c) => c != null).length;
      }
      expect(filled, 2);
    });
  });
}
