import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/minesweeper/components/minesweeper_logic.dart';

/// Клетки безопасного квадрата 3×3 вокруг (cx, cy), обрезанные по полю.
List<Point<int>> _safeZone(MinesweeperLogic g, int cx, int cy) {
  final zone = <Point<int>>[];
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      final x = cx + dx;
      final y = cy + dy;
      if (x >= 0 && y >= 0 && x < g.cols && y < g.rows) {
        zone.add(Point(x, y));
      }
    }
  }
  return zone;
}

/// Сколько всего мин реально лежит на доске.
int _countMines(MinesweeperLogic g) {
  var n = 0;
  for (var y = 0; y < g.rows; y++) {
    for (var x = 0; x < g.cols; x++) {
      if (g.cellAt(x, y).mine) n++;
    }
  }
  return n;
}

/// Раскрыть всю доску, кроме мин (для сценария победы). Использует знание
/// о расположении мин — допустимо в тесте, так как первый клик уже расставил их.
RevealResult _revealAllSafe(MinesweeperLogic g) {
  var last = RevealResult.empty();
  for (var y = 0; y < g.rows; y++) {
    for (var x = 0; x < g.cols; x++) {
      if (!g.cellAt(x, y).mine) {
        final r = g.reveal(x, y);
        if (r.cascade > 0 || r.hitMine) last = r;
      }
    }
  }
  return last;
}

void main() {
  group('MinesweeperLogic — старт и счётчики', () {
    test('после reset поле скрыто, не выиграно/проиграно', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(1));
      expect(g.won, isFalse);
      expect(g.lost, isFalse);
      expect(g.isOver, isFalse);
      expect(g.remainingMines, 10);
      expect(g.flags, 0);
      for (var y = 0; y < g.rows; y++) {
        for (var x = 0; x < g.cols; x++) {
          expect(g.cellAt(x, y).state, CellState.hidden);
        }
      }
    });

    test('геометрия доски совпадает с cols×rows', () {
      final g = MinesweeperLogic(12, 7, 15, random: Random(2));
      expect(g.board.length, 7);
      expect(g.board.every((row) => row.length == 12), isTrue);
    });
  });

  group('MinesweeperLogic — первый клик безопасен', () {
    test('первый клик никогда не мина и не подрывает', () {
      // Проверяем устойчиво по многим зёрнам и точкам клика.
      for (var seed = 0; seed < 40; seed++) {
        final g = MinesweeperLogic(9, 9, 10, random: Random(seed));
        final cx = seed % 9;
        final cy = (seed * 7) % 9;
        final r = g.reveal(cx, cy);
        expect(r.hitMine, isFalse, reason: 'seed=$seed клик ($cx,$cy)');
        expect(g.lost, isFalse, reason: 'seed=$seed');
        expect(g.cellAt(cx, cy).mine, isFalse, reason: 'seed=$seed');
      }
    });

    test('вся зона 3×3 вокруг первого клика свободна от мин', () {
      for (var seed = 0; seed < 40; seed++) {
        final g = MinesweeperLogic(9, 9, 10, random: Random(seed));
        const cx = 4;
        const cy = 4;
        g.reveal(cx, cy);
        for (final p in _safeZone(g, cx, cy)) {
          expect(g.cellAt(p.x, p.y).mine, isFalse,
              reason: 'seed=$seed зона содержит мину в $p');
        }
      }
    });

    test('расставлено ровно [mines] мин', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(5));
      g.reveal(4, 4);
      expect(_countMines(g), 10);
    });

    test('число-подсказка = числу мин среди соседей', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(9));
      g.reveal(4, 4);
      for (var y = 0; y < g.rows; y++) {
        for (var x = 0; x < g.cols; x++) {
          final c = g.cellAt(x, y);
          if (c.mine) continue;
          var n = 0;
          for (final p in _safeZone(g, x, y)) {
            if (!(p.x == x && p.y == y) && g.cellAt(p.x, p.y).mine) n++;
          }
          expect(c.adjacent, n, reason: 'подсказка ($x,$y)');
        }
      }
    });
  });

  group('MinesweeperLogic — раскрытие и флуд-филл', () {
    test('флуд-филл раскрывает целую область при нуле соседей', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(3));
      final r = g.reveal(4, 4);
      // Безопасная зона 3×3 гарантирует, что у центра 0 мин-соседей,
      // значит запустится каскад и раскроется заметно больше одной клетки.
      expect(g.cellAt(4, 4).adjacent, 0);
      expect(r.cascade, greaterThan(1));
      // Все клетки исхода действительно помечены раскрытыми.
      for (final rc in r.revealed) {
        expect(g.cellAt(rc.x, rc.y).state, CellState.revealed);
      }
    });

    test('исход несёт корректные числа соседей для раскрытых клеток', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(11));
      final r = g.reveal(4, 4);
      for (final rc in r.revealed) {
        expect(rc.adjacent, g.cellAt(rc.x, rc.y).adjacent);
        expect(rc.adjacent, inInclusiveRange(0, 8));
      }
    });

    test('повторное раскрытие уже открытой клетки — пустой исход', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(4));
      g.reveal(4, 4);
      final again = g.reveal(4, 4);
      expect(again.cascade, 0);
      expect(again.hitMine, isFalse);
      expect(again.won, isFalse);
    });

    test('reveal вне поля — пустой исход', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(4));
      final r = g.reveal(-1, 100);
      expect(r.cascade, 0);
      expect(r.hitMine, isFalse);
    });

    test('одиночное раскрытие клетки с числом не запускает каскад', () {
      // Поле 3×3 с 0 мин: первый клик безопасен, мин нет вообще, поэтому
      // здесь проверяем отдельный кейс ниже. Тут — поле, где есть числа.
      // Берём узкое поле, чтобы рядом с краем оказалась клетка-число.
      final g = MinesweeperLogic(9, 9, 10, random: Random(8));
      // Кликаем в угол, наиболее вероятно дающий число (не зону нулей).
      // Если попали в ноль — тест всё равно валиден: проверяем согласованность.
      final r = g.reveal(0, 0);
      if (g.cellAt(0, 0).adjacent != 0) {
        expect(r.cascade, 1, reason: 'клетка с числом раскрывается одна');
      } else {
        expect(r.cascade, greaterThan(1));
      }
    });
  });

  group('MinesweeperLogic — флаги', () {
    test('toggleFlag меняет счётчик remainingMines и flags', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(1));
      expect(g.remainingMines, 10);
      expect(g.toggleFlag(0, 0), isTrue);
      expect(g.flags, 1);
      expect(g.remainingMines, 9);
      expect(g.cellAt(0, 0).state, CellState.flagged);

      expect(g.toggleFlag(0, 0), isTrue);
      expect(g.flags, 0);
      expect(g.remainingMines, 10);
      expect(g.cellAt(0, 0).state, CellState.hidden);
    });

    test('по флагнутой клетке reveal не срабатывает', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(1));
      g.toggleFlag(4, 4);
      final r = g.reveal(4, 4);
      expect(r.cascade, 0);
      expect(g.cellAt(4, 4).state, CellState.flagged);
      // Мины ещё не расставлены, т.к. первого раскрытия не было.
      expect(g.cellAt(4, 4).mine, isFalse);
    });

    test('нельзя поставить флаг на раскрытую клетку', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(3));
      g.reveal(4, 4); // запустит каскад, (4,4) станет revealed
      expect(g.cellAt(4, 4).state, CellState.revealed);
      expect(g.toggleFlag(4, 4), isFalse);
      expect(g.cellAt(4, 4).state, CellState.revealed);
    });

    test('remainingMines может уйти в минус при лишних флагах', () {
      final g = MinesweeperLogic(3, 3, 0, random: Random(1));
      // Мин нет: безопасно флагать любые клетки.
      g.toggleFlag(0, 0);
      g.toggleFlag(0, 1);
      expect(g.flags, 2);
      expect(g.remainingMines, -2);
    });
  });

  group('MinesweeperLogic — конец игры', () {
    test('подрыв на мине → lost, исход содержит все мины', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(6));
      g.reveal(4, 4); // расставит мины, первый клик безопасен
      // Находим любую мину и кликаем по ней.
      Point<int>? mine;
      for (var y = 0; y < g.rows && mine == null; y++) {
        for (var x = 0; x < g.cols; x++) {
          if (g.cellAt(x, y).mine) {
            mine = Point(x, y);
            break;
          }
        }
      }
      expect(mine, isNotNull);
      final r = g.reveal(mine!.x, mine.y);
      expect(r.hitMine, isTrue);
      expect(g.lost, isTrue);
      expect(g.isOver, isTrue);
      expect(r.won, isFalse);
      expect(r.explodedMines.length, _countMines(g));
      expect(r.explodedMines.contains(mine), isTrue);
    });

    test('после проигрыша reveal и toggleFlag игнорируются', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(6));
      g.reveal(4, 4);
      Point<int>? mine;
      for (var y = 0; y < g.rows && mine == null; y++) {
        for (var x = 0; x < g.cols; x++) {
          if (g.cellAt(x, y).mine) {
            mine = Point(x, y);
            break;
          }
        }
      }
      g.reveal(mine!.x, mine.y);
      expect(g.lost, isTrue);
      final r = g.reveal(0, 0);
      expect(r.cascade, 0);
      expect(g.toggleFlag(0, 0), isFalse);
    });

    test('раскрытие всех не-мин → won', () {
      final g = MinesweeperLogic(9, 9, 10, random: Random(7));
      g.reveal(4, 4); // расставит мины
      final last = _revealAllSafe(g);
      expect(g.won, isTrue);
      expect(g.lost, isFalse);
      expect(g.isOver, isTrue);
      expect(last.won, isTrue);
      expect(last.hitMine, isFalse);
    });

    test('победа на поле без мин одним кликом', () {
      final g = MinesweeperLogic(5, 5, 0, random: Random(1));
      final r = g.reveal(2, 2);
      // Нет мин → весь каскад раскрывает всё поле сразу.
      expect(r.cascade, 25);
      expect(g.won, isTrue);
      expect(r.won, isTrue);
    });
  });

  group('MinesweeperLogic — детерминизм', () {
    test('одинаковое зерно даёт идентичную расстановку мин', () {
      final a = MinesweeperLogic(9, 9, 10, random: Random(42));
      final b = MinesweeperLogic(9, 9, 10, random: Random(42));
      a.reveal(4, 4);
      b.reveal(4, 4);
      for (var y = 0; y < 9; y++) {
        for (var x = 0; x < 9; x++) {
          expect(a.cellAt(x, y).mine, b.cellAt(x, y).mine,
              reason: 'расхождение в ($x,$y)');
        }
      }
    });
  });
}
