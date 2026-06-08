import 'dart:math';

/// Цвет фишки. Шесть видов; хранится как enum, чтобы слой Flame сам выбрал
/// текстуру/палитру (никаких Color здесь — логика чистая).
enum Gem { red, orange, yellow, green, blue, purple }

/// Одна очищенная фишка: её позиция на доске и цвет (до схлопывания).
/// Нужно слою рендера для частиц «в цвет» и попапов в точке взрыва.
class ClearedGem {
  const ClearedGem(this.pos, this.gem);

  final Point<int> pos;
  final Gem gem;

  @override
  String toString() => 'ClearedGem(${pos.x},${pos.y},$gem)';
}

/// Один «всплеск» каскада: что лопнуло на этой волне, сколько начислено очков
/// и порядковый номер волны (1 — первая, дальше растёт множитель).
class CascadeStep {
  CascadeStep({
    required this.wave,
    required this.cleared,
    required this.gained,
  });

  /// Номер волны каскада, начиная с 1.
  final int wave;

  /// Лопнувшие фишки этой волны (позиции + цвета) — для частиц и попапов.
  final List<ClearedGem> cleared;

  /// Очки, начисленные за эту волну (с учётом множителя волны).
  final int gained;

  /// Сколько фишек убрано на этой волне.
  int get count => cleared.length;
}

/// Итог хода [MatchThreeLogic.trySwap]: применился ли обмен и весь каскад,
/// который он породил. Один объект — всё, что нужно «соку» после свайпа.
class SwapResult {
  SwapResult({
    required this.applied,
    required this.a,
    required this.b,
    required this.cascades,
    required this.gained,
  });

  /// Создал ли обмен матч (true) или был откатан (false).
  final bool applied;

  /// Обменянные клетки (как их передал вызывающий) — для анимации свайпа/отката.
  final Point<int> a;
  final Point<int> b;

  /// Волны каскада по порядку. Пусто, если [applied] == false.
  final List<CascadeStep> cascades;

  /// Сумма очков за весь ход.
  final int gained;

  /// Глубина каскада (число волн). 0 — обмен не дал матча.
  int get waves => cascades.length;
}

/// Чистая логика «три в ряд» без рендера и Flutter-зависимостей — тестируемая.
/// Поле, счёт и исход хода читаются публично; рендер и «сок» живут в Flame.
class MatchThreeLogic {
  MatchThreeLogic({Random? random}) : _rng = random ?? Random() {
    reset();
  }

  static const int cols = 8;
  static const int rows = 8;

  final Random _rng;

  /// board[y][x] — цвет фишки в клетке. Заполнено всегда (бесконечный режим).
  late List<List<Gem>> board;

  /// Накопленные очки за всю партию.
  int score = 0;

  /// Заново раздать поле без готовых матчей и обнулить счёт.
  void reset() {
    score = 0;
    board = List.generate(
      rows,
      (_) => List<Gem>.filled(cols, Gem.red),
    );
    _fillWithoutMatches();
  }

  /// Цвет клетки или null за пределами доски.
  Gem? gemAt(int x, int y) {
    if (x < 0 || y < 0 || x >= cols || y >= rows) return null;
    return board[y][x];
  }

  /// Соседние ли клетки (по стороне, не по диагонали).
  static bool areAdjacent(Point<int> a, Point<int> b) {
    final dx = (a.x - b.x).abs();
    final dy = (a.y - b.y).abs();
    return dx + dy == 1;
  }

  bool _inBounds(Point<int> p) =>
      p.x >= 0 && p.y >= 0 && p.x < cols && p.y < rows;

  /// Попытаться обменять две СОСЕДНИЕ клетки.
  ///
  /// Если обмен создаёт хотя бы один матч (≥3 подряд по горизонтали или
  /// вертикали) — обмен применяется, запускается каскад с гравитацией и
  /// добором; иначе обмен откатывается. Возвращает [SwapResult] с описанием
  /// того, что произошло (для частиц/попапов).
  SwapResult trySwap(Point<int> a, Point<int> b) {
    // Невалидный ход: вне поля, та же клетка или не соседи — откат без эффекта.
    if (!_inBounds(a) || !_inBounds(b) || !areAdjacent(a, b)) {
      return _noSwap(a, b);
    }

    _swapCells(a, b);

    // Матч проверяем только вокруг двух тронутых клеток — этого достаточно,
    // т.к. до обмена матчей на доске не было.
    if (!_hasMatchAt(a) && !_hasMatchAt(b)) {
      _swapCells(a, b); // откат
      return _noSwap(a, b);
    }

    final cascades = resolve();
    var gained = 0;
    for (final c in cascades) {
      gained += c.gained;
    }
    return SwapResult(
      applied: true,
      a: a,
      b: b,
      cascades: cascades,
      gained: gained,
    );
  }

  /// Разрешить все матчи каскадом: чистка → гравитация → добор → повтор,
  /// пока матчи есть. Возвращает волны по порядку.
  ///
  /// Публичный метод: слой Flame может проигрывать волны по очереди (с паузой
  /// на анимацию), а также вызывать вручную после прямой правки [board].
  List<CascadeStep> resolve() {
    final steps = <CascadeStep>[];
    var wave = 1;

    while (true) {
      final matched = _findMatches();
      if (matched.isEmpty) break;

      final cleared = <ClearedGem>[
        for (final p in matched) ClearedGem(p, board[p.y][p.x]),
      ];

      // Множитель растёт с номером волны: 1, 2, 3, … За каждую фишку — 10 очков.
      final gained = cleared.length * _pointsPerGem * wave;
      score += gained;
      steps.add(CascadeStep(wave: wave, cleared: cleared, gained: gained));

      _removeAndCollapse(matched);
      wave++;
    }
    return steps;
  }

  static const int _pointsPerGem = 10;

  /// Исход «обмен не состоялся» (откат) — без волн и очков.
  SwapResult _noSwap(Point<int> a, Point<int> b) =>
      SwapResult(applied: false, a: a, b: b, cascades: const [], gained: 0);

  void _swapCells(Point<int> a, Point<int> b) {
    final tmp = board[a.y][a.x];
    board[a.y][a.x] = board[b.y][b.x];
    board[b.y][b.x] = tmp;
  }

  /// Все позиции, входящие в какой-либо матч (без дублей), по всей доске.
  Set<Point<int>> _findMatches() {
    final matched = <Point<int>>{};

    // Горизонтальные серии.
    for (var y = 0; y < rows; y++) {
      var runStart = 0;
      for (var x = 1; x <= cols; x++) {
        final same = x < cols && board[y][x] == board[y][runStart];
        if (!same) {
          if (x - runStart >= 3) {
            for (var i = runStart; i < x; i++) {
              matched.add(Point(i, y));
            }
          }
          runStart = x;
        }
      }
    }

    // Вертикальные серии.
    for (var x = 0; x < cols; x++) {
      var runStart = 0;
      for (var y = 1; y <= rows; y++) {
        final same = y < rows && board[y][x] == board[runStart][x];
        if (!same) {
          if (y - runStart >= 3) {
            for (var i = runStart; i < y; i++) {
              matched.add(Point(x, i));
            }
          }
          runStart = y;
        }
      }
    }

    return matched;
  }

  /// Есть ли матч, проходящий через клетку [p] (быстрая проверка для свайпа).
  bool _hasMatchAt(Point<int> p) {
    final gem = board[p.y][p.x];

    // По горизонтали: считаем одинаковые слева и справа.
    var run = 1;
    for (var x = p.x - 1; x >= 0 && board[p.y][x] == gem; x--) {
      run++;
    }
    for (var x = p.x + 1; x < cols && board[p.y][x] == gem; x++) {
      run++;
    }
    if (run >= 3) return true;

    // По вертикали.
    run = 1;
    for (var y = p.y - 1; y >= 0 && board[y][p.x] == gem; y--) {
      run++;
    }
    for (var y = p.y + 1; y < rows && board[y][p.x] == gem; y++) {
      run++;
    }
    return run >= 3;
  }

  /// Убрать матчи и обрушить столбцы: уцелевшие фишки падают вниз, сверху
  /// досыпаются новые случайные.
  void _removeAndCollapse(Set<Point<int>> matched) {
    // Помечаем убранные по столбцам, чтобы пройтись снизу вверх.
    for (var x = 0; x < cols; x++) {
      // Собираем уцелевшие фишки столбца снизу вверх.
      final survivors = <Gem>[];
      for (var y = rows - 1; y >= 0; y--) {
        if (!matched.contains(Point(x, y))) {
          survivors.add(board[y][x]);
        }
      }
      // Раскладываем обратно: дно столбца — уцелевшие, верх — новые случайные.
      for (var y = rows - 1, i = 0; y >= 0; y--, i++) {
        if (i < survivors.length) {
          board[y][x] = survivors[i];
        } else {
          board[y][x] = _randomGem();
        }
      }
    }
  }

  Gem _randomGem() => Gem.values[_rng.nextInt(Gem.values.length)];

  /// Заполнить доску случайными фишками так, чтобы ни одного готового матча
  /// не было. Для каждой клетки исключаем цвета, дающие тройку влево или вверх.
  void _fillWithoutMatches() {
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final forbidden = <Gem>{};

        // Два слева одного цвета — третий такой же создал бы горизонтальный матч.
        if (x >= 2 && board[y][x - 1] == board[y][x - 2]) {
          forbidden.add(board[y][x - 1]);
        }
        // Два сверху одного цвета — третий такой же создал бы вертикальный матч.
        if (y >= 2 && board[y - 1][x] == board[y - 2][x]) {
          forbidden.add(board[y - 1][x]);
        }

        final choices = [
          for (final g in Gem.values)
            if (!forbidden.contains(g)) g,
        ];
        // forbidden не более 2 цветов из 6 — choices всегда непусто.
        board[y][x] = choices[_rng.nextInt(choices.length)];
      }
    }
  }
}
