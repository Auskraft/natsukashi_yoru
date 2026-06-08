import 'dart:math';

/// Тип особого камня.
/// none — обычный; lineH/lineV — линейный (чистит строку/столбец при активации);
/// colorBomb — цвет-бомба (чистит все камни своего цвета).
enum Special { none, lineH, lineV, colorBomb }

/// Камень на доске: цвет (0..colors-1) и опциональный особый эффект.
/// Поля публичны и иммутабельны — слой Flame читает их для рендера.
class Gem {
  const Gem(this.color, [this.special = Special.none]);

  /// Индекс цвета. Для цвет-бомбы цвет визуально неважен, но хранится
  /// (бомба, попавшая в обычный матч, тоже срабатывает по этому цвету).
  final int color;
  final Special special;

  bool get isSpecial => special != Special.none;

  Gem withSpecial(Special s) => Gem(color, s);

  @override
  bool operator ==(Object other) =>
      other is Gem && other.color == color && other.special == special;

  @override
  int get hashCode => Object.hash(color, special);

  @override
  String toString() => 'Gem($color, $special)';
}

/// Позиция клетки на доске (col=x, row=y). Удобный алиас для читаемости.
typedef Cell = Point<int>;

/// Описание одного лопнувшего камня — для частиц «в цвет».
class ClearedGem {
  const ClearedGem(this.pos, this.color, this.special);

  final Cell pos;
  final int color;

  /// Каким был камень в момент очистки (особый он или нет) — для эффектов.
  final Special special;
}

/// Описание созданного особого камня — для «вспышки» при рождении.
class CreatedSpecial {
  const CreatedSpecial(this.pos, this.color, this.special);

  final Cell pos;
  final int color;
  final Special special;
}

/// Один шаг каскада (одна «волна» очистки) — данные для «сока».
/// Слой рендера проигрывает шаги по очереди: лопнувшие камни, рождённые
/// особые, начисленные за волну очки и её порядковый номер.
class CascadeStep {
  CascadeStep({
    required this.wave,
    required this.cleared,
    required this.created,
    required this.gained,
  });

  /// Номер волны каскада, начиная с 1.
  final int wave;

  /// Все камни, очищенные в этой волне (с позицией, цветом, бывшим типом).
  final List<ClearedGem> cleared;

  /// Особые камни, рождённые в этой волне (на месте матчей 4/5).
  final List<CreatedSpecial> created;

  /// Очки, начисленные за эту волну.
  final int gained;
}

/// Итог попытки обмена — то, ЧТО изменилось, для частиц и попапов.
/// Если [swapped] == false, обмена не было (несоседние клетки или нет матча,
/// тогда [reverted] == true и доска возвращена в исходное состояние).
class SwapResult {
  SwapResult({
    required this.swapped,
    required this.reverted,
    required this.steps,
    required this.gained,
    required this.gameOver,
  });

  /// Был ли выполнен обмен камней.
  final bool swapped;

  /// Был ли обмен откатан (валидный обмен, но матча не возникло).
  final bool reverted;

  /// Каскад очисток. Пуст при откате/несоседних клетках.
  final List<CascadeStep> steps;

  /// Суммарно начисленные очки за весь каскад.
  final int gained;

  /// Конец игры (нет возможных ходов после доборов).
  final bool gameOver;

  /// Сколько волн было в каскаде.
  int get cascadeLength => steps.length;
}

/// Чистая логика «Bejeweled» (свап-матч с особыми камнями) без рендера и
/// Flutter-зависимостей — поэтому легко тестируется. Рендер и «сок» живут
/// в Flame-слое и читают публичные поля доски.
class BejeweledLogic {
  BejeweledLogic({
    this.cols = 8,
    this.rows = 8,
    this.colors = 6,
    Random? random,
  }) : _rng = random ?? Random() {
    reset();
  }

  final int cols;
  final int rows;

  /// Количество базовых цветов.
  final int colors;

  final Random _rng;

  /// board[y][x] — камень в клетке. Заполнена всегда (нет пустых после хода).
  late List<List<Gem>> board;

  int score = 0;
  bool gameOver = false;

  /// Заполнить доску так, чтобы стартовых матчей не было, и сбросить счёт.
  void reset() {
    score = 0;
    gameOver = false;
    board = List.generate(
      rows,
      (_) => List<Gem>.filled(cols, const Gem(0)),
    );
    _fillNoMatches();
  }

  Gem gemAt(int x, int y) => board[y][x];

  bool _inBounds(int x, int y) => x >= 0 && x < cols && y >= 0 && y < rows;

  /// Соседние ли клетки (по стороне, не по диагонали).
  bool areAdjacent(Cell a, Cell b) {
    final dx = (a.x - b.x).abs();
    final dy = (a.y - b.y).abs();
    return (dx + dy) == 1;
  }

  /// Попытаться обменять две клетки [a] и [b].
  /// Обмен валиден только для соседей. Если после обмена нет матча —
  /// откатываем (классическое правило Bejeweled) и возвращаем reverted.
  /// Особый случай: обмен двух особых / особого с цвет-бомбой срабатывает
  /// даже без обычного матча.
  SwapResult trySwap(Cell a, Cell b) {
    if (gameOver || !_inBounds(a.x, a.y) || !_inBounds(b.x, b.y)) {
      return SwapResult(
        swapped: false,
        reverted: false,
        steps: const [],
        gained: 0,
        gameOver: gameOver,
      );
    }
    if (!areAdjacent(a, b)) {
      return SwapResult(
        swapped: false,
        reverted: false,
        steps: const [],
        gained: 0,
        gameOver: gameOver,
      );
    }

    _swapCells(a, b);

    // Обмен с участием особых камней активирует их сразу, без матча.
    final ga = board[a.y][a.x];
    final gb = board[b.y][b.x];
    final forced = <Cell>{};
    if (ga.isSpecial) forced.add(a);
    if (gb.isSpecial) forced.add(b);

    final matches = _findMatches();
    if (matches.isEmpty && forced.isEmpty) {
      // Нет матча и нет активируемых особых — откат.
      _swapCells(a, b);
      return SwapResult(
        swapped: false,
        reverted: true,
        steps: const [],
        gained: 0,
        gameOver: gameOver,
      );
    }

    // Камень-«источник» для рождения особого при матче — место обмена.
    final steps = _resolve(swapA: a, swapB: b, forced: forced);
    final gained = steps.fold<int>(0, (s, st) => s + st.gained);
    score += gained;

    gameOver = !_hasPossibleMove();

    return SwapResult(
      swapped: true,
      reverted: false,
      steps: steps,
      gained: gained,
      gameOver: gameOver,
    );
  }

  void _swapCells(Cell a, Cell b) {
    final tmp = board[a.y][a.x];
    board[a.y][a.x] = board[b.y][b.x];
    board[b.y][b.x] = tmp;
  }

  // ───────────────────────── Поиск матчей ─────────────────────────

  /// Найти все матчи как «сырые» линии (горизонтальные и вертикальные по >=3),
  /// которые позже агрегируются в очистку и рождение особых.
  /// Цвет линии берётся из любого её камня (все одного цвета).
  List<_Line> _findMatches() {
    final lines = <_Line>[];

    // Горизонтальные.
    for (var y = 0; y < rows; y++) {
      var runStart = 0;
      for (var x = 1; x <= cols; x++) {
        final same = x < cols && board[y][x].color == board[y][runStart].color;
        if (!same) {
          final len = x - runStart;
          if (len >= 3) {
            lines.add(_Line(
              horizontal: true,
              color: board[y][runStart].color,
              cells: [for (var i = runStart; i < x; i++) Point(i, y)],
            ));
          }
          runStart = x;
        }
      }
    }

    // Вертикальные.
    for (var x = 0; x < cols; x++) {
      var runStart = 0;
      for (var y = 1; y <= rows; y++) {
        final same = y < rows && board[y][x].color == board[runStart][x].color;
        if (!same) {
          final len = y - runStart;
          if (len >= 3) {
            lines.add(_Line(
              horizontal: false,
              color: board[runStart][x].color,
              cells: [for (var i = runStart; i < y; i++) Point(x, i)],
            ));
          }
          runStart = y;
        }
      }
    }

    return lines;
  }

  // ───────────────────────── Разрешение каскада ─────────────────────────

  /// Прогнать весь каскад: матчи → очистка (с активацией особых) →
  /// рождение особых → гравитация → добор → повтор, пока матчи есть.
  /// [swapA]/[swapB] — клетки последнего обмена (приоритет места рождения
  /// особого). [forced] — особые, активированные самим обменом без матча.
  List<CascadeStep> _resolve({
    Cell? swapA,
    Cell? swapB,
    Set<Cell> forced = const <Cell>{},
  }) {
    final steps = <CascadeStep>[];
    var wave = 0;

    // Первая волна может включать принудительную активацию (обмен особыми).
    var pendingForced = forced;

    while (true) {
      final lines = _findMatches();
      if (lines.isEmpty && pendingForced.isEmpty) break;

      wave++;

      // 1) Определяем, какие особые родятся (по длинным линиям), и где.
      final created = <CreatedSpecial>[];
      // Клетки, которые НЕ нужно очищать, т.к. на них родится особый.
      final birthCells = <Cell>{};

      for (final line in lines) {
        if (line.cells.length >= 5) {
          // Матч-5 в линию → цвет-бомба.
          final pos = _birthPos(line, swapA, swapB);
          created.add(CreatedSpecial(pos, line.color, Special.colorBomb));
          birthCells.add(pos);
        } else if (line.cells.length == 4) {
          // Матч-4 → линейный камень, чистящий вдоль той же оси, что и линия:
          // горизонтальный матч даёт lineH (чистит строку), вертикальный — lineV.
          final pos = _birthPos(line, swapA, swapB);
          final s = line.horizontal ? Special.lineH : Special.lineV;
          created.add(CreatedSpecial(pos, line.color, s));
          birthCells.add(pos);
        }
      }

      // 2) Базовое множество клеток к очистке — все клетки матчей.
      final toClear = <Cell>{};
      for (final line in lines) {
        toClear.addAll(line.cells);
      }
      // Принудительно активированные обменом особые тоже очищаются.
      toClear.addAll(pendingForced);

      // 3) Активация особых: любой особый камень, попавший в очистку,
      //    раскрывает свой эффект. Делаем замыкание (эффект может задеть
      //    другие особые — те тоже активируются).
      _expandSpecials(toClear);

      // 4) Собираем данные «сока» по очищенным клеткам.
      //    Клетки рождения особого исключаем из «лопнувших».
      final cleared = <ClearedGem>[];
      for (final c in toClear) {
        if (birthCells.contains(c)) continue;
        final g = board[c.y][c.x];
        cleared.add(ClearedGem(c, g.color, g.special));
      }

      // 5) Очки: 3 в ряд = 10 за камень; особые и каскады дороже.
      final gained = _scoreFor(cleared.length, created, wave);

      // 6) Применяем к доске: сначала очистка, потом рождение особых.
      for (final c in toClear) {
        board[c.y][c.x] = const Gem(-1); // -1 — временно пусто
      }
      for (final cs in created) {
        board[cs.pos.y][cs.pos.x] = Gem(cs.color, cs.special);
      }

      steps.add(CascadeStep(
        wave: wave,
        cleared: cleared,
        created: created,
        gained: gained,
      ));

      // 7) Гравитация + добор новыми камнями.
      _collapseAndRefill();

      // Принудительная активация — только в первой волне.
      pendingForced = const <Cell>{};
      // Рождение особого «привязано» к обмену лишь на первой волне.
      swapA = null;
      swapB = null;
    }

    return steps;
  }

  /// Где родить особый камень: предпочтительно в клетке обмена, если она
  /// лежит на линии; иначе — в середине линии (детерминированно).
  Cell _birthPos(_Line line, Cell? swapA, Cell? swapB) {
    if (swapA != null && line.cells.contains(swapA)) return swapA;
    if (swapB != null && line.cells.contains(swapB)) return swapB;
    return line.cells[line.cells.length ~/ 2];
  }

  /// Раскрыть эффекты всех особых камней внутри [toClear], добавляя
  /// затронутые клетки. Повторяем, пока множество растёт (цепная реакция).
  void _expandSpecials(Set<Cell> toClear) {
    final queue = <Cell>[...toClear];
    while (queue.isNotEmpty) {
      final c = queue.removeLast();
      final g = board[c.y][c.x];
      switch (g.special) {
        case Special.none:
          break;
        case Special.lineH:
          for (var x = 0; x < cols; x++) {
            final p = Point(x, c.y);
            if (toClear.add(p)) queue.add(p);
          }
          break;
        case Special.lineV:
          for (var y = 0; y < rows; y++) {
            final p = Point(c.x, y);
            if (toClear.add(p)) queue.add(p);
          }
          break;
        case Special.colorBomb:
          // Цвет-бомба чистит все камни своего цвета по всей доске.
          for (var y = 0; y < rows; y++) {
            for (var x = 0; x < cols; x++) {
              if (board[y][x].color == g.color) {
                final p = Point(x, y);
                if (toClear.add(p)) queue.add(p);
              }
            }
          }
          break;
      }
    }
  }

  /// Очки за волну: базово 10 за обычный камень, надбавка за особые и
  /// множитель за номер волны каскада (чем глубже каскад — тем дороже).
  int _scoreFor(int clearedCount, List<CreatedSpecial> created, int wave) {
    var base = clearedCount * 10;
    for (final cs in created) {
      base += switch (cs.special) {
        Special.colorBomb => 100, // цвет-бомба ценнее всего
        Special.lineH || Special.lineV => 50, // линейный
        Special.none => 0,
      };
    }
    return base * wave; // каскадный множитель
  }

  /// Гравитация: камни падают вниз в пустоты (Gem(-1)), сверху добор новыми.
  void _collapseAndRefill() {
    for (var x = 0; x < cols; x++) {
      // Снизу вверх: собираем уцелевшие, считаем пустоты.
      var write = rows - 1;
      for (var y = rows - 1; y >= 0; y--) {
        if (board[y][x].color != -1) {
          board[write][x] = board[y][x];
          write--;
        }
      }
      // Оставшиеся сверху клетки — добор случайными цветами.
      for (var y = write; y >= 0; y--) {
        board[y][x] = Gem(_rng.nextInt(colors));
      }
    }
  }

  /// Стартовое заполнение без готовых троек (чтобы игра не «само-играла»).
  void _fillNoMatches() {
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        int color;
        var guard = 0;
        do {
          color = _rng.nextInt(colors);
          guard++;
        } while (guard < 100 && _wouldMatch(x, y, color));
        board[y][x] = Gem(color);
      }
    }
  }

  /// Создаст ли постановка [color] в (x,y) тройку с уже стоящими слева/сверху.
  bool _wouldMatch(int x, int y, int color) {
    if (x >= 2 &&
        board[y][x - 1].color == color &&
        board[y][x - 2].color == color) {
      return true;
    }
    if (y >= 2 &&
        board[y - 1][x].color == color &&
        board[y - 2][x].color == color) {
      return true;
    }
    return false;
  }

  // ───────────────────────── Доступность ходов ─────────────────────────

  /// Есть ли хоть один обмен, дающий матч (иначе — конец игры).
  /// Особые камни на доске гарантируют наличие хода.
  bool _hasPossibleMove() {
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (board[y][x].isSpecial) return true;
        // Пробуем обмен вправо и вниз — этого достаточно для всех пар.
        if (x + 1 < cols && _swapMakesMatch(Point(x, y), Point(x + 1, y))) {
          return true;
        }
        if (y + 1 < rows && _swapMakesMatch(Point(x, y), Point(x, y + 1))) {
          return true;
        }
      }
    }
    return false;
  }

  /// Дал бы обмен матч? Проверяем без мутации наблюдаемого состояния
  /// (свапаем туда-обратно).
  bool _swapMakesMatch(Cell a, Cell b) {
    _swapCells(a, b);
    final has = _findMatches().isNotEmpty;
    _swapCells(a, b);
    return has;
  }
}

/// Внутреннее описание линии совпадения (для рождения особых камней).
class _Line {
  _Line({required this.horizontal, required this.color, required this.cells});

  final bool horizontal;
  final int color;
  final List<Cell> cells;
}
