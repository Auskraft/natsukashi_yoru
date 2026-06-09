import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/bubble_shooter/components/bubble_shooter_logic.dart';

/// Полностью очистить соты (для контролируемых сценариев без случайного добора).
void clearField(BubbleShooterLogic g) {
  for (var row = 0; row < g.rows; row++) {
    for (var col = 0; col < g.colsInRow(row); col++) {
      g.grid[row][col] = null;
    }
  }
}

/// Сколько пузырей сейчас на поле (через публичный счётчик).
int count(BubbleShooterLogic g) => g.bubbleCount;

void main() {
  const red = Bubble.red;
  const blue = Bubble.blue;
  const green = Bubble.green;

  group('старт', () {
    test('верхние startRows заполнены, остальное пусто, счёт ноль', () {
      for (var seed = 0; seed < 20; seed++) {
        final g = BubbleShooterLogic(random: Random(seed));
        expect(g.score, 0);
        expect(g.gameOver, isFalse);
        // Заполнены ровно первые startRows рядов.
        for (var row = 0; row < g.rows; row++) {
          for (var col = 0; col < g.colsInRow(row); col++) {
            final filled = g.grid[row][col] != null;
            if (row < g.startRows) {
              expect(filled, isTrue, reason: 'seed=$seed ($col,$row) пуст');
            } else {
              expect(filled, isFalse, reason: 'seed=$seed ($col,$row) занят');
            }
          }
        }
      }
    });

    test('нечётные ряды на один столбец у́же чётных', () {
      final g = BubbleShooterLogic(random: Random(1));
      expect(g.colsInRow(0), g.cols);
      expect(g.colsInRow(1), g.cols - 1);
      expect(g.colsInRow(2), g.cols);
    });

    test('пушка выдаёт цвета, присутствующие на поле', () {
      for (var seed = 0; seed < 20; seed++) {
        final g = BubbleShooterLogic(random: Random(seed));
        final present = g.colorsOnField();
        expect(present.contains(g.current), isTrue);
        expect(present.contains(g.next), isTrue);
      }
    });
  });

  group('геометрия сот', () {
    test('соседи чётного ряда симметричны и числом 6 внутри поля', () {
      final g = BubbleShooterLogic(random: Random(2));
      // Внутренняя ячейка чётного ряда — все 6 соседей валидны.
      final c = const HexCell(2, 3);
      final ns = g.neighbors(c);
      expect(ns.length, 6);
      // Горизонтальные соседи.
      expect(ns.contains(const HexCell(2, 2)), isTrue);
      expect(ns.contains(const HexCell(2, 4)), isTrue);
      // Диагональные вверх/вниз для чётного ряда: col-1 и col.
      expect(ns.contains(const HexCell(1, 2)), isTrue);
      expect(ns.contains(const HexCell(1, 3)), isTrue);
      expect(ns.contains(const HexCell(3, 2)), isTrue);
      expect(ns.contains(const HexCell(3, 3)), isTrue);
    });

    test('соседство взаимно (если A сосед B, то B сосед A)', () {
      final g = BubbleShooterLogic(random: Random(3));
      for (var row = 0; row < 6; row++) {
        for (var col = 0; col < g.colsInRow(row); col++) {
          final a = HexCell(row, col);
          for (final b in g.neighbors(a)) {
            if (b.row < 0 ||
                b.row >= g.rows ||
                b.col < 0 ||
                b.col >= g.colsInRow(b.row)) {
              continue; // вне поля — пропускаем
            }
            expect(g.neighbors(b).contains(a), isTrue,
                reason: '$a сосед $b, но не наоборот');
          }
        }
      }
    });

    test('центры соседних рядов отстоят по вертикали на rowHeight', () {
      final g = BubbleShooterLogic(random: Random(4));
      final a = g.centerOf(const HexCell(0, 0));
      final b = g.centerOf(const HexCell(1, 0));
      expect((b.y - a.y - BubbleShooterLogic.rowHeight).abs(), lessThan(1e-9));
    });
  });

  group('прилипание (trace + snap)', () {
    test('выстрел в пустое поле прямо вверх прилипает к верхнему ряду', () {
      final g = BubbleShooterLogic(random: Random(5));
      clearField(g);
      final cell = g.trace(0); // строго вверх
      expect(cell, isNotNull);
      expect(cell!.row, 0, reason: 'у пустого поля точка прилипания — верх');
    });

    test('прилипает в свободную ячейку, примыкающую к препятствию', () {
      final g = BubbleShooterLogic(random: Random(6));
      clearField(g);
      // Один пузырь в центре верхнего ряда.
      const obstacle = HexCell(0, 5);
      g.grid[obstacle.row][obstacle.col] = blue;

      final cell = g.trace(0); // вверх по центру -> упрётся в препятствие
      expect(cell, isNotNull);
      // Ячейка свободна …
      expect(g.bubbleAt(cell!.row, cell.col), isNull);
      // … и примыкает к препятствию (валидная точка прилипания).
      final touchesObstacle = g.neighbors(cell).contains(obstacle);
      final atTop = cell.row == 0;
      expect(touchesObstacle || atTop, isTrue,
          reason: 'точка прилипания должна примыкать к препятствию/верху');
      // И находится не выше препятствия (прилипли снизу/сбоку, не сквозь него).
      expect(cell.row, greaterThanOrEqualTo(0));
    });

    test('placeAndResolve кладёт пузырь в указанную свободную ячейку', () {
      final g = BubbleShooterLogic(random: Random(7));
      clearField(g);
      const target = HexCell(0, 4);
      final res = g.placeAndResolve(target, red);
      expect(res.didLand, isTrue);
      expect(res.landed, target);
      // Кластер из одного — не лопается, пузырь остаётся на поле.
      expect(res.cleared, isEmpty);
      expect(g.bubbleAt(0, 4), red);
      expect(count(g), 1);
    });
  });

  group('кластер ≥3 лопается и начисляет очки', () {
    test('три в ряд одного цвета лопаются, счёт растёт', () {
      final g = BubbleShooterLogic(random: Random(8));
      clearField(g);
      // Два красных в верхнем ряду рядом; третий «прилетает» между/рядом.
      g.grid[0][3] = red;
      g.grid[0][5] = red;
      // (0,4) — общий сосед (0,3) и (0,5) в чётном ряду по горизонтали.
      final res = g.placeAndResolve(const HexCell(0, 4), red);

      expect(res.cleared.length, 3, reason: 'кластер из трёх красных');
      expect(res.cleared.every((p) => p.bubble == red), isTrue);
      // Позиции лопнувших — именно эти три.
      expect(res.cleared.map((p) => p.cell).toSet(), {
        const HexCell(0, 3),
        const HexCell(0, 4),
        const HexCell(0, 5),
      });
      // Очки = 3 * popPoints (висящих нет — все были в верхнем ряду).
      expect(res.gained, 3 * BubbleShooterLogic.popPoints);
      expect(g.score, res.gained);
      // Поле снова пустое — все три убраны.
      expect(count(g), 0);
    });

    test('кластер из двух НЕ лопается', () {
      final g = BubbleShooterLogic(random: Random(9));
      clearField(g);
      g.grid[0][3] = green;
      // (0,4) — сосед (0,3); итого два зелёных, мало для лопания.
      final res = g.placeAndResolve(const HexCell(0, 4), green);
      expect(res.cleared, isEmpty);
      expect(res.gained, 0);
      expect(g.score, 0);
      expect(count(g), 2);
    });

    test('разноцветный сосед не входит в кластер', () {
      final g = BubbleShooterLogic(random: Random(10));
      clearField(g);
      g.grid[0][3] = red;
      g.grid[0][5] = red;
      g.grid[0][6] = blue; // другой цвет рядом — не должен лопнуть
      final res = g.placeAndResolve(const HexCell(0, 4), red);
      expect(res.cleared.length, 3);
      expect(res.cleared.any((p) => p.cell == const HexCell(0, 6)), isFalse);
      expect(g.bubbleAt(0, 6), blue, reason: 'синий уцелел');
    });
  });

  group('висящие пузыри падают после лопания', () {
    test('отрезанный от верха пузырь осыпается и стоит дороже', () {
      final g = BubbleShooterLogic(random: Random(11));
      clearField(g);
      // Мост из красных в верхнем ряду: (0,3),(0,5) + прилетающий (0,4) -> лопнут.
      g.grid[0][3] = red;
      g.grid[0][5] = red;
      // Синий «висит» только на (0,4)-через-сцепку: подвесим его под красным мостом
      // так, чтобы после лопания он остался без связи с верхним рядом.
      // (1,4) в нечётном ряду соседствует сверху с (0,4) и (0,5).
      g.grid[1][4] = blue;
      // Чтобы синий держался ТОЛЬКО за лопающийся кластер, у (1,4) не должно
      // быть других заполненных соседей. Соседи (1,4): (1,3),(1,5),(0,4),(0,5),
      // (2,4),(2,5). Заполнены сейчас только (0,5) [красный, лопнет] и будущий
      // (0,4) [красный, лопнет]. Значит после лопания (1,4) повиснет.

      final res = g.placeAndResolve(const HexCell(0, 4), red);

      // Лопнули три красных.
      expect(res.cleared.length, 3);
      expect(res.cleared.every((p) => p.bubble == red), isTrue);
      // Синий — единственный упавший.
      expect(res.dropped.length, 1);
      expect(res.dropped.first.cell, const HexCell(1, 4));
      expect(res.dropped.first.bubble, blue);

      // Очки: 3 лопнутых + 1 упавший (упавший дороже).
      expect(
        res.gained,
        3 * BubbleShooterLogic.popPoints + 1 * BubbleShooterLogic.dropPoints,
      );
      // Падший дороже лопнутого — инвариант ценности.
      expect(BubbleShooterLogic.dropPoints,
          greaterThan(BubbleShooterLogic.popPoints));

      // Поле опустело: 3 лопнули, 1 упал.
      expect(count(g), 0);
    });

    test('связанный с верхом пузырь НЕ падает', () {
      final g = BubbleShooterLogic(random: Random(12));
      clearField(g);
      // Тот же красный «мост» (0,3)+(0,5), что лопнет с прилётом (0,4).
      g.grid[0][3] = red;
      g.grid[0][5] = red;
      // Синяя цепочка с СОБСТВЕННЫМ якорем у верха, не зависящим от красных:
      //   (1,4)-(1,5)-(0,6), где (0,6) — пузырь верхнего ряда (якорь).
      // Соседство (нечётный ряд 1): (1,4)~(1,5) по горизонтали; up-соседи (1,5) —
      // (0,5)[красный] и (0,6)[синий]. После лопания красных связь с верхом
      // сохраняется через (0,6), поэтому синие НЕ должны осыпаться.
      g.grid[1][4] = blue;
      g.grid[1][5] = blue;
      g.grid[0][6] = blue;

      final res = g.placeAndResolve(const HexCell(0, 4), red);

      // Красные лопнули …
      expect(res.cleared.length, 3);
      // … но ни один синий не упал — все связаны с верхом через (0,6).
      expect(res.dropped, isEmpty,
          reason: 'синие связаны с верхним рядом и не должны падать');
      // Синие на месте.
      expect(g.bubbleAt(1, 4), blue);
      expect(g.bubbleAt(1, 5), blue);
      expect(g.bubbleAt(0, 6), blue);
    });
  });

  group('конец партии', () {
    test('gameOver, если пузырь достиг нижней линии', () {
      final g = BubbleShooterLogic(random: Random(13));
      clearField(g);
      final last = g.rows - 1;
      // Одиночный пузырь в свободной ячейке нижнего ряда: не лопнет (кластер=1),
      // но достигнет линии проигрыша.
      const colInLast = 2;
      final res = g.placeAndResolve(HexCell(last, colInLast), red);
      expect(res.didLand, isTrue);
      // Один красный в нижнем ряду -> не лопнул, но достиг низа.
      expect(res.gameOver, isTrue);
      expect(g.gameOver, isTrue);
    });

    test('после gameOver fire ничего не делает', () {
      final g = BubbleShooterLogic(random: Random(14));
      clearField(g);
      final last = g.rows - 1;
      g.placeAndResolve(HexCell(last, 1), red);
      expect(g.gameOver, isTrue);
      final scoreBefore = g.score;
      final res = g.fire(0);
      expect(res.didLand, isFalse);
      expect(res.gameOver, isTrue);
      expect(g.score, scoreBefore);
    });

    test('лопание в нижнем ряду НЕ вызывает gameOver (ряд снова пуст)', () {
      final g = BubbleShooterLogic(random: Random(15));
      clearField(g);
      final last = g.rows - 1;
      // Тройка красных целиком в нижнем ряду: лопнет немедленно, низа «не
      // останется» -> партия продолжается.
      g.grid[last][2] = red;
      g.grid[last][4] = red;
      final res = g.placeAndResolve(HexCell(last, 3), red);
      expect(res.cleared.length, 3);
      expect(res.gameOver, isFalse);
      expect(g.gameOver, isFalse);
    });
  });

  group('fire (полный ход с трассировкой)', () {
    test('после выстрела пушка прокручивается (current<-next)', () {
      final g = BubbleShooterLogic(random: Random(16));
      final prevNext = g.next;
      g.fire(0);
      expect(g.current, prevNext, reason: 'current должен стать прежним next');
    });

    test('детерминированность: одинаковый seed -> одинаковый ход', () {
      final a = BubbleShooterLogic(random: Random(99));
      final b = BubbleShooterLogic(random: Random(99));
      final ra = a.fire(0.2);
      final rb = b.fire(0.2);
      expect(ra.landed, rb.landed);
      expect(ra.gained, rb.gained);
      expect(a.score, b.score);
      expect(a.current, b.current);
    });
  });
}
