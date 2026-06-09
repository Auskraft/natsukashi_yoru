import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/block_puzzle/components/block_puzzle_logic.dart';

/// Единичная клетка-фигура — удобный «кирпич» для точечных сценариев.
const _dot = BlockShape([Point(0, 0)], 1, 1);

/// Горизонтальная палочка длины [n].
BlockShape _hLine(int n) =>
    BlockShape([for (var i = 0; i < n; i++) Point(i, 0)], n, 1);

/// Вертикальная палочка длины [n].
BlockShape _vLine(int n) =>
    BlockShape([for (var i = 0; i < n; i++) Point(0, i)], 1, n);

/// Полностью занять поле, кроме перечисленных пустых клеток.
void _fillBoardExcept(BlockPuzzleLogic g, Set<Point<int>> empty) {
  for (var y = 0; y < BlockPuzzleLogic.size; y++) {
    for (var x = 0; x < BlockPuzzleLogic.size; x++) {
      g.board[y][x] = empty.contains(Point(x, y)) ? null : BlockColor.teal;
    }
  }
}

/// Занять строку [y] во всех столбцах, кроме [gapX] (остальное поле не трогаем).
void _fillRowExcept(BlockPuzzleLogic g, int y, int gapX) {
  for (var x = 0; x < BlockPuzzleLogic.size; x++) {
    if (x != gapX) g.board[y][x] = BlockColor.teal;
  }
}

/// Занять столбец [x] во всех строках, кроме [gapY] (остальное поле не трогаем).
void _fillColExcept(BlockPuzzleLogic g, int x, int gapY) {
  for (var y = 0; y < BlockPuzzleLogic.size; y++) {
    if (y != gapY) g.board[y][x] = BlockColor.teal;
  }
}

/// Положить фигуру [shape] в слот [i] лотка, остальные слоты — очистить.
void _setTraySingle(BlockPuzzleLogic g, int i, BlockShape shape,
    [BlockColor color = BlockColor.violet]) {
  for (var k = 0; k < BlockPuzzleLogic.traySize; k++) {
    g.tray[k] = null;
  }
  g.tray[i] = TrayPiece(shape, color);
}

void main() {
  group('каталог фигур', () {
    test('все фигуры размером 1..5 и нормализованы к (0,0)', () {
      expect(kBlockShapes, isNotEmpty);
      for (final s in kBlockShapes) {
        expect(s.size, greaterThanOrEqualTo(1), reason: 'размер < 1');
        expect(s.size, lessThanOrEqualTo(9), reason: 'размер > 9 (макс — квадрат 3×3)');
        final minX = s.cells.map((p) => p.x).reduce(min);
        final minY = s.cells.map((p) => p.y).reduce(min);
        expect(minX, 0, reason: 'фигура не прижата к x=0');
        expect(minY, 0, reason: 'фигура не прижата к y=0');
        // Рамка согласована с клетками.
        final maxX = s.cells.map((p) => p.x).reduce(max);
        final maxY = s.cells.map((p) => p.y).reduce(max);
        expect(s.width, maxX + 1);
        expect(s.height, maxY + 1);
      }
    });

    test('есть палочки 1..5, квадраты 2x2 и 3x3', () {
      bool has(int cells, int w, int h) =>
          kBlockShapes.any((s) => s.size == cells && s.width == w && s.height == h);
      for (var n = 1; n <= 5; n++) {
        expect(has(n, n, 1), isTrue, reason: 'нет гориз. палочки длины $n');
      }
      expect(has(4, 2, 2), isTrue, reason: 'нет квадрата 2x2');
      expect(has(9, 3, 3), isTrue, reason: 'нет квадрата 3x3');
    });
  });

  group('старт', () {
    test('поле пусто, лоток полон, счёт 0, не мертва', () {
      final g = BlockPuzzleLogic(random: Random(1));
      expect(g.score, 0);
      expect(g.dead, isFalse);
      expect(g.piecesLeft, BlockPuzzleLogic.traySize);
      for (final row in g.board) {
        expect(row.every((c) => c == null), isTrue);
      }
    });
  });

  group('canPlaceShape', () {
    test('палочка в углу пустого поля — можно', () {
      final g = BlockPuzzleLogic(random: Random(2));
      expect(g.canPlaceShape(_hLine(5), 0, 0), isTrue);
    });

    test('выход за правый край — нельзя', () {
      final g = BlockPuzzleLogic(random: Random(2));
      // 5 клеток с anchor x=6 уходят за x=9.
      expect(g.canPlaceShape(_hLine(5), 6, 0), isFalse);
    });

    test('наложение на занятую клетку — нельзя', () {
      final g = BlockPuzzleLogic(random: Random(2));
      g.board[0][1] = BlockColor.pink;
      expect(g.canPlaceShape(_hLine(3), 0, 0), isFalse);
    });
  });

  group('place: базовая постановка', () {
    test('кладёт клетки, начисляет очки за размер, убирает из лотка', () {
      final g = BlockPuzzleLogic(random: Random(3));
      // Заполняем все 3 слота, чтобы установка слота 0 не вызвала рефилл лотка
      // (рефилл происходит, только когда ВСЕ слоты пусты).
      g.tray[0] = TrayPiece(_hLine(3), BlockColor.green);
      g.tray[1] = const TrayPiece(_dot, BlockColor.violet);
      g.tray[2] = const TrayPiece(_dot, BlockColor.violet);

      final res = g.place(0, 2, 4);
      expect(res.placed, isTrue);
      expect(res.gained, 3, reason: 'без линий очки = число клеток');
      expect(g.score, 3);
      expect(res.placedCells.toSet(), {
        const Point(2, 4),
        const Point(3, 4),
        const Point(4, 4),
      });
      for (final p in res.placedCells) {
        expect(g.board[p.y][p.x], BlockColor.green);
      }
      expect(g.tray[0], isNull);
      expect(res.linesCleared, 0);
    });

    test('недопустимая постановка ничего не меняет', () {
      final g = BlockPuzzleLogic(random: Random(3));
      _setTraySingle(g, 1, _hLine(3));
      g.board[0][1] = BlockColor.teal; // перекрываем целевую клетку

      final res = g.place(1, 0, 0);
      expect(res.placed, isFalse);
      expect(res.gained, 0);
      expect(g.score, 0);
      expect(g.tray[1], isNotNull, reason: 'фигура осталась в лотке');
    });

    test('пустой слот не ставится', () {
      final g = BlockPuzzleLogic(random: Random(3));
      _setTraySingle(g, 0, _dot);
      final res = g.place(2, 0, 0); // слот 2 пуст
      expect(res.placed, isFalse);
    });
  });

  group('place: очистка линий', () {
    test('очистка СТРОКИ: одна точка достраивает ряд', () {
      final g = BlockPuzzleLogic(random: Random(4));
      // Строка y=5 заполнена везде, кроме (9,5); остальное поле пусто.
      _fillRowExcept(g, 5, 9);
      _setTraySingle(g, 0, _dot, BlockColor.yellow);

      final res = g.place(0, 9, 5);
      expect(res.placed, isTrue);
      expect(res.clearedRows, [5]);
      expect(res.clearedCols, isEmpty);
      expect(res.linesCleared, 1);
      // Вся строка теперь пуста.
      for (var x = 0; x < BlockPuzzleLogic.size; x++) {
        expect(g.board[5][x], isNull, reason: 'клетка ($x,5) должна очиститься');
      }
      // Очки: 1 клетка фигуры + бонус за 1 линию (=10).
      expect(res.gained, 1 + 10);
      // Исход несёт цвета очищенных клеток (для частиц).
      expect(res.clearedCells.length, BlockPuzzleLogic.size);
    });

    test('очистка СТОЛБЦА: вертикальная палочка достраивает колонку', () {
      final g = BlockPuzzleLogic(random: Random(5));
      // Столбец x=3 пуст в строках 0..4, занят в 5..9; остальное поле пусто.
      for (var y = 5; y < BlockPuzzleLogic.size; y++) {
        g.board[y][3] = BlockColor.teal;
      }
      _setTraySingle(g, 0, _vLine(5), BlockColor.blue);

      final res = g.place(0, 3, 0);
      expect(res.placed, isTrue);
      expect(res.clearedCols, [3]);
      expect(res.clearedRows, isEmpty);
      for (var y = 0; y < BlockPuzzleLogic.size; y++) {
        expect(g.board[y][3], isNull, reason: 'клетка (3,$y) должна очиститься');
      }
    });

    test('строка и столбец очищаются ОДНОВРЕМЕННО одной постановкой', () {
      final g = BlockPuzzleLogic(random: Random(6));
      // Строка 0 и столбец 0 заполнены везде, кроме общей клетки (0,0); прочее
      // поле пусто. Установка точки в (0,0) достраивает обе линии разом.
      _fillRowExcept(g, 0, 0);
      _fillColExcept(g, 0, 0);
      _setTraySingle(g, 0, _dot, BlockColor.orange);

      final res = g.place(0, 0, 0);
      expect(res.placed, isTrue);
      expect(res.clearedRows, [0]);
      expect(res.clearedCols, [0]);
      expect(res.linesCleared, 2);
      // Клетка-пересечение учтена в clearedCells лишь один раз (без дублей):
      // 10 в строке + 10 в столбце − 1 общая = 19.
      final keys =
          res.clearedCells.map((c) => '${c.pos.x},${c.pos.y}').toSet();
      expect(keys.length, res.clearedCells.length,
          reason: 'пересечение строки и столбца не должно дублироваться');
      expect(res.clearedCells.length, 2 * BlockPuzzleLogic.size - 1);
      // Обе линии очищены полностью.
      for (var i = 0; i < BlockPuzzleLogic.size; i++) {
        expect(g.board[0][i], isNull);
        expect(g.board[i][0], isNull);
      }
    });

    test('бонус за линии растёт быстрее линейного', () {
      int bonusFor(int lines) {
        final g = BlockPuzzleLogic(random: Random(100 + lines));
        if (lines == 1) {
          _fillRowExcept(g, 0, 9);
          _setTraySingle(g, 0, _dot);
          final r = g.place(0, 9, 0);
          return r.gained - 1; // минус клетка фигуры
        }
        // lines == 2: пересечение в (0,0) очищает строку 0 и столбец 0.
        _fillRowExcept(g, 0, 0);
        _fillColExcept(g, 0, 0);
        _setTraySingle(g, 0, _dot);
        final r = g.place(0, 0, 0);
        return r.gained - 1;
      }

      final b1 = bonusFor(1);
      final b2 = bonusFor(2);
      expect(b2, greaterThan(2 * b1),
          reason: 'две линии разом должны давать больше, чем 2×одна');
    });
  });

  group('лоток', () {
    test('после трёх постановок раздаётся новый набор', () {
      final g = BlockPuzzleLogic(random: Random(7));
      // Кладём три точки в три угла — линий не возникнет.
      g.tray[0] = const TrayPiece(_dot, BlockColor.teal);
      g.tray[1] = const TrayPiece(_dot, BlockColor.pink);
      g.tray[2] = const TrayPiece(_dot, BlockColor.blue);

      final r0 = g.place(0, 0, 0);
      expect(r0.newTray, isFalse);
      expect(g.piecesLeft, 2);

      final r1 = g.place(1, 9, 0);
      expect(r1.newTray, isFalse);
      expect(g.piecesLeft, 1);

      final r2 = g.place(2, 0, 9);
      expect(r2.newTray, isTrue, reason: 'третья постановка обновляет лоток');
      expect(g.piecesLeft, BlockPuzzleLogic.traySize);
    });
  });

  group('конец игры', () {
    test('валидная постановка приводит к тупику → gameOver, фигура осталась', () {
      final g = BlockPuzzleLogic(random: Random(8));
      // Оставляем три ИЗОЛИРОВАННЫЕ одиночные дыры: (0,0), (2,0), (0,2).
      // Дыры в строке 0 и столбце 0 разнесены так, что постановка точки в (0,0)
      // НЕ собирает полной линии (в строке 0 остаётся дыра (2,0), в столбце 0 —
      // дыра (0,2)). После постановки на поле остаются лишь одиночные клетки.
      // Дыры по диагонали (i,i) — ни одна строка/столбец не полны (значит
      // постановка не сожжёт линий), плюс лишние дыры в строке 0 и столбце 0,
      // чтобы точка в (0,0) их не достроила. Все дыры не соседствуют → двойка
      // не влезает никуда.
      final holes = <Point<int>>{
        for (var i = 0; i < BlockPuzzleLogic.size; i++) Point(i, i),
        const Point(2, 0),
        const Point(0, 2),
      };
      _fillBoardExcept(g, holes);
      // Лоток: точка (слот 0) + палочка-двойка (слот 1), которая в одиночные
      // дыры не влезает нигде.
      g.tray[0] = const TrayPiece(_dot, BlockColor.teal);
      g.tray[1] = TrayPiece(_hLine(2), BlockColor.pink);
      g.tray[2] = null;

      expect(g.dead, isFalse);
      final res = g.place(0, 0, 0); // ставим точку в (0,0)
      expect(res.placed, isTrue);
      expect(res.linesCleared, 0, reason: 'разнесённые дыры — линий нет');
      expect(res.newTray, isFalse, reason: 'в лотке ещё лежит палочка');
      // Палочка-двойка теперь никуда не помещается → конец игры.
      expect(res.gameOver, isTrue);
      expect(g.dead, isTrue);
      expect(g.tray[1], isNotNull, reason: 'неуместившаяся фигура осталась');
    });

    test('полностью занятое поле: ничего не помещается', () {
      final g = BlockPuzzleLogic(random: Random(9));
      _fillBoardExcept(g, const {});
      expect(g.canPlaceAnywhere(_dot), isFalse);
      expect(g.canPlaceAnywhere(_hLine(2)), isFalse);
    });

    test('живой пока есть ход хотя бы для одной фигуры лотка', () {
      final g = BlockPuzzleLogic(random: Random(10));
      // Поле забито, кроме одной клетки (4,4): двойка не влезет, но точка — да.
      _fillBoardExcept(g, {const Point(4, 4)});
      g.tray[0] = TrayPiece(_hLine(2), BlockColor.blue); // не влезает
      g.tray[1] = const TrayPiece(_dot, BlockColor.green); // влезает в (4,4)
      g.tray[2] = null;
      expect(g.canPlaceAnywhere(_hLine(2)), isFalse);
      expect(g.canPlaceAnywhere(_dot), isTrue);
    });
  });

  group('детерминизм', () {
    test('один и тот же seed даёт одинаковые наборы лотка', () {
      List<int> traySig(int seed) {
        final g = BlockPuzzleLogic(random: Random(seed));
        return [
          for (final p in g.tray) ...[
            p!.shape.size,
            p.shape.width,
            p.shape.height,
            p.color.index,
          ],
        ];
      }

      expect(traySig(42), traySig(42));
    });
  });
}
