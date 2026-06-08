import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/match3/components/match3_logic.dart';

/// Пересобрать доску логики из «строк» enum-ов. Удобно для прямой инициализации
/// сценариев (каскады, матчи) без зависимости от случайного добора.
void setBoard(MatchThreeLogic g, List<List<Gem>> rows) {
  assert(rows.length == MatchThreeLogic.rows);
  for (var y = 0; y < MatchThreeLogic.rows; y++) {
    assert(rows[y].length == MatchThreeLogic.cols);
    for (var x = 0; x < MatchThreeLogic.cols; x++) {
      g.board[y][x] = rows[y][x];
    }
  }
}

/// Есть ли в текущем поле хоть один матч (≥3 подряд) — для проверки инвариантов.
bool hasAnyMatch(MatchThreeLogic g) {
  const cols = MatchThreeLogic.cols;
  const rows = MatchThreeLogic.rows;
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      final gem = g.board[y][x];
      if (x + 2 < cols &&
          g.board[y][x + 1] == gem &&
          g.board[y][x + 2] == gem) {
        return true;
      }
      if (y + 2 < rows &&
          g.board[y + 1][x] == gem &&
          g.board[y + 2][x] == gem) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  const r = Gem.red;
  const o = Gem.orange;
  const g_ = Gem.green;

  /// Шахматная «безматчевая» подложка из двух цветов: соседи по строке и по
  /// столбцу всегда разные, поэтому троек не возникает.
  List<List<Gem>> checkerBoard() => List.generate(
        MatchThreeLogic.rows,
        (y) => List.generate(
          MatchThreeLogic.cols,
          (x) => (x + y).isEven ? Gem.red : Gem.blue,
        ),
      );

  group('старт', () {
    test('поле полностью заполнено и без готовых матчей', () {
      for (var seed = 0; seed < 25; seed++) {
        final game = MatchThreeLogic(random: Random(seed));
        // Все клетки заданы (enum, не null) — доска полна.
        expect(game.board.length, MatchThreeLogic.rows);
        for (final row in game.board) {
          expect(row.length, MatchThreeLogic.cols);
        }
        expect(hasAnyMatch(game), isFalse,
            reason: 'seed=$seed дал матч на старте');
      }
    });

    test('счёт стартует с нуля', () {
      final game = MatchThreeLogic(random: Random(1));
      expect(game.score, 0);
    });
  });

  group('areAdjacent', () {
    test('по стороне — соседи, по диагонали и дальше — нет', () {
      expect(MatchThreeLogic.areAdjacent(const Point(1, 1), const Point(2, 1)),
          isTrue);
      expect(MatchThreeLogic.areAdjacent(const Point(1, 1), const Point(1, 2)),
          isTrue);
      expect(MatchThreeLogic.areAdjacent(const Point(1, 1), const Point(2, 2)),
          isFalse);
      expect(MatchThreeLogic.areAdjacent(const Point(1, 1), const Point(1, 1)),
          isFalse);
      expect(MatchThreeLogic.areAdjacent(const Point(1, 1), const Point(3, 1)),
          isFalse);
    });
  });

  group('trySwap', () {
    test('обмен несоседних клеток не применяется', () {
      final game = MatchThreeLogic(random: Random(3));
      setBoard(game, checkerBoard());
      final res = game.trySwap(const Point(0, 0), const Point(2, 0));
      expect(res.applied, isFalse);
      expect(res.waves, 0);
      expect(game.score, 0);
    });

    test('обмен без матча откатывается, доска не меняется', () {
      final game = MatchThreeLogic(random: Random(4));
      setBoard(game, checkerBoard());
      // Снимок доски до обмена.
      final before = <List<Gem>>[
        for (final row in game.board) [...row],
      ];

      // Любой обмен соседей на шахматке матча не создаёт.
      final res = game.trySwap(const Point(0, 0), const Point(1, 0));
      expect(res.applied, isFalse);
      expect(res.waves, 0);
      expect(res.gained, 0);
      expect(game.score, 0);

      for (var y = 0; y < MatchThreeLogic.rows; y++) {
        for (var x = 0; x < MatchThreeLogic.cols; x++) {
          expect(game.board[y][x], before[y][x],
              reason: 'клетка ($x,$y) изменилась после отката');
        }
      }
    });

    test('обмен, создающий тройку, применяется и чистит >=3', () {
      final game = MatchThreeLogic(random: Random(5));
      // Подготовим горизонтальную тройку: в строке 0 нужны R на x=0,1,2.
      // Ставим R на (0,0) и (1,0), а на (2,0) кладём R под (2,1)=R, чтобы
      // вертикальный обмен (2,0)<->(2,1) привёл R наверх и собрал тройку.
      final brd = checkerBoard();
      brd[0][0] = r;
      brd[0][1] = r;
      brd[0][2] = o; // сейчас не R
      brd[1][2] = r; // обменяем вверх -> (2,0) станет R -> тройка R на y=0
      setBoard(game, brd);

      final scoreBefore = game.score;
      final res = game.trySwap(const Point(2, 0), const Point(2, 1));
      expect(res.applied, isTrue);
      expect(res.waves, greaterThanOrEqualTo(1));

      final firstWave = res.cascades.first;
      expect(firstWave.wave, 1);
      expect(firstWave.count, greaterThanOrEqualTo(3),
          reason: 'первая волна должна убрать минимум тройку');
      // В исходе есть позиции и цвета — данные для частиц.
      expect(firstWave.cleared.every((c) => c.gem == r), isTrue,
          reason: 'лопнули именно красные');

      expect(res.gained, greaterThan(0));
      expect(game.score, scoreBefore + res.gained);

      // После хода матчей не остаётся (каскад досчитан до конца).
      expect(hasAnyMatch(game), isFalse);
    });
  });

  group('resolve / каскад', () {
    test('готовая тройка лопает в первой волне: позиции, цвет, очки', () {
      final game = MatchThreeLogic(random: Random(6));
      final brd = checkerBoard();
      // Готовая горизонтальная тройка зелёных внизу — единственный матч.
      brd[7][0] = g_;
      brd[7][1] = g_;
      brd[7][2] = g_;
      setBoard(game, brd);

      final steps = game.resolve();
      expect(steps, isNotEmpty);
      final first = steps.first;
      expect(first.wave, 1);
      // Ровно три зелёных в известных позициях (исход для частиц/попапов).
      expect(first.count, 3);
      expect(first.cleared.every((c) => c.gem == g_), isTrue);
      expect(first.cleared.map((c) => c.pos).toSet(), {
        const Point(0, 7),
        const Point(1, 7),
        const Point(2, 7),
      });
      // Очки первой волны = число фишек * 10 * множитель(=1).
      expect(first.gained, 30);
    });

    test('подобранное поле даёт каскад из >1 волны', () {
      final game = MatchThreeLogic(random: Random(7));

      // Конструкция каскада на «выживших» (минимум зависимости от добора).
      // Базис — шахматка red/blue (троек нет). Цвета каскада (orange/green)
      // не совпадают с базисом, чтобы не создавать лишних совпадений.
      //   столбец 0 (сверху вниз): R B R G G O O O
      //     · O,O,O на y=5,6,7 — вертикальная тройка, лопнет в ВОЛНЕ 1;
      //     · G,G на y=3,4 — выжившие, после падения станут (0,6) и (0,7);
      //   столбцы 1 и 2: на y=7 заранее лежит G и НЕ трогается в волне 1.
      // После падения строка y=7 = [G(0), G(1), G(2), …] -> ВОЛНА 2.
      final brd = checkerBoard();
      brd[5][0] = o;
      brd[6][0] = o;
      brd[7][0] = o; // тройка O в столбце 0 -> волна 1
      brd[3][0] = g_; // выживет -> упадёт на (0,6)
      brd[4][0] = g_; // выживет -> упадёт на (0,7)
      brd[7][1] = g_; // заранее для волны 2
      brd[7][2] = g_; // заранее для волны 2
      setBoard(game, brd);

      final steps = game.resolve();

      // Каскад: минимум две волны, нумерация по порядку.
      expect(steps.length, greaterThanOrEqualTo(2),
          reason: 'ожидался каскад из нескольких волн');
      expect(steps[0].wave, 1);
      expect(steps[1].wave, 2);

      // Волна 1 — ровно тройка O в столбце 0 (единственный матч на старте).
      expect(steps[0].count, 3);
      expect(steps[0].cleared.every((c) => c.gem == o), isTrue,
          reason: 'первой лопает тройка оранжевых');
      expect(steps[0].cleared.map((c) => c.pos).toSet(), {
        const Point(0, 5),
        const Point(0, 6),
        const Point(0, 7),
      });

      // Волна 2 порождена падением: в ней присутствует горизонтальная тройка
      // зелёных в нижней строке (данные для частиц «в цвет»).
      final wave2 = steps[1];
      for (final p in const [Point(0, 7), Point(1, 7), Point(2, 7)]) {
        final hit = wave2.cleared.where((c) => c.pos == p);
        expect(hit.length, 1, reason: 'в волне 2 ждали очистку $p');
        expect(hit.first.gem, g_, reason: 'в $p должна лопнуть зелёная');
      }

      // По завершении каскада матчей не остаётся (инвариант resolve).
      expect(hasAnyMatch(game), isFalse);

      // Счёт = сумма всех волн; растущий множитель делает поздние волны дороже
      // за фишку: цена за 1 фишку в волне 2 строго больше, чем в волне 1.
      final sum = steps.fold<int>(0, (acc, s) => acc + s.gained);
      expect(game.score, sum);
      expect(steps[1].gained / steps[1].count,
          greaterThan(steps[0].gained / steps[0].count),
          reason: 'множитель волны 2 выше волны 1');
    });

    test('счёт растёт на сумму очков всех волн', () {
      final game = MatchThreeLogic(random: Random(8));
      final brd = checkerBoard();
      brd[7][0] = g_;
      brd[7][1] = g_;
      brd[7][2] = g_;
      setBoard(game, brd);

      expect(game.score, 0);
      final steps = game.resolve();
      final sum = steps.fold<int>(0, (acc, s) => acc + s.gained);
      expect(game.score, sum);
      expect(sum, greaterThan(0));
    });
  });

  group('гравитация и добор', () {
    test('после каскада поле снова полностью заполнено', () {
      final game = MatchThreeLogic(random: Random(9));
      final brd = checkerBoard();
      brd[7][0] = g_;
      brd[7][1] = g_;
      brd[7][2] = g_;
      setBoard(game, brd);

      game.resolve();
      // Доска по-прежнему полна (бесконечный режим — пустых клеток нет).
      expect(game.board.length, MatchThreeLogic.rows);
      for (final row in game.board) {
        expect(row.length, MatchThreeLogic.cols);
      }
    });
  });
}
