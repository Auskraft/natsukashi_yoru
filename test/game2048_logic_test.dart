import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/game2048/components/game2048_logic.dart';

/// Прямо задать поле логики из строк (по 4 значения, сверху вниз).
/// 0 — пусто. Позволяет строить детерминированные сценарии без зависимости
/// от случайного спавна стартовых плиток.
void setGrid(Game2048Logic g, List<List<int>> rows) {
  assert(rows.length == g.size);
  for (var y = 0; y < g.size; y++) {
    assert(rows[y].length == g.size);
    for (var x = 0; x < g.size; x++) {
      g.grid[y * g.size + x] = rows[y][x];
    }
  }
}

/// Поле в виде строк (для удобных сравнений в expect).
List<List<int>> gridRows(Game2048Logic g) => [
      for (var y = 0; y < g.size; y++)
        [for (var x = 0; x < g.size; x++) g.tileAt(x, y)],
    ];

/// Сколько непустых плиток на поле.
int tileCount(Game2048Logic g) => g.grid.where((v) => v != 0).length;

void main() {
  group('старт', () {
    test('после reset ровно две плитки, счёт 0, не выиграно', () {
      for (var seed = 0; seed < 25; seed++) {
        final g = Game2048Logic(random: Random(seed));
        expect(tileCount(g), 2, reason: 'seed=$seed: должно быть 2 плитки');
        expect(g.score, 0);
        expect(g.won, isFalse);
        // Стартовые плитки — только 2 или 4.
        for (final v in g.grid.where((v) => v != 0)) {
          expect(v == 2 || v == 4, isTrue, reason: 'seed=$seed: плитка $v');
        }
      }
    });

    test('сетка по умолчанию 4×4', () {
      final g = Game2048Logic(random: Random(1));
      expect(g.size, 4);
      expect(g.grid.length, 16);
    });
  });

  group('слияние пары по направлению', () {
    test('влево: [2,2,0,0] -> [4,0,0,0], очки +4', () {
      final g = Game2048Logic(random: Random(1));
      setGrid(g, [
        [2, 2, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      final before = g.score;
      final res = g.move(SlideDirection.left);

      expect(res.moved, isTrue);
      expect(res.gained, 4);
      expect(g.score, before + 4);
      // Получившаяся четвёрка — в левом верхнем углу.
      expect(g.tileAt(0, 0), 4);
      // Исход содержит слияние с позицией и значением (для частиц).
      expect(res.merges.length, 1);
      expect(res.merges.first.value, 4);
      expect(res.merges.first.x, 0);
      expect(res.merges.first.y, 0);
    });

    test('вправо: пара уезжает к правому краю и сливается', () {
      final g = Game2048Logic(random: Random(2));
      setGrid(g, [
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [2, 0, 2, 0],
      ]);
      final res = g.move(SlideDirection.right);
      expect(res.moved, isTrue);
      expect(res.gained, 4);
      // Четвёрка прижата к правому краю нижней строки.
      expect(g.tileAt(3, 3), 4);
      expect(res.merges.single.x, 3);
      expect(res.merges.single.y, 3);
    });

    test('вверх: вертикальная пара сливается у верхнего края', () {
      final g = Game2048Logic(random: Random(3));
      setGrid(g, [
        [0, 4, 0, 0],
        [0, 0, 0, 0],
        [0, 4, 0, 0],
        [0, 0, 0, 0],
      ]);
      final res = g.move(SlideDirection.up);
      expect(res.moved, isTrue);
      expect(res.gained, 8);
      expect(g.tileAt(1, 0), 8);
    });

    test('вниз: вертикальная пара сливается у нижнего края', () {
      final g = Game2048Logic(random: Random(4));
      setGrid(g, [
        [0, 0, 8, 0],
        [0, 0, 8, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      final res = g.move(SlideDirection.down);
      expect(res.moved, isTrue);
      expect(res.gained, 16);
      expect(g.tileAt(2, 3), 16);
    });
  });

  group('не более одного слияния за ход', () {
    test('[2,2,2,2] влево -> [4,4,0,0], очки +8 (не 8 одной плиткой)', () {
      final g = Game2048Logic(random: Random(5));
      setGrid(g, [
        [2, 2, 2, 2],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      final res = g.move(SlideDirection.left);

      expect(res.moved, isTrue);
      // Две независимые четвёрки, а не одна восьмёрка.
      expect(g.tileAt(0, 0), 4);
      expect(g.tileAt(1, 0), 4);
      expect(res.merges.length, 2);
      expect(res.merges.every((m) => m.value == 4), isTrue);
      // Очки за ход = сумма получившихся плиток = 4 + 4.
      expect(res.gained, 8);
    });

    test('[4,4,4,0] влево -> [8,4,0,0]: сливается только крайняя пара', () {
      final g = Game2048Logic(random: Random(6));
      setGrid(g, [
        [4, 4, 4, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      final res = g.move(SlideDirection.left);

      expect(res.moved, isTrue);
      // От края направления: первые две сливаются в 8, третья остаётся 4.
      expect(g.tileAt(0, 0), 8);
      expect(g.tileAt(1, 0), 4);
      expect(res.merges.length, 1);
      expect(res.merges.single.value, 8);
      expect(res.gained, 8);
    });
  });

  group('очки за слияние', () {
    test('gained = сумма всех получившихся при слиянии плиток', () {
      final g = Game2048Logic(random: Random(7));
      setGrid(g, [
        [2, 2, 0, 0],
        [8, 8, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      final res = g.move(SlideDirection.left);
      // 2+2 -> 4 и 8+8 -> 16: gained = 4 + 16 = 20.
      expect(res.gained, 20);
      expect(g.score, 20);
      expect(res.merges.map((m) => m.value).toSet(), {4, 16});
    });

    test('счёт накапливается между ходами', () {
      final g = Game2048Logic(random: Random(8));
      setGrid(g, [
        [2, 2, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      g.move(SlideDirection.left); // +4
      setGrid(g, [
        [4, 4, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      final res = g.move(SlideDirection.left); // +8
      expect(res.gained, 8);
      expect(g.score, 12);
    });
  });

  group('спавн только в пустую клетку', () {
    test('после результативного хода появляется ровно одна новая плитка 2/4', () {
      // Берём много зерён: куда именно ляжет плитка — зависит от Random,
      // но всегда в пустую клетку и со значением 2 или 4.
      for (var seed = 0; seed < 40; seed++) {
        final g = Game2048Logic(random: Random(seed));
        setGrid(g, [
          [2, 2, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ]);
        final res = g.move(SlideDirection.left);
        expect(res.moved, isTrue);

        final spawn = res.spawned;
        expect(spawn, isNotNull, reason: 'seed=$seed: ждали новую плитку');
        expect(spawn!.value == 2 || spawn.value == 4, isTrue);
        // Появилась не на месте получившейся четвёрки (0,0).
        expect(spawn.x == 0 && spawn.y == 0, isFalse,
            reason: 'seed=$seed: плитка села на занятую (0,0)');
        // Значение в сетке совпадает с заявленным спавном.
        expect(g.tileAt(spawn.x, spawn.y), spawn.value);
        // На поле теперь: четвёрка + новая плитка = 2 непустых.
        expect(tileCount(g), 2);
      }
    });

    test('заполнение одной свободной клетки кладёт плитку именно туда', () {
      // 15 занятых клеток без возможных слияний по вертикали, одна пустая.
      // Дырка — внизу столбца x=2, поэтому только ход ВНИЗ сдвинет этот столбец
      // и освободит спавну единственную клетку (2,0) — независимо от зерна.
      for (var seed = 0; seed < 30; seed++) {
        final g = Game2048Logic(random: Random(seed));
        setGrid(g, [
          [2, 4, 2, 4],
          [4, 2, 4, 2],
          [2, 4, 2, 4],
          [4, 2, 0, 2],
        ]);
        final res = g.move(SlideDirection.down);
        expect(res.moved, isTrue, reason: 'seed=$seed');
        expect(res.merges, isEmpty, reason: 'seed=$seed: слияний быть не должно');
        // После сдвига вниз столбец x=2 = [0,2,4,2]; спавн займёт (2,0).
        final spawn = res.spawned!;
        expect(spawn.x, 2, reason: 'seed=$seed');
        expect(spawn.y, 0, reason: 'seed=$seed');
      }
    });
  });

  group('ход без изменений', () {
    test('упёртая в край стенка не двигается: moved=false, без спавна', () {
      final g = Game2048Logic(random: Random(9));
      setGrid(g, [
        [2, 4, 8, 16],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      final snapshot = gridRows(g);
      final res = g.move(SlideDirection.left);

      expect(res.moved, isFalse);
      expect(res.gained, 0);
      expect(res.spawned, isNull);
      expect(res.merges, isEmpty);
      // Поле не изменилось — новая плитка не появилась.
      expect(gridRows(g), snapshot);
      expect(tileCount(g), 4);
    });
  });

  group('конец игры', () {
    test('полное поле без возможных слияний -> isGameOver', () {
      final g = Game2048Logic(random: Random(10));
      // Шахматка 2/4 — нет двух равных соседей ни по строке, ни по столбцу.
      setGrid(g, [
        [2, 4, 2, 4],
        [4, 2, 4, 2],
        [2, 4, 2, 4],
        [4, 2, 4, 2],
      ]);
      expect(g.hasEmpty, isFalse);
      expect(g.isGameOver, isTrue);

      // Любой ход ничего не меняет (некуда двигать и нечего сливать).
      for (final d in SlideDirection.values) {
        final res = g.move(d);
        expect(res.moved, isFalse, reason: 'ход $d не должен ничего менять');
      }
    });

    test('полное поле с возможным слиянием -> ещё не конец', () {
      final g = Game2048Logic(random: Random(12));
      setGrid(g, [
        [2, 4, 2, 4],
        [4, 2, 4, 2],
        [2, 4, 2, 4],
        [4, 2, 4, 4], // две 4 рядом в нижней строке — слияние возможно
      ]);
      expect(g.hasEmpty, isFalse);
      expect(g.isGameOver, isFalse);

      final res = g.move(SlideDirection.left);
      expect(res.moved, isTrue);
      expect(res.gained, 8);
    });
  });

  group('reset', () {
    test('сбрасывает счёт, флаг победы и раскладывает заново', () {
      final g = Game2048Logic(random: Random(13));
      setGrid(g, [
        [2, 2, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      g.move(SlideDirection.left);
      expect(g.score, greaterThan(0));

      g.reset();
      expect(g.score, 0);
      expect(g.won, isFalse);
      expect(tileCount(g), 2);
    });
  });
}
