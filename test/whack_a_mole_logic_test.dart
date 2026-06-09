import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/whack_a_mole/components/whack_a_mole_logic.dart';

/// Индекс первой норы, где сейчас «вылезший» крот, или -1.
int _firstUp(WhackAMoleLogic g) {
  for (var i = 0; i < g.count; i++) {
    if (g.holes[i].up) return i;
  }
  return -1;
}

/// Прогонять [tick] по [dt], пока не появится хотя бы один крот, и вернуть его
/// индекс. Ограничено числом шагов, чтобы тест не зависал при регрессе.
int _tickUntilMole(WhackAMoleLogic g, {double dt = 0.1, int maxSteps = 200}) {
  for (var i = 0; i < maxSteps; i++) {
    g.tick(dt);
    final up = _firstUp(g);
    if (up >= 0) return up;
  }
  return -1;
}

void main() {
  group('старт / reset', () {
    test('после reset все норы пусты, счётчики на нуле', () {
      final g = WhackAMoleLogic(random: Random(1));
      expect(g.count, 9, reason: 'сетка 3×3');
      expect(g.combo, 0);
      expect(g.hits, 0);
      expect(g.misses, 0);
      expect(g.elapsed, 0);
      expect(g.moleCount, 0);
      for (final h in g.holes) {
        expect(h.up, isFalse);
      }
    });

    test('reset возвращает игру в исходное состояние', () {
      final g = WhackAMoleLogic(random: Random(2));
      _tickUntilMole(g);
      g.hit(_firstUp(g));
      expect(g.hits, greaterThan(0));

      g.reset();
      expect(g.combo, 0);
      expect(g.hits, 0);
      expect(g.misses, 0);
      expect(g.elapsed, 0);
      expect(g.moleCount, 0);
    });
  });

  group('hit', () {
    test('удар по вылезшему кроту — попадание: очки и крот прячется', () {
      final g = WhackAMoleLogic(random: Random(3));
      final i = _tickUntilMole(g);
      expect(i, greaterThanOrEqualTo(0), reason: 'крот должен был вылезти');
      expect(g.holes[i].up, isTrue);

      final res = g.hit(i);
      expect(res.hit, isTrue);
      expect(res.ignored, isFalse);
      expect(res.index, i);
      expect(res.gained, WhackAMoleLogic.basePoints, reason: 'первое попадание ×комбо 1');
      expect(res.combo, 1);
      expect(g.hits, 1);
      // Крот спрятался после удара.
      expect(g.holes[i].up, isFalse);
    });

    test('удар по пустой норе — промах: комбо сбрасывается, очков нет', () {
      final g = WhackAMoleLogic(random: Random(4));
      // Наберём комбо двумя попаданиями.
      var i = _tickUntilMole(g);
      g.hit(i);
      i = _tickUntilMole(g);
      g.hit(i);
      expect(g.combo, 2);

      // Найдём гарантированно пустую нору и ударим по ней.
      final empty = List.generate(g.count, (k) => k).firstWhere(
            (k) => !g.holes[k].up,
          );
      final res = g.hit(empty);
      expect(res.hit, isFalse);
      expect(res.ignored, isFalse);
      expect(res.gained, 0);
      expect(res.combo, 0);
      expect(g.combo, 0, reason: 'промах ломает серию');
    });

    test('комбо растёт по серии попаданий и множит очки', () {
      final g = WhackAMoleLogic(random: Random(5));
      final gains = <int>[];
      for (var n = 0; n < 4; n++) {
        final i = _tickUntilMole(g);
        final res = g.hit(i);
        expect(res.hit, isTrue);
        gains.add(res.gained);
        expect(res.combo, n + 1);
      }
      // Очки = base × комбо: 10, 20, 30, 40.
      expect(gains, [10, 20, 30, 40]);
      expect(g.hits, 4);
    });

    test('удар вне поля — игнор, состояние не меняется', () {
      final g = WhackAMoleLogic(random: Random(6));
      _tickUntilMole(g);
      g.hit(_firstUp(g)); // комбо 1
      expect(g.combo, 1);

      final res = g.hit(-1);
      expect(res.ignored, isTrue);
      expect(res.hit, isFalse);
      expect(g.combo, 1, reason: 'игнор не трогает комбо');

      final res2 = g.hit(g.count); // за верхней границей
      expect(res2.ignored, isTrue);
    });
  });

  group('tick / спавн', () {
    test('спавн детерминирован по Random: одно зерно — один путь', () {
      final a = WhackAMoleLogic(random: Random(42));
      final b = WhackAMoleLogic(random: Random(42));
      for (var step = 0; step < 50; step++) {
        final ea = a.tick(0.1);
        final eb = b.tick(0.1);
        expect(ea.map((e) => '${e.index}:${e.change}').toList(),
            eb.map((e) => '${e.index}:${e.change}').toList(),
            reason: 'расхождение событий на шаге $step');
        for (var i = 0; i < a.count; i++) {
          expect(a.holes[i].up, b.holes[i].up,
              reason: 'нора $i разошлась на шаге $step');
        }
      }
    });

    test('разные зёрна дают разные первые позиции (выборка не вырождена)', () {
      final seen = <int>{};
      for (var seed = 0; seed < 20; seed++) {
        final g = WhackAMoleLogic(random: Random(seed));
        final i = _tickUntilMole(g);
        if (i >= 0) seen.add(i);
      }
      expect(seen.length, greaterThan(1),
          reason: 'спавн должен покрывать разные норы');
    });

    test('tick возвращает событие popUp с валидным индексом норы', () {
      final g = WhackAMoleLogic(random: Random(7));
      List<HoleEvent> events = const [];
      for (var step = 0; step < 50 && events.isEmpty; step++) {
        events = g.tick(0.1);
      }
      expect(events, isNotEmpty);
      final pop = events.firstWhere((e) => e.change == HoleChange.popUp);
      expect(pop.index, inInclusiveRange(0, g.count - 1));
      expect(g.holes[pop.index].up, isTrue);
    });

    test('крот сам прячется по истечении времени → событие hide и сброс комбо', () {
      final g = WhackAMoleLogic(random: Random(8));
      final i = _tickUntilMole(g);
      expect(g.holes[i].up, isTrue);
      // Поднимем комбо отдельным попаданием по этому кроту нельзя (он спрячется),
      // поэтому проверяем именно зевок: ждём, пока крот уйдёт сам.
      // upTime ~1.15с; крупный шаг гарантированно его прячет.
      var hid = false;
      for (var step = 0; step < 40 && !hid; step++) {
        final events = g.tick(0.1);
        if (events.any((e) => e.index == i && e.change == HoleChange.hide)) {
          hid = true;
        }
      }
      expect(hid, isTrue, reason: 'крот должен спрятаться сам');
      expect(g.holes[i].up, isFalse);
      expect(g.misses, greaterThanOrEqualTo(1));
      expect(g.combo, 0, reason: 'зевок сбрасывает комбо');
    });

    test('tick(0) ничего не меняет', () {
      final g = WhackAMoleLogic(random: Random(9));
      final before = g.elapsed;
      final events = g.tick(0);
      expect(events, isEmpty);
      expect(g.elapsed, before);
      expect(g.moleCount, 0);
    });

    test('спавн не превышает число нор', () {
      final g = WhackAMoleLogic(random: Random(10));
      for (var step = 0; step < 200; step++) {
        g.tick(0.1);
        expect(g.moleCount, lessThanOrEqualTo(g.count));
      }
    });
  });

  group('темп', () {
    test('интервал спавна сокращается с ростом elapsed', () {
      final g = WhackAMoleLogic(random: Random(11));
      final startInterval = g.spawnInterval;
      // Прокрутим время вперёд (попутно сбивая кротов, чтобы поле не забилось).
      for (var step = 0; step < 250; step++) {
        g.tick(0.1);
        final up = _firstUp(g);
        if (up >= 0) g.hit(up);
      }
      expect(g.elapsed, greaterThan(20));
      expect(g.spawnInterval, lessThan(startInterval),
          reason: 'темп должен расти (интервал падать)');
    });
  });
}
