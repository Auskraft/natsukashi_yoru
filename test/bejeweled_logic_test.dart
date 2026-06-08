import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/bejeweled/components/bejeweled_logic.dart';

/// Хелпер: заполнить доску из «карты» цветов для детерминизма.
/// rows×cols значений int — цвет камня (особых нет).
void _setBoard(BejeweledLogic g, List<List<int>> map) {
  for (var y = 0; y < g.rows; y++) {
    for (var x = 0; x < g.cols; x++) {
      g.board[y][x] = Gem(map[y][x]);
    }
  }
}

/// «Шахматная» заливка двумя цветами — гарантированно без матчей.
List<List<int>> _checker(int cols, int rows, [int a = 0, int b = 1]) {
  return List.generate(
    rows,
    (y) => List.generate(cols, (x) => (x + y).isEven ? a : b),
  );
}

void main() {
  group('Gem', () {
    test('равенство учитывает цвет и особость', () {
      expect(const Gem(2), const Gem(2));
      expect(const Gem(2) == const Gem(3), isFalse);
      expect(
        const Gem(2, Special.lineH) == const Gem(2, Special.lineV),
        isFalse,
      );
    });

    test('withSpecial сохраняет цвет', () {
      const g = Gem(4);
      final s = g.withSpecial(Special.colorBomb);
      expect(s.color, 4);
      expect(s.special, Special.colorBomb);
      expect(s.isSpecial, isTrue);
    });
  });

  group('BejeweledLogic — базовое', () {
    test('старт: доска заполнена и без готовых матчей', () {
      final g = BejeweledLogic(random: Random(1));
      // Все клетки заполнены валидными цветами.
      for (var y = 0; y < g.rows; y++) {
        for (var x = 0; x < g.cols; x++) {
          final c = g.gemAt(x, y).color;
          expect(c, inInclusiveRange(0, g.colors - 1));
        }
      }
      // Нет ни одной горизонтальной/вертикальной тройки.
      var triple = false;
      for (var y = 0; y < g.rows; y++) {
        for (var x = 0; x < g.cols; x++) {
          if (x >= 2 &&
              g.gemAt(x, y).color == g.gemAt(x - 1, y).color &&
              g.gemAt(x, y).color == g.gemAt(x - 2, y).color) {
            triple = true;
          }
          if (y >= 2 &&
              g.gemAt(x, y).color == g.gemAt(x, y - 1).color &&
              g.gemAt(x, y).color == g.gemAt(x, y - 2).color) {
            triple = true;
          }
        }
      }
      expect(triple, isFalse, reason: 'стартовая доска не должна иметь троек');
      expect(g.score, 0);
      expect(g.gameOver, isFalse);
    });

    test('areAdjacent: только соседи по стороне', () {
      final g = BejeweledLogic(random: Random(1));
      expect(g.areAdjacent(const Point(2, 2), const Point(3, 2)), isTrue);
      expect(g.areAdjacent(const Point(2, 2), const Point(2, 3)), isTrue);
      expect(g.areAdjacent(const Point(2, 2), const Point(3, 3)), isFalse);
      expect(g.areAdjacent(const Point(2, 2), const Point(4, 2)), isFalse);
      expect(g.areAdjacent(const Point(2, 2), const Point(2, 2)), isFalse);
    });
  });

  group('Обмен без матча', () {
    test('несоседние клетки — обмена нет', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(1));
      _setBoard(g, _checker(8, 8));
      final before = g.gemAt(0, 0);
      final res = g.trySwap(const Point(0, 0), const Point(2, 0));
      expect(res.swapped, isFalse);
      expect(res.reverted, isFalse);
      expect(g.gemAt(0, 0), before, reason: 'доска не должна меняться');
    });

    test('валидный обмен без матча откатывается', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(1));
      // Шахматка: любой обмен соседей не создаёт тройку.
      _setBoard(g, _checker(8, 8));
      final a = const Point(0, 0);
      final b = const Point(1, 0);
      final ga = g.gemAt(a.x, a.y);
      final gb = g.gemAt(b.x, b.y);

      final res = g.trySwap(a, b);
      expect(res.swapped, isFalse);
      expect(res.reverted, isTrue);
      expect(res.steps, isEmpty);
      // Камни вернулись на места.
      expect(g.gemAt(a.x, a.y), ga);
      expect(g.gemAt(b.x, b.y), gb);
      expect(g.score, 0);
    });
  });

  group('Обычный матч-3', () {
    test('обмен, дающий тройку, очищает её и начисляет очки', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(1));
      _setBoard(g, _checker(8, 8));
      // Изолированный матч-3 на чистом фоне (цвета 2/3), чтобы не зацепить
      // соседние клетки. Готовим row0: [1,1,?,4] и под (2,0) лежит 1.
      // Свап (2,0)<->(2,1) приносит 1 в (2,0) => ровно 1 1 1, дальше — 4 (стоп).
      _setBoard(g, _checker(8, 8, 2, 3));
      g.board[0][0] = const Gem(1);
      g.board[0][1] = const Gem(1);
      g.board[0][2] = const Gem(4); // временно другой
      g.board[0][3] = const Gem(2); // ограничитель справа (не 1) — ровно тройка
      g.board[1][2] = const Gem(1); // приедет вверх при свапе
      // Глушим вертикальные тройки под местом матча.
      g.board[1][0] = const Gem(2);
      g.board[1][1] = const Gem(3);
      g.board[2][2] = const Gem(2);

      final res = g.trySwap(const Point(2, 0), const Point(2, 1));
      expect(res.swapped, isTrue);
      expect(res.reverted, isFalse);
      expect(res.steps, isNotEmpty);
      // В первой волне лопнули ровно 3 камня цвета 1 и не родилось особых.
      final firstWave = res.steps.first;
      final cnt = firstWave.cleared.where((c) => c.color == 1).length;
      expect(cnt, 3);
      expect(firstWave.created, isEmpty);
      expect(g.score, greaterThan(0));
      expect(res.gained, g.score);
    });
  });

  group('Создание особых камней', () {
    test('матч-4 в линию создаёт линейный камень', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(1));
      _setBoard(g, _checker(8, 8, 2, 3));
      // Готовим горизонтальный матч-4 в строке 0 через вертикальный свап.
      //   row0: 5 5 5 0   и под (3,0) лежит 5 -> свап (3,0)<->(3,1) даёт 5555
      g.board[0][0] = const Gem(5);
      g.board[0][1] = const Gem(5);
      g.board[0][2] = const Gem(5);
      g.board[0][3] = const Gem(2); // временно другой цвет
      g.board[1][3] = const Gem(5); // приедет вверх
      // Убедимся, что соседние клетки не создают лишних матчей.
      g.board[1][0] = const Gem(2);
      g.board[1][1] = const Gem(3);
      g.board[1][2] = const Gem(2);

      final res = g.trySwap(const Point(3, 0), const Point(3, 1));
      expect(res.swapped, isTrue);
      // В первой волне родился ровно один особый — линейный (lineH),
      // т.к. исходная линия горизонтальная.
      final created = res.steps.first.created;
      expect(created.length, 1);
      expect(created.first.special, Special.lineH);
      expect(created.first.color, 5);
      // Особый родился в клетке обмена (3,0) — она лежала на линии матча.
      expect(created.first.pos, const Point(3, 0));
      // Эта клетка НЕ числится среди лопнувших (там вырос особый).
      final clearedAtBirth = res.steps.first.cleared
          .where((c) => c.pos == const Point(3, 0))
          .isEmpty;
      expect(clearedAtBirth, isTrue);
    });

    test('матч-5 в линию создаёт цвет-бомбу', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(1));
      _setBoard(g, _checker(8, 8, 2, 3));
      // Горизонтальный матч-5 в строке 0 через вертикальный свап в центре.
      //   row0: 4 4 _ 4 4  с 4 под (2,0) -> свап (2,0)<->(2,1) => 44444
      g.board[0][0] = const Gem(4);
      g.board[0][1] = const Gem(4);
      g.board[0][2] = const Gem(2); // временно другой
      g.board[0][3] = const Gem(4);
      g.board[0][4] = const Gem(4);
      g.board[1][2] = const Gem(4); // приедет вверх
      // Глушим соседние тройки.
      g.board[1][0] = const Gem(2);
      g.board[1][1] = const Gem(3);
      g.board[1][3] = const Gem(3);
      g.board[1][4] = const Gem(2);

      final res = g.trySwap(const Point(2, 0), const Point(2, 1));
      expect(res.swapped, isTrue);
      final created = res.steps.first.created;
      expect(created.length, 1);
      expect(created.first.special, Special.colorBomb);
      expect(created.first.color, 4);
      // Бомба родилась в клетке обмена (2,0).
      expect(created.first.pos, const Point(2, 0));
    });

    test('особый рождается в клетке обмена (приоритет места хода)', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(1));
      _setBoard(g, _checker(8, 8, 2, 3));
      // Матч-4 горизонтально; клетка обмена (3,0) лежит на линии — там и родится.
      g.board[0][0] = const Gem(5);
      g.board[0][1] = const Gem(5);
      g.board[0][2] = const Gem(5);
      g.board[0][3] = const Gem(2);
      g.board[1][3] = const Gem(5);
      g.board[1][0] = const Gem(2);
      g.board[1][1] = const Gem(3);
      g.board[1][2] = const Gem(2);

      final res = g.trySwap(const Point(3, 0), const Point(3, 1));
      final created = res.steps.first.created;
      expect(created.first.pos, const Point(3, 0));
    });
  });

  group('Активация особых камней', () {
    test('линейный (lineH) при активации чистит всю свою строку', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(1));
      _setBoard(g, _checker(8, 8, 2, 3));
      // Кладём lineH в (4,4). Рядом строим тройку, в которую он попадёт.
      // Сделаем вертикальный матч-3 в столбце 4: (4,3),(4,4),(4,5) цвета 1,
      // а сам линейный камень имеет цвет 1 и попадает в этот матч → активация.
      g.board[3][4] = const Gem(1);
      g.board[4][4] = const Gem(1, Special.lineH);
      g.board[5][4] = const Gem(1);
      // Свап, создающий этот вертикальный матч: поставим (4,5) другим и под ним 1.
      // Упростим: матч уже стоит; чтобы его «активировать» свапом, временно
      // сломаем и почним обменом.
      g.board[5][4] = const Gem(2);
      g.board[5][3] = const Gem(1); // приедет в (5,4)? нет — свап (5,4)<->(5,3)

      final res = g.trySwap(const Point(4, 5), const Point(3, 5));
      expect(res.swapped, isTrue);
      // Раз линейный лопнул — вся строка y=4 должна была очиститься в 1-й волне.
      final firstWave = res.steps.first;
      final clearedRow4 =
          firstWave.cleared.where((c) => c.pos.y == 4).map((c) => c.pos.x);
      expect(
        clearedRow4.toSet().length,
        g.cols,
        reason: 'линейный lineH чистит все 8 клеток своей строки',
      );
    });

    test('линейный (lineV) при активации чистит весь свой столбец', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(1));
      _setBoard(g, _checker(8, 8, 2, 3));
      // lineV цвета 1 в (4,4); строим горизонтальную тройку в строке 4.
      g.board[4][3] = const Gem(1);
      g.board[4][4] = const Gem(1, Special.lineV);
      g.board[4][5] = const Gem(2); // сломаем
      g.board[3][5] = const Gem(1); // свап (4,5)<->(5,5)? нет

      // Создаём матч: (4,3)=1,(4,4)=1(special),(4,5) станет 1 после свапа.
      g.board[4][6] = const Gem(1); // приедет в (4,5) при свапе (4,5)<->(4,6)
      final res = g.trySwap(const Point(5, 4), const Point(6, 4));
      expect(res.swapped, isTrue);
      final firstWave = res.steps.first;
      final clearedCol4 =
          firstWave.cleared.where((c) => c.pos.x == 4).map((c) => c.pos.y);
      expect(
        clearedCol4.toSet().length,
        g.rows,
        reason: 'линейный lineV чистит все 8 клеток своего столбца',
      );
    });

    test('цвет-бомба при обмене с обычным чистит камни своего цвета', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(1));
      // Контролируемая доска: считаем камни цвета бомбы.
      _setBoard(g, _checker(8, 8, 2, 3)); // только цвета 2 и 3
      // Поставим бомбу цвета 2 в (0,0) и обменяем с соседом — активируется.
      g.board[0][0] = const Gem(2, Special.colorBomb);
      g.board[0][1] = const Gem(3);

      final color2before = _countColor(g, 2);
      expect(color2before, greaterThan(1));

      final res = g.trySwap(const Point(0, 0), const Point(1, 0));
      expect(res.swapped, isTrue);
      // В первой волне должны лопнуть все камни цвета 2, что были до добора.
      final cleared2 = res.steps.first.cleared.where((c) => c.color == 2).length;
      expect(cleared2, greaterThanOrEqualTo(color2before - 1),
          reason: 'цвет-бомба выносит весь свой цвет');
      expect(g.score, greaterThan(0));
    });

    test('обмен двух особых срабатывает без обычного матча', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(1));
      _setBoard(g, _checker(8, 8, 2, 3));
      // Два линейных рядом, без обычного матча вокруг.
      g.board[4][4] = const Gem(2, Special.lineH);
      g.board[4][5] = const Gem(3, Special.lineV);

      final res = g.trySwap(const Point(4, 4), const Point(5, 4));
      expect(res.swapped, isTrue);
      expect(res.reverted, isFalse);
      expect(res.steps, isNotEmpty);
      // Очистка затронула обе линии (как минимум строку и столбец).
      final cleared = res.steps.first.cleared;
      expect(cleared.length, greaterThanOrEqualTo(g.cols));
    });
  });

  group('Каскады и гравитация', () {
    test('после хода доска снова полностью заполнена', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(3));
      _setBoard(g, _checker(8, 8));
      g.board[0][0] = const Gem(1);
      g.board[0][1] = const Gem(1);
      g.board[0][2] = const Gem(0);
      g.board[1][2] = const Gem(1);
      g.board[1][0] = const Gem(0);
      g.board[1][1] = const Gem(0);

      g.trySwap(const Point(2, 0), const Point(2, 1));
      // Нет пустот (цвет -1) после разрешения.
      var empties = 0;
      for (var y = 0; y < g.rows; y++) {
        for (var x = 0; x < g.cols; x++) {
          if (g.gemAt(x, y).color == -1) empties++;
        }
      }
      expect(empties, 0, reason: 'гравитация и добор заполняют доску');
    });

    test('очки каскада суммируются и равны приросту счёта', () {
      final g = BejeweledLogic(cols: 8, rows: 8, random: Random(9));
      _setBoard(g, _checker(8, 8));
      g.board[0][0] = const Gem(1);
      g.board[0][1] = const Gem(1);
      g.board[0][2] = const Gem(0);
      g.board[1][2] = const Gem(1);
      g.board[1][0] = const Gem(0);
      g.board[1][1] = const Gem(0);

      final res = g.trySwap(const Point(2, 0), const Point(2, 1));
      final sumSteps = res.steps.fold<int>(0, (s, st) => s + st.gained);
      expect(res.gained, sumSteps);
      expect(g.score, res.gained);
      // Номера волн идут по порядку с 1.
      for (var i = 0; i < res.steps.length; i++) {
        expect(res.steps[i].wave, i + 1);
      }
    });
  });
}

int _countColor(BejeweledLogic g, int color) {
  var n = 0;
  for (var y = 0; y < g.rows; y++) {
    for (var x = 0; x < g.cols; x++) {
      if (g.gemAt(x, y).color == color) n++;
    }
  }
  return n;
}
