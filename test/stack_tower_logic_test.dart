import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/stack_tower/components/stack_tower_logic.dart';

void main() {
  // Детерминированные параметры поля: основание [20,80], центр 50, ширина 60.
  StackTowerLogic make() => StackTowerLogic(random: Random(7));

  group('StackTowerLogic — старт', () {
    test('основание по центру, ширина = baseWidth, не мертва, счёт 0', () {
      final g = make();
      expect(g.tower.length, 1);
      expect(g.height, 0);
      expect(g.dead, isFalse);
      expect(g.top.width, 60);
      expect(g.top.left, 20); // (100 - 60) / 2
      expect(g.top.center, 50);
      expect(g.currentWidth, 60);
      expect(g.perfectStreak, 0);
    });

    test('движущийся блок входит с края поля в пределах границ', () {
      final g = make();
      expect(g.currentLeft, greaterThanOrEqualTo(0));
      expect(g.currentRight, lessThanOrEqualTo(g.fieldWidth + 1e-9));
      expect(g.currentDir.abs(), 1);
    });
  });

  group('StackTowerLogic — обычная укладка и обрезка', () {
    test('свес справа: блок = перекрытие, отрезано справа', () {
      final g = make();
      final out = g.dropAt(30); // moving [30,90] над [20,80]
      expect(out.result, DropResult.placed);
      expect(out.overlap, 50); // [30,80]
      expect(out.placedLeft, 30);
      expect(out.placedWidth, 50);
      expect(out.cutSide, CutSide.right);
      expect(out.cutWidth, 10); // 60 - 50
      expect(out.cutLeft, 80); // правее перекрытия
      // Башня выросла, новый верх сузился, серия сброшена.
      expect(g.height, 1);
      expect(g.top.left, 30);
      expect(g.top.width, 50);
      expect(g.currentWidth, 50);
      expect(g.perfectStreak, 0);
    });

    test('свес слева: блок = перекрытие, отрезано слева', () {
      final g = make();
      final out = g.dropAt(10); // moving [10,70] над [20,80]
      expect(out.result, DropResult.placed);
      expect(out.overlap, 50); // [20,70]
      expect(out.placedLeft, 20);
      expect(out.placedWidth, 50);
      expect(out.cutSide, CutSide.left);
      expect(out.cutWidth, 10);
      expect(out.cutLeft, 10);
      expect(g.top.left, 20);
      expect(g.top.width, 50);
    });

    test('последовательная обрезка только сужает башню', () {
      final g = make();
      g.dropAt(30); // ширина -> 50, верх [30,80]
      final w1 = g.currentWidth;
      final out2 = g.dropAt(45); // moving [45,95] над [30,80] -> overlap [45,80]=35
      expect(out2.result, DropResult.placed);
      expect(out2.overlap, 35);
      expect(g.currentWidth, lessThan(w1));
      expect(g.currentWidth, 35);
    });
  });

  group('StackTowerLogic — идеальная установка', () {
    test('в пределах допуска: perfect, серия растёт, блок расширяется', () {
      final g = make();
      final out = g.dropAt(20); // центр moving = 50 == центр опоры
      expect(out.result, DropResult.perfect);
      expect(out.isPerfect, isTrue);
      expect(out.cutWidth, 0);
      expect(out.perfectStreak, 1);
      // Лёгкое расширение (+perfectBonus), центрировано на опоре.
      expect(g.top.width, closeTo(61.6, 1e-9));
      expect(g.top.center, closeTo(50, 1e-9));
      expect(g.currentWidth, closeTo(61.6, 1e-9));
    });

    test('малое смещение в пределах допуска тоже идеал', () {
      final g = make();
      // tolerance 1.2: смещение центра на 1.0 (left=21) ещё идеал.
      final out = g.dropAt(21);
      expect(out.result, DropResult.perfect);
      expect(out.perfectStreak, 1);
    });

    test('за пределами допуска — обычная укладка, не идеал', () {
      final g = make();
      final out = g.dropAt(23); // смещение центра 3.0 > 1.2
      expect(out.result, DropResult.placed);
      expect(out.perfectStreak, 0);
    });

    test('серия идеалов копится и сбрасывается обычной укладкой', () {
      final g = make();
      expect(g.dropAt(g.top.left).perfectStreak, 1);
      expect(g.dropAt(g.top.left).perfectStreak, 2);
      expect(g.dropAt(g.top.left).perfectStreak, 3);
      // Сильное смещение прерывает серию.
      final broke = g.dropAt(g.top.left + 10);
      expect(broke.result, DropResult.placed);
      expect(broke.perfectStreak, 0);
      expect(g.perfectStreak, 0);
    });

    test('расширение не выводит блок за пределы поля', () {
      final g = make();
      // Многократные идеалы подряд: ширина растёт, но не превышает fieldWidth,
      // и блок остаётся внутри [0, fieldWidth].
      for (var i = 0; i < 40; i++) {
        final out = g.dropAt(g.top.left);
        expect(out.result, DropResult.perfect);
      }
      expect(g.top.width, lessThanOrEqualTo(g.fieldWidth));
      expect(g.top.left, greaterThanOrEqualTo(0));
      expect(g.top.right, lessThanOrEqualTo(g.fieldWidth + 1e-9));
    });
  });

  group('StackTowerLogic — обвал', () {
    test('нулевое перекрытие завершает игру', () {
      final g = make();
      final out = g.dropAt(85); // moving [85,145] не пересекает [20,80]
      expect(out.result, DropResult.gameOver);
      expect(out.isGameOver, isTrue);
      expect(out.overlap, 0);
      expect(g.dead, isTrue);
      // Башня не выросла.
      expect(g.height, 0);
    });

    test('касание край-в-край (overlap 0) — тоже обвал', () {
      final g = make();
      // moving начинается ровно на правом крае опоры: [80,140] -> overlap <= 0.
      final out = g.dropAt(80);
      expect(out.result, DropResult.gameOver);
      expect(g.dead, isTrue);
    });

    test('после обвала повторный drop безопасен и остаётся gameOver', () {
      final g = make();
      g.dropAt(85);
      final again = g.drop();
      expect(again.result, DropResult.gameOver);
      expect(g.dead, isTrue);
    });

    test('reset воскрешает игру в исходное состояние', () {
      final g = make();
      g.dropAt(85);
      expect(g.dead, isTrue);
      g.reset();
      expect(g.dead, isFalse);
      expect(g.height, 0);
      expect(g.top.width, 60);
    });
  });

  group('StackTowerLogic — движение и скорость', () {
    test('advance держит блок в пределах поля и отскакивает', () {
      final g = StackTowerLogic(random: Random(1));
      for (var i = 0; i < 200; i++) {
        g.advance(0.05);
        expect(g.currentLeft, greaterThanOrEqualTo(-1e-9));
        expect(g.currentRight, lessThanOrEqualTo(g.fieldWidth + 1e-9));
      }
    });

    test('очень большой dt не выбрасывает блок за поле (мульти-отскок)', () {
      final g = StackTowerLogic(random: Random(2));
      g.advance(100); // много отражений за один шаг
      expect(g.currentLeft, greaterThanOrEqualTo(-1e-9));
      expect(g.currentRight, lessThanOrEqualTo(g.fieldWidth + 1e-9));
    });

    test('скорость растёт с высотой башни', () {
      final g = make();
      final v0 = g.currentSpeed;
      g.dropAt(g.top.left); // идеал, высота +1
      expect(g.currentSpeed, greaterThan(v0));
    });

    test('мёртвый блок не двигается', () {
      final g = make();
      g.dropAt(85);
      final left = g.currentLeft;
      g.advance(1);
      expect(g.currentLeft, left);
    });
  });
}
