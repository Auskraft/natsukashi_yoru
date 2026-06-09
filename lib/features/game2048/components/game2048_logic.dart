import 'dart:math';

/// Направление свайпа в «2048».
enum SlideDirection { up, down, left, right }

/// Одно слияние, случившееся за ход: куда (в координатах сетки) встала
/// получившаяся плитка и её НОВОЕ значение (сумма двух слитых).
///
/// Нужно слою «сока», чтобы пустить частицы/попап «в цвет» итоговой плитки
/// в точке слияния.
class Merge {
  const Merge({required this.x, required this.y, required this.value});

  /// Координаты получившейся плитки на сетке (0..size-1).
  final int x;
  final int y;

  /// Значение получившейся плитки (степень двойки, напр. 4, 8, …).
  final int value;
}

/// Появившаяся за ход плитка: позиция и значение (2 или 4).
class Spawn {
  const Spawn({required this.x, required this.y, required this.value});

  final int x;
  final int y;
  final int value;
}

/// Итог одного хода [Game2048Logic.move] — что изменилось за ход.
///
/// Содержит всё, что нужно «соку»: сдвинулось ли поле вообще, какие плитки
/// слились (с их позициями/значениями), какая новая плитка появилась, сколько
/// очков начислено и достигнута ли впервые плитка 2048.
class MoveResult {
  MoveResult({
    required this.moved,
    required this.merges,
    required this.spawned,
    required this.gained,
    required this.reached2048,
  });

  /// Пустой исход — ход ничего не изменил (поле осталось прежним).
  factory MoveResult.none() => MoveResult(
        moved: false,
        merges: const [],
        spawned: null,
        gained: 0,
        reached2048: false,
      );

  /// Сдвинул или слил ли ход хоть что-то. Если false — новую плитку не спавним.
  final bool moved;

  /// Слияния этого хода (позиция + итоговое значение) — для частиц/попапов.
  final List<Merge> merges;

  /// Появившаяся после хода плитка или null, если ход ничего не изменил.
  final Spawn? spawned;

  /// Очки за ход — сумма значений всех получившихся при слиянии плиток.
  final int gained;

  /// Достигнута ли впервые плитка 2048 (для особого акцента).
  final bool reached2048;
}

/// Чистая логика «2048» без рендера и Flutter-зависимостей — тестируемая.
///
/// Сетка [size]×[size] целых: 0 — пусто, иначе степень двойки. Свайп сдвигает
/// все плитки к краю и сливает одинаковые соседние (каждая плитка участвует в
/// слиянии не более раза за ход; слияние идёт от края направления). Если ход
/// что-то изменил — спавнится новая плитка (2 с вер. 90%, 4 с 10%).
///
/// Состояние ([grid], [score], [won], плитки) читается публично; «сок» берёт
/// данные из [MoveResult].
class Game2048Logic {
  Game2048Logic({this.size = 4, Random? random}) : _rng = random ?? Random() {
    reset();
  }

  /// Цель победы — первая плитка такого номинала зажигает «реколор-салют».
  static const int winValue = 2048;

  /// Сторона квадратной сетки.
  final int size;
  final Random _rng;

  /// Плоская сетка размером [size]*[size]; индекс = y*size + x. 0 — пусто.
  /// Публично для рендера (читать через [tileAt]).
  late List<int> grid;

  /// Накопленные очки за партию.
  int score = 0;

  /// Достигнута ли уже плитка [winValue] в этой партии.
  bool won = false;

  /// Заново разложить поле: всё очистить, две стартовые плитки, счёт в ноль.
  void reset() {
    grid = List<int>.filled(size * size, 0);
    score = 0;
    won = false;
    _spawnRandomTile();
    _spawnRandomTile();
  }

  int _index(int x, int y) => y * size + x;

  /// Значение плитки в клетке (0 — пусто). Вне поля возвращает 0.
  int tileAt(int x, int y) {
    if (x < 0 || y < 0 || x >= size || y >= size) return 0;
    return grid[_index(x, y)];
  }

  /// Есть ли хоть одна пустая клетка.
  bool get hasEmpty => grid.any((v) => v == 0);

  /// Наибольшая плитка на поле (0, если поле пустое — не бывает после reset).
  int get maxTile => grid.fold(0, max);

  /// Конец игры: нет пустых клеток И нет возможных слияний ни по одной оси.
  bool get isGameOver => !hasEmpty && !_hasAnyMerge();

  /// Выполнить ход в направлении [dir].
  ///
  /// Сдвигает и сливает плитки; если поле изменилось — спавнит новую плитку и
  /// начисляет очки. Возвращает [MoveResult] с описанием изменений (для «сока»).
  /// Если ничего не изменилось — [MoveResult.none] и поле остаётся прежним.
  MoveResult move(SlideDirection dir) {
    final merges = <Merge>[];
    var gained = 0;
    var moved = false;

    // Обрабатываем построчно/постолбцово: каждую «линию» в направлении хода
    // вытягиваем в список «от края направления», схлопываем, кладём обратно.
    for (var i = 0; i < size; i++) {
      final line = _readLine(dir, i);
      final result = _collapse(line);
      gained += result.gained;

      if (!_sameLine(line, result.line)) moved = true;

      // Слияния перевести из «линейных» координат обратно в координаты сетки.
      for (final m in result.merges) {
        final cell = _lineCellToGrid(dir, i, m.index);
        merges.add(Merge(x: cell.x, y: cell.y, value: m.value));
      }

      _writeLine(dir, i, result.line);
    }

    if (!moved) return MoveResult.none();

    score += gained;

    final reached2048 = !won && merges.any((m) => m.value >= winValue);
    if (reached2048) won = true;

    final spawn = _spawnRandomTile();

    return MoveResult(
      moved: true,
      merges: merges,
      spawned: spawn,
      gained: gained,
      reached2048: reached2048,
    );
  }

  // ── Внутреннее: работа с одной линией ──────────────────────────────────────

  /// Прочитать i-ю линию в порядке «от края направления к центру».
  ///
  /// Для left — строка слева направо; right — строка справа налево; up —
  /// столбец сверху вниз; down — столбец снизу вверх. Так схлопывание всегда
  /// идёт к началу списка (к краю), и логика слияния общая для всех направлений.
  List<int> _readLine(SlideDirection dir, int i) {
    final line = <int>[];
    for (var k = 0; k < size; k++) {
      final cell = _lineCellToGrid(dir, i, k);
      line.add(grid[_index(cell.x, cell.y)]);
    }
    return line;
  }

  /// Записать линию обратно (в том же порядке, что и [_readLine]).
  void _writeLine(SlideDirection dir, int i, List<int> line) {
    for (var k = 0; k < size; k++) {
      final cell = _lineCellToGrid(dir, i, k);
      grid[_index(cell.x, cell.y)] = line[k];
    }
  }

  /// Перевод позиции в линии [k] (0 — у края направления) в координаты сетки
  /// для линии номер [i].
  Point<int> _lineCellToGrid(SlideDirection dir, int i, int k) {
    switch (dir) {
      case SlideDirection.left:
        return Point(k, i);
      case SlideDirection.right:
        return Point(size - 1 - k, i);
      case SlideDirection.up:
        return Point(i, k);
      case SlideDirection.down:
        return Point(i, size - 1 - k);
    }
  }

  /// Схлопнуть одну линию к краю (началу списка): убрать нули, слить равные
  /// соседние пары (каждая плитка — максимум одно слияние), снова дополнить
  /// нулями до [size]. Возвращает новую линию, очки и индексы слияний.
  _LineResult _collapse(List<int> line) {
    final compact = [
      for (final v in line)
        if (v != 0) v,
    ];

    final out = <int>[];
    final merges = <_LineMerge>[];
    var gained = 0;

    for (var j = 0; j < compact.length; j++) {
      if (j + 1 < compact.length && compact[j] == compact[j + 1]) {
        final merged = compact[j] * 2;
        out.add(merged);
        gained += merged;
        merges.add(_LineMerge(index: out.length - 1, value: merged));
        j++; // следующий элемент уже поглощён — пропускаем
      } else {
        out.add(compact[j]);
      }
    }

    while (out.length < size) {
      out.add(0);
    }

    return _LineResult(line: out, merges: merges, gained: gained);
  }

  bool _sameLine(List<int> a, List<int> b) {
    for (var k = 0; k < size; k++) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  // ── Внутреннее: спавн и проверка слияний ───────────────────────────────────

  /// Поставить новую плитку (2 с вер. 90%, 4 с 10%) в случайную пустую клетку.
  /// Возвращает описание появившейся плитки или null, если пустых клеток нет.
  Spawn? _spawnRandomTile() {
    final empties = <int>[];
    for (var idx = 0; idx < grid.length; idx++) {
      if (grid[idx] == 0) empties.add(idx);
    }
    if (empties.isEmpty) return null;

    final idx = empties[_rng.nextInt(empties.length)];
    final value = _rng.nextDouble() < 0.9 ? 2 : 4;
    grid[idx] = value;
    return Spawn(x: idx % size, y: idx ~/ size, value: value);
  }

  /// Есть ли хоть одна пара равных соседей (по горизонтали или вертикали) —
  /// т.е. возможен ли вообще какой-то ход слиянием.
  bool _hasAnyMerge() {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final v = grid[_index(x, y)];
        if (v == 0) continue;
        if (x + 1 < size && grid[_index(x + 1, y)] == v) return true;
        if (y + 1 < size && grid[_index(x, y + 1)] == v) return true;
      }
    }
    return false;
  }
}

/// Слияние внутри линии: позиция в выходной линии и итоговое значение.
class _LineMerge {
  const _LineMerge({required this.index, required this.value});
  final int index;
  final int value;
}

/// Результат схлопывания одной линии.
class _LineResult {
  const _LineResult({
    required this.line,
    required this.merges,
    required this.gained,
  });
  final List<int> line;
  final List<_LineMerge> merges;
  final int gained;
}
