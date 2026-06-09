import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/lights_out/components/lights_out_logic.dart';

/// Клетки «креста» (центр + ортогональные соседи) вокруг (cx, cy),
/// обрезанные по полю стороной [size].
Set<Point<int>> _crossCells(int size, int cx, int cy) {
  const deltas = [
    Point(0, 0),
    Point(1, 0),
    Point(-1, 0),
    Point(0, 1),
    Point(0, -1),
  ];
  final out = <Point<int>>{};
  for (final d in deltas) {
    final x = cx + d.x;
    final y = cy + d.y;
    if (x >= 0 && y >= 0 && x < size && y < size) out.add(Point(x, y));
  }
  return out;
}

/// Снимок поля (копия), чтобы сравнивать состояния до/после хода.
List<List<bool>> _snapshot(LightsOutLogic g) => [
      for (var y = 0; y < g.size; y++)
        [for (var x = 0; x < g.size; x++) g.isOn(x, y)],
    ];

void main() {
  group('LightsOutLogic — генерация старта', () {
    test('после reset поле не all-off, ходов 0, не выиграно', () {
      // Устойчиво по многим зёрнам: старт обязан быть непустым.
      for (var seed = 0; seed < 40; seed++) {
        final g = LightsOutLogic(random: Random(seed));
        expect(g.won, isFalse, reason: 'seed=$seed');
        expect(g.moves, 0, reason: 'seed=$seed');
        expect(g.litCount, greaterThan(0),
            reason: 'seed=$seed: старт не должен быть пустым');
      }
    });

    test('геометрия поля квадратная size×size', () {
      final g = LightsOutLogic(size: 5, random: Random(1));
      expect(g.grid.length, 5);
      expect(g.grid.every((row) => row.length == 5), isTrue);
    });

    test('одинаковое зерно даёт идентичный стартовый узор', () {
      final a = LightsOutLogic(random: Random(42));
      final b = LightsOutLogic(random: Random(42));
      expect(_snapshot(a), _snapshot(b));
    });
  });

  group('LightsOutLogic — тап инвертирует крест', () {
    test('центр поля: переключаются ровно 5 клеток (центр + 4 соседа)', () {
      final g = LightsOutLogic(random: Random(3));
      const cx = 2, cy = 2;
      final before = _snapshot(g);
      final expected = _crossCells(g.size, cx, cy);

      final res = g.tap(cx, cy);
      expect(res.applied, isTrue);
      expect(res.affected, 5);
      expect(res.toggled.map((t) => Point(t.x, t.y)).toSet(), expected);

      // Ровно клетки креста инвертированы, остальные не тронуты.
      for (var y = 0; y < g.size; y++) {
        for (var x = 0; x < g.size; x++) {
          final flipped = expected.contains(Point(x, y));
          expect(g.isOn(x, y), flipped ? !before[y][x] : before[y][x],
              reason: 'клетка ($x,$y)');
        }
      }
      // Новое состояние в исходе совпадает с полем.
      for (final t in res.toggled) {
        expect(t.on, g.isOn(t.x, t.y));
      }
    });

    test('угол: крест обрезан до 3 клеток', () {
      final g = LightsOutLogic(random: Random(4));
      final res = g.tap(0, 0);
      expect(res.affected, 3);
      expect(res.toggled.map((t) => Point(t.x, t.y)).toSet(),
          _crossCells(g.size, 0, 0));
    });

    test('край (не угол): крест обрезан до 4 клеток', () {
      final g = LightsOutLogic(random: Random(5));
      final res = g.tap(2, 0); // верхний край
      expect(res.affected, 4);
      expect(res.toggled.map((t) => Point(t.x, t.y)).toSet(),
          _crossCells(g.size, 2, 0));
    });

    test('счётчик ходов растёт на каждом валидном тапе', () {
      final g = LightsOutLogic(random: Random(6));
      expect(g.moves, 0);
      g.tap(0, 0);
      expect(g.moves, 1);
      g.tap(1, 1);
      expect(g.moves, 2);
    });

    test('тап вне поля — пустой исход, ход не засчитан', () {
      final g = LightsOutLogic(random: Random(7));
      final res = g.tap(-1, 99);
      expect(res.applied, isFalse);
      expect(res.affected, 0);
      expect(res.won, isFalse);
      expect(g.moves, 0);
    });

    test('двойной тап по одной клетке возвращает поле в исходное', () {
      final g = LightsOutLogic(random: Random(8));
      final before = _snapshot(g);
      g.tap(2, 2);
      g.tap(2, 2);
      expect(_snapshot(g), before, reason: 'крест самоинверсен');
    });
  });

  group('LightsOutLogic — решаемость и победа', () {
    test('воспроизведение скрэмбла генератора гасит сгенерированное поле', () {
      // Генератор строит поле из погашенного, применяя scramble случайных
      // крестов через инъектированный Random; если узор схлопнулся в пустой —
      // повторяет проход (do/while). Воспроизведём ЭТУ ЖЕ процедуру тем же
      // зерном, восстановим точный мультимножество центров, сведём к чётности
      // (двойной тап клетки — no-op) и применим его к полю.
      //
      // Важно: победный флаг защёлкивается ТОЛЬКО при litCount==0 и замораживает
      // поле, поэтому он не может увести поле прочь от нуля. Значит, применив
      // точный инверс набор, мы гарантированно приходим к litCount==0 вне
      // зависимости от того, на каком тапе защёлкнулась победа.
      const size = 5;
      const scramble = 6;
      for (var seed = 0; seed < 40; seed++) {
        // Точное воспроизведение генератора: считаем чётность нажатий по клеткам.
        final trace = Random(seed);
        late List<List<int>> parity;
        late List<List<int>> centerParity;
        do {
          parity = List.generate(size, (_) => List.filled(size, 0));
          centerParity = List.generate(size, (_) => List.filled(size, 0));
          var lit = 0; // имитируем litCount поля по ходу скрэмбла
          for (var i = 0; i < scramble; i++) {
            final cx = trace.nextInt(size);
            final cy = trace.nextInt(size);
            centerParity[cy][cx] ^= 1; // чётность нажатий ЦЕНТРА (для решения)
            for (final p in _crossCells(size, cx, cy)) {
              parity[p.y][p.x] ^= 1;
            }
          }
          for (final row in parity) {
            for (final v in row) {
              lit += v;
            }
          }
          if (lit != 0) break; // непустой узор — генератор принял его
        } while (true);

        final g = LightsOutLogic(
          size: size,
          scramble: scramble,
          random: Random(seed),
        );
        // Поле логики должно совпасть с воспроизведённым узором.
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            expect(g.isOn(x, y), parity[y][x] == 1,
                reason: 'seed=$seed: расхождение узора в ($x,$y)');
          }
        }
        // Решение Lights Out: нажать те же ЦЕНТРЫ с нечётной чётностью
        // (повторное нажатие креста — involution) — поле гарантированно гаснет.
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            if (centerParity[y][x] == 1) g.tap(x, y);
          }
        }
        expect(g.litCount, 0,
            reason: 'seed=$seed: поле решаемо и погашено инверсом');
        expect(g.won, isTrue, reason: 'seed=$seed');
      }
    });

    test('явный сценарий: один скрэмбл-тап гасится повтором этого тапа', () {
      // scramble=1 → генератор делает ровно один крест из погашенного поля,
      // значит поле = крест вокруг некоторой клетки. Повтор ЛЮБОГО одиночного
      // тапа, совпавшего с тем же центром, гасит всё. Найдём центр перебором.
      final g = LightsOutLogic(size: 5, scramble: 1, random: Random(11));
      expect(g.litCount, greaterThan(0));

      // Центр — единственная клетка, у которой ВЕСЬ её крест горит.
      Point<int>? center;
      for (var y = 0; y < g.size && center == null; y++) {
        for (var x = 0; x < g.size; x++) {
          final cross = _crossCells(g.size, x, y);
          if (cross.every((p) => g.isOn(p.x, p.y))) {
            center = Point(x, y);
            break;
          }
        }
      }
      expect(center, isNotNull, reason: 'крест единственного тапа должен гореть');

      final res = g.tap(center!.x, center.y);
      expect(res.won, isTrue);
      expect(g.won, isTrue);
      expect(g.litCount, 0);
    });

    test('победа достигается при all-off и фиксируется в исходе', () {
      final g = LightsOutLogic(size: 5, scramble: 1, random: Random(2));
      Point<int>? center;
      for (var y = 0; y < g.size && center == null; y++) {
        for (var x = 0; x < g.size; x++) {
          if (_crossCells(g.size, x, y).every((p) => g.isOn(p.x, p.y))) {
            center = Point(x, y);
            break;
          }
        }
      }
      final res = g.tap(center!.x, center.y);
      expect(res.won, isTrue);
      expect(res.applied, isTrue);
    });

    test('после победы тап игнорируется (пустой исход, ходы не растут)', () {
      final g = LightsOutLogic(size: 5, scramble: 1, random: Random(13));
      Point<int>? center;
      for (var y = 0; y < g.size && center == null; y++) {
        for (var x = 0; x < g.size; x++) {
          if (_crossCells(g.size, x, y).every((p) => g.isOn(p.x, p.y))) {
            center = Point(x, y);
            break;
          }
        }
      }
      g.tap(center!.x, center.y);
      expect(g.won, isTrue);
      final movesAtWin = g.moves;

      final after = g.tap(0, 0);
      expect(after.applied, isFalse);
      expect(after.affected, 0);
      expect(g.moves, movesAtWin, reason: 'после победы ходы не засчитываются');
    });
  });

  group('LightsOutLogic — reset', () {
    test('reset обнуляет ходы и снимает победу, генерирует новый пазл', () {
      final g = LightsOutLogic(size: 5, scramble: 1, random: Random(3));
      Point<int>? center;
      for (var y = 0; y < g.size && center == null; y++) {
        for (var x = 0; x < g.size; x++) {
          if (_crossCells(g.size, x, y).every((p) => g.isOn(p.x, p.y))) {
            center = Point(x, y);
            break;
          }
        }
      }
      g.tap(center!.x, center.y);
      expect(g.won, isTrue);

      g.reset();
      expect(g.won, isFalse);
      expect(g.moves, 0);
      expect(g.litCount, greaterThan(0));
    });
  });
}
