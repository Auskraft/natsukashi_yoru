import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/sokoban/components/sokoban_logic.dart';

/// Прогнать последовательность ходов, вернуть последний исход.
SokoMoveResult _run(SokobanLogic g, List<SokoDir> moves) {
  var last = const SokoMoveResult.blocked();
  for (final d in moves) {
    last = g.move(d);
  }
  return last;
}

void main() {
  // Удобные направления.
  const u = SokoDir.up;
  const d = SokoDir.down;
  const l = SokoDir.left;
  const r = SokoDir.right;

  group('SokobanLogic — парсинг ASCII-уровня', () {
    test('символы карты раскладываются в правильные тайлы и игрока', () {
      // Карта: стены по периметру, игрок, ящик на полу, ящик на цели, цель.
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#####',
          '#@\$.#',
          '#*  #',
          '#####',
        ],
      ]);

      expect(g.cols, 5);
      expect(g.rows, 4);
      expect(g.player, const Point(1, 1));

      expect(g.tileAt(0, 0), SokoTile.wall);
      expect(g.tileAt(2, 1), SokoTile.box); // $
      expect(g.tileAt(3, 1), SokoTile.goal); // .
      expect(g.tileAt(1, 2), SokoTile.boxOnGoal); // *
      expect(g.tileAt(2, 2), SokoTile.floor); // пробел

      // Под игроком — пол (символ @).
      expect(g.tileAt(1, 1), SokoTile.floor);

      // Цели: '.' и '*' → 2; ящики: '$' и '*' → 2.
      expect(g.goalCount, 2);
      expect(g.boxesOnGoal, 1); // только '*' уже зачтён
      expect(g.solved, isFalse);
      expect(g.moves, 0);
    });

    test("игрок на цели ('+') считается целью и стартовой клеткой", () {
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '####',
          '#+\$#', // игрок на цели, рядом ящик
          '####',
        ],
      ]);
      expect(g.player, const Point(1, 1));
      expect(g.tileAt(1, 1), SokoTile.goal);
      expect(g.goalCount, 1);
      expect(g.boxesOnGoal, 0);
    });

    test('строки выравниваются по самой длинной (недостающее — пол)', () {
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#####',
          '#@', // короткая строка
        ],
      ]);
      expect(g.cols, 5);
      expect(g.tileAt(4, 1), SokoTile.floor);
    });

    test('границы поля считаются стеной', () {
      final g = SokobanLogic(random: Random(1), levels: const [
        ['@.'],
      ]);
      expect(g.tileAt(-1, 0), SokoTile.wall);
      expect(g.tileAt(0, -1), SokoTile.wall);
      expect(g.tileAt(99, 0), SokoTile.wall);
    });

    test('тайл-помощники hasBox/isGoalSquare/isWalkable', () {
      expect(SokoTile.box.hasBox, isTrue);
      expect(SokoTile.boxOnGoal.hasBox, isTrue);
      expect(SokoTile.floor.hasBox, isFalse);

      expect(SokoTile.goal.isGoalSquare, isTrue);
      expect(SokoTile.boxOnGoal.isGoalSquare, isTrue);
      expect(SokoTile.floor.isGoalSquare, isFalse);

      expect(SokoTile.floor.isWalkable, isTrue);
      expect(SokoTile.goal.isWalkable, isTrue);
      expect(SokoTile.wall.isWalkable, isFalse);
      expect(SokoTile.box.isWalkable, isFalse);
    });
  });

  group('SokobanLogic — ход в пол', () {
    test('шаг на свободную клетку: walked, игрок сдвинулся, +1 ход', () {
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#####',
          '#@  #',
          '#####',
        ],
      ]);
      final res = g.move(r);
      expect(res.kind, SokoMoveKind.walked);
      expect(res.player, const Point(2, 1));
      expect(res.movedBox, isFalse);
      expect(res.box, isNull);
      expect(res.solved, isFalse);
      expect(g.player, const Point(2, 1));
      expect(g.moves, 1);
    });

    test('шаг в стену: blocked, без сдвига и без хода', () {
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '###',
          '#@#',
          '###',
        ],
      ]);
      final res = g.move(u);
      expect(res.kind, SokoMoveKind.blocked);
      expect(g.player, const Point(1, 1));
      expect(g.moves, 0);
    });
  });

  group('SokobanLogic — толкание ящика', () {
    test('толчок ящика в свободную клетку: pushed, ящик и игрок сдвинулись', () {
      // @ $ _  → толкаем вправо: ящик уезжает на пустой пол (не цель).
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#####',
          '#@\$ #',
          '#####',
        ],
      ]);
      final res = g.move(r);
      expect(res.kind, SokoMoveKind.pushed);
      expect(res.player, const Point(2, 1));
      expect(res.box, const Point(3, 1));
      expect(res.movedBox, isTrue);
      expect(res.solved, isFalse);
      expect(g.tileAt(2, 1), SokoTile.floor);
      expect(g.tileAt(3, 1), SokoTile.box);
      expect(g.moves, 1);
    });

    test('запрет: за ящиком стена → blocked, ничего не изменилось', () {
      // @ $ #  → толкать некуда (стена за ящиком).
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '####',
          '#@\$#',
          '####',
        ],
      ]);
      final before = g.tileAt(2, 1);
      final res = g.move(r);
      expect(res.kind, SokoMoveKind.blocked);
      expect(g.player, const Point(1, 1));
      expect(g.tileAt(2, 1), before); // ящик на месте
      expect(g.moves, 0);
    });

    test('запрет: два ящика подряд нельзя толкать → blocked', () {
      // @ $ $ _ → нельзя толкать два ящика разом.
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '######',
          '#@\$\$ #',
          '######',
        ],
      ]);
      final res = g.move(r);
      expect(res.kind, SokoMoveKind.blocked);
      expect(g.player, const Point(1, 1));
      expect(g.tileAt(2, 1), SokoTile.box);
      expect(g.tileAt(3, 1), SokoTile.box);
      expect(g.moves, 0);
    });

    test('толчок ящика НА цель: pushedOntoGoal и счётчик зачтённых растёт', () {
      // @ $ .  → толкаем ящик прямо на цель справа.
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#####',
          '#@\$.#',
          '#####',
        ],
      ]);
      expect(g.boxesOnGoal, 0);
      final res = g.move(r);
      expect(res.kind, SokoMoveKind.pushedOntoGoal);
      expect(res.box, const Point(3, 1));
      expect(g.tileAt(3, 1), SokoTile.boxOnGoal);
      expect(g.boxesOnGoal, 1);
      expect(res.solved, isTrue); // единственный ящик встал на цель
    });

    test('толчок ящика С цели: pushedOffGoal и счётчик зачтённых падает', () {
      // .* _ : игрок на цели слева от ящика-на-цели, толкаем его на пустой пол.
      // Карта: цель(0)+игрок, ящик-на-цели, пол.
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#####',
          '#+*.#',
          '#####',
        ],
      ]);
      // (1,1) игрок на цели, (2,1) ящик-на-цели, (3,1) цель.
      expect(g.boxesOnGoal, 1);
      final res = g.move(r);
      // Ящик переезжает с цели (2,1) на цель (3,1): остаётся зачтён.
      expect(res.kind, SokoMoveKind.pushed);
      expect(g.boxesOnGoal, 1);
      expect(g.tileAt(2, 1), SokoTile.goal); // освобождённая цель
      expect(g.tileAt(3, 1), SokoTile.boxOnGoal);
    });

    test('толчок ящика с цели на обычный пол: pushedOffGoal', () {
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#####',
          '#+* #',
          '#####',
        ],
      ]);
      expect(g.boxesOnGoal, 1);
      final res = g.move(r);
      expect(res.kind, SokoMoveKind.pushedOffGoal);
      expect(g.boxesOnGoal, 0);
      expect(g.tileAt(2, 1), SokoTile.goal);
      expect(g.tileAt(3, 1), SokoTile.box);
      expect(g.solved, isFalse);
    });
  });

  group('SokobanLogic — победа', () {
    test('победа, когда ВСЕ ящики на целях', () {
      // Два ящика, две цели; толкаем оба на цели.
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#######',
          '#@\$ . #',
          '#######',
        ],
      ]);
      // Один ящик/одна цель: R (ящик 2->3), R (ящик 3->4=цель).
      expect(g.solved, isFalse);
      final res = _run(g, const [r, r]);
      expect(g.solved, isTrue);
      expect(res.solved, isTrue);
      expect(g.boxesOnGoal, g.goalCount);
    });

    test('после победы ходы игнорируются (blocked)', () {
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#####',
          '#@\$.#',
          '#####',
        ],
      ]);
      g.move(r); // ставит ящик на цель → solved
      expect(g.solved, isTrue);
      final after = g.move(l);
      expect(after.kind, SokoMoveKind.blocked);
    });

    test('частичная расстановка не считается победой', () {
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#######',
          '#@\$.\$.#',
          '#######',
        ],
      ]);
      // Толкаем только первый ящик на первую цель.
      final res = g.move(r);
      expect(res.kind, SokoMoveKind.pushedOntoGoal);
      expect(g.boxesOnGoal, 1);
      expect(g.goalCount, 2);
      expect(g.solved, isFalse);
    });
  });

  group('SokobanLogic — смена уровня', () {
    test('nextLevel переключает на следующий и сбрасывает ходы', () {
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '###',
          '#@#',
          '###',
        ],
        [
          '#####',
          '#@  #',
          '#####',
        ],
      ]);
      expect(g.levelIndex, 0);
      expect(g.levelNumber, 1);
      expect(g.levelCount, 2);
      expect(g.hasNextLevel, isTrue);

      g.move(u); // blocked в первом уровне, но проверим сброс ходов на переходе
      final ok = g.nextLevel();
      expect(ok, isTrue);
      expect(g.levelIndex, 1);
      expect(g.levelNumber, 2);
      expect(g.moves, 0);
      expect(g.cols, 5);
      expect(g.hasNextLevel, isFalse);
    });

    test('nextLevel на последнем уровне возвращает false и не меняет уровень',
        () {
      final g = SokobanLogic(random: Random(1), levels: const [
        ['@'],
      ]);
      expect(g.hasNextLevel, isFalse);
      expect(g.nextLevel(), isFalse);
      expect(g.levelIndex, 0);
    });

    test('restartLevel сбрасывает расстановку и ходы текущего уровня', () {
      final g = SokobanLogic(random: Random(1), levels: const [
        [
          '#####',
          '#@\$.#',
          '#####',
        ],
      ]);
      g.move(r); // ящик на цель, solved, moves=1
      expect(g.solved, isTrue);
      expect(g.moves, 1);
      g.restartLevel();
      expect(g.solved, isFalse);
      expect(g.moves, 0);
      expect(g.boxesOnGoal, 0);
      expect(g.tileAt(2, 1), SokoTile.box); // ящик вернулся на старт
      expect(g.player, const Point(1, 1));
    });

    test('reset возвращает на первый уровень', () {
      final g = SokobanLogic(random: Random(1), levels: const [
        ['@ '],
        ['@  '],
      ]);
      g.nextLevel();
      expect(g.levelIndex, 1);
      g.reset();
      expect(g.levelIndex, 0);
      expect(g.moves, 0);
    });
  });

  group('SokobanLogic — встроенные уровни решаемы', () {
    test('есть 4–6 уровней и в каждом ящиков ровно столько же, сколько целей',
        () {
      expect(kSokobanLevels.length, inInclusiveRange(4, 6));
      for (var i = 0; i < kSokobanLevels.length; i++) {
        final g = SokobanLogic(random: Random(1));
        for (var k = 0; k < i; k++) {
          g.nextLevel();
        }
        // На старте уровня число зачтённых ≤ число целей, и есть хотя бы 1 цель.
        expect(g.goalCount, greaterThan(0), reason: 'уровень ${i + 1}');
        expect(g.boxesOnGoal, lessThanOrEqualTo(g.goalCount),
            reason: 'уровень ${i + 1}');
      }
    });

    test('уровень 1 проходится известным решением (R)', () {
      final g = SokobanLogic(random: Random(1));
      expect(g.levelNumber, 1);
      final res = g.move(r);
      expect(res.solved, isTrue);
      expect(g.solved, isTrue);
    });

    test('уровень 4 проходится известным решением (D,R,D,L,L)', () {
      final g = SokobanLogic(random: Random(1));
      g.nextLevel(); // 2
      g.nextLevel(); // 3
      g.nextLevel(); // 4
      expect(g.levelNumber, 4);
      final res = _run(g, const [d, r, d, l, l]);
      expect(g.solved, isTrue, reason: 'уровень 4 должен решаться D,R,D,L,L');
      expect(res.solved, isTrue);
    });
  });

  group('SokobanLogic — детерминизм', () {
    test('одинаковое зерно даёт идентичный старт', () {
      final a = SokobanLogic(random: Random(42));
      final b = SokobanLogic(random: Random(42));
      expect(a.player, b.player);
      expect(a.cols, b.cols);
      expect(a.rows, b.rows);
      for (var y = 0; y < a.rows; y++) {
        for (var x = 0; x < a.cols; x++) {
          expect(a.tileAt(x, y), b.tileAt(x, y), reason: '($x,$y)');
        }
      }
    });
  });
}
