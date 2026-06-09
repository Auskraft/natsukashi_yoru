import 'dart:math';

/// Чистая логика «1010!» — без рендера и зависимостей от Flutter/Flame,
/// поэтому полностью тестируема. Поле, лоток и счёт читаются публично;
/// «сок» (частицы/попапы/шейк) живёт в слое Flame и питается [PlaceResult].
///
/// Правила: поле 10×10 (клетка занята/пуста). В лотке три фигуры-полимино.
/// Игрок ставит фигуру в любое свободное место; затем все полностью
/// заполненные строки И столбцы очищаются одновременно. Когда лоток пуст —
/// раздаётся новый набор из трёх. Игра кончается, когда ни одна из
/// оставшихся в лотке фигур не помещается никуда.

/// Семь видов «кирпичей» (палитра выбирается слоем рендера, не здесь).
enum BlockColor { teal, yellow, violet, green, pink, blue, orange }

/// Форма полимино: клетки в своей локальной рамке (минимум по x и y = 0).
/// Хранит ширину/высоту рамки, чтобы слой ввода мог центрировать перетаскивание.
class BlockShape {
  const BlockShape(this.cells, this.width, this.height);

  /// Локальные клетки фигуры (dx, dy), оба >= 0.
  final List<Point<int>> cells;

  /// Габариты рамки фигуры в клетках.
  final int width;
  final int height;

  /// Сколько клеток занимает фигура (1..5).
  int get size => cells.length;
}

/// Построить [BlockShape] из «сырых» клеток: нормализует к (0,0) и считает рамку.
BlockShape _shape(List<Point<int>> raw) {
  final minX = raw.map((p) => p.x).reduce(min);
  final minY = raw.map((p) => p.y).reduce(min);
  final cells = [for (final p in raw) Point(p.x - minX, p.y - minY)];
  final w = cells.map((p) => p.x).reduce(max) + 1;
  final h = cells.map((p) => p.y).reduce(max) + 1;
  return BlockShape(cells, w, h);
}

/// Каталог фигур «1010!»: палочки 1..5, квадраты 2×2 и 3×3, уголки L (2×2 и 3×3,
/// во всех четырёх ориентациях). Состав классический для жанра.
final List<BlockShape> kBlockShapes = _buildShapes();

List<BlockShape> _buildShapes() {
  final shapes = <BlockShape>[];

  // Палочки по горизонтали и вертикали, длиной 1..5.
  for (var len = 1; len <= 5; len++) {
    shapes.add(_shape([for (var i = 0; i < len; i++) Point(i, 0)]));
    if (len > 1) {
      shapes.add(_shape([for (var i = 0; i < len; i++) Point(0, i)]));
    }
  }

  // Квадраты.
  shapes.add(_shape(const [Point(0, 0), Point(1, 0), Point(0, 1), Point(1, 1)]));
  shapes.add(_shape(const [
    Point(0, 0), Point(1, 0), Point(2, 0),
    Point(0, 1), Point(1, 1), Point(2, 1),
    Point(0, 2), Point(1, 2), Point(2, 2),
  ]));

  // Уголки L 2×2 (три клетки) во всех четырёх поворотах.
  shapes.add(_shape(const [Point(0, 0), Point(0, 1), Point(1, 1)]));
  shapes.add(_shape(const [Point(1, 0), Point(0, 1), Point(1, 1)]));
  shapes.add(_shape(const [Point(0, 0), Point(1, 0), Point(0, 1)]));
  shapes.add(_shape(const [Point(0, 0), Point(1, 0), Point(1, 1)]));

  // Уголки L 3×3 (пять клеток) во всех четырёх поворотах.
  shapes.add(_shape(const [
    Point(0, 0), Point(0, 1), Point(0, 2), Point(1, 2), Point(2, 2),
  ]));
  shapes.add(_shape(const [
    Point(2, 0), Point(2, 1), Point(0, 2), Point(1, 2), Point(2, 2),
  ]));
  shapes.add(_shape(const [
    Point(0, 0), Point(1, 0), Point(2, 0), Point(0, 1), Point(0, 2),
  ]));
  shapes.add(_shape(const [
    Point(0, 0), Point(1, 0), Point(2, 0), Point(2, 1), Point(2, 2),
  ]));

  return shapes;
}

/// Фигура в лотке: форма + цвет. Размещённая фигура из лотка убирается.
class TrayPiece {
  const TrayPiece(this.shape, this.color);

  final BlockShape shape;
  final BlockColor color;

  int get size => shape.size;
}

/// Итог постановки фигуры [BlockPuzzleLogic.place] — данные для счёта и «сока».
///
/// Несёт, что именно изменилось: какие клетки фигура заняла, какие строки и
/// столбцы очистились (вместе с цветами этих клеток до очистки — для частиц
/// «в цвет»), сколько начислено очков и не наступил ли конец игры.
class PlaceResult {
  PlaceResult({
    required this.placed,
    required this.placedCells,
    required this.clearedRows,
    required this.clearedCols,
    required this.clearedCells,
    required this.gained,
    required this.newTray,
    required this.gameOver,
  });

  /// Состоялась ли постановка (false — клетки заняты/вне поля/нет такой фигуры).
  final bool placed;

  /// Клетки поля, которые заняла фигура (для всплеска при установке).
  final List<Point<int>> placedCells;

  /// Индексы очищенных строк (0..size-1).
  final List<int> clearedRows;

  /// Индексы очищенных столбцов (0..size-1).
  final List<int> clearedCols;

  /// Клетки (позиция + цвет до очистки) всех очищенных линий, без дублей на
  /// пересечениях — для частиц «в цвет».
  final List<ClearedCell> clearedCells;

  /// Очки за ход: клетки фигуры + бонус за линии (растёт с числом линий разом).
  final int gained;

  /// Стал ли лоток пустым и был добран новый набор из трёх фигур.
  final bool newTray;

  /// Не осталось ли ходов после постановки (конец игры).
  final bool gameOver;

  /// Сколько всего линий (строк + столбцов) очищено за ход.
  int get linesCleared => clearedRows.length + clearedCols.length;
}

/// Одна очищенная клетка: позиция на поле и её цвет до очистки.
class ClearedCell {
  const ClearedCell(this.pos, this.color);

  final Point<int> pos;
  final BlockColor color;

  @override
  String toString() => 'ClearedCell(${pos.x},${pos.y},$color)';
}

/// Чистая логика «1010!».
class BlockPuzzleLogic {
  BlockPuzzleLogic({Random? random}) : _rng = random ?? Random() {
    reset();
  }

  /// Сторона квадратного поля.
  static const int size = 10;

  /// Сколько фигур в наборе лотка.
  static const int traySize = 3;

  final Random _rng;

  /// board[y][x] — цвет занятой клетки или null, если пусто.
  late List<List<BlockColor?>> board;

  /// Лоток: ровно [traySize] слотов, занятый — [TrayPiece], израсходованный — null.
  late List<TrayPiece?> tray;

  /// Накопленные очки за партию.
  int score = 0;

  /// Кончились ли ходы (ни одна фигура лотка никуда не помещается).
  bool dead = false;

  /// Заново: пустое поле, свежий набор лотка, обнулённый счёт.
  void reset() {
    board = List.generate(size, (_) => List<BlockColor?>.filled(size, null));
    score = 0;
    dead = false;
    tray = List<TrayPiece?>.filled(traySize, null);
    _refillTray();
  }

  /// Цвет клетки или null вне поля / если пусто.
  BlockColor? cellAt(int x, int y) {
    if (x < 0 || y < 0 || x >= size || y >= size) return null;
    return board[y][x];
  }

  /// Сколько фигур ещё лежит в лотке.
  int get piecesLeft => tray.where((p) => p != null).length;

  /// Можно ли поставить фигуру [piece] так, чтобы её локальная клетка (0,0)
  /// легла в клетку поля (anchorX, anchorY): все клетки в поле и свободны.
  bool canPlaceShape(BlockShape piece, int anchorX, int anchorY) {
    for (final c in piece.cells) {
      final x = anchorX + c.x;
      final y = anchorY + c.y;
      if (x < 0 || y < 0 || x >= size || y >= size) return false;
      if (board[y][x] != null) return false;
    }
    return true;
  }

  /// Помещается ли фигура хоть куда-нибудь на текущем поле.
  bool canPlaceAnywhere(BlockShape piece) {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (canPlaceShape(piece, x, y)) return true;
      }
    }
    return false;
  }

  /// Поставить фигуру из слота [trayIndex] якорной клеткой в (anchorX, anchorY).
  ///
  /// Если постановка валидна: занимает клетки, очищает все полностью заполненные
  /// строки и столбцы одновременно, начисляет очки, при опустевшем лотке
  /// добирает новый набор, пересчитывает конец игры. Иначе — [PlaceResult] с
  /// `placed == false` и без побочных эффектов.
  PlaceResult place(int trayIndex, int anchorX, int anchorY) {
    if (trayIndex < 0 || trayIndex >= traySize) return _noPlace();
    final piece = tray[trayIndex];
    if (piece == null) return _noPlace();
    if (!canPlaceShape(piece.shape, anchorX, anchorY)) return _noPlace();

    // Занимаем клетки.
    final placedCells = <Point<int>>[];
    for (final c in piece.shape.cells) {
      final x = anchorX + c.x;
      final y = anchorY + c.y;
      board[y][x] = piece.color;
      placedCells.add(Point(x, y));
    }
    tray[trayIndex] = null;

    // Находим полные строки и столбцы (до очистки — оцениваем по текущей доске).
    final fullRows = <int>[];
    for (var y = 0; y < size; y++) {
      if (_rowFull(y)) fullRows.add(y);
    }
    final fullCols = <int>[];
    for (var x = 0; x < size; x++) {
      if (_colFull(x)) fullCols.add(x);
    }

    // Снимаем цвета очищаемых клеток (без дублей на пересечениях строк/столбцов).
    final clearedCells = <ClearedCell>[];
    final seen = <int>{};
    void collect(int x, int y) {
      final key = y * size + x;
      if (seen.add(key)) {
        clearedCells.add(ClearedCell(Point(x, y), board[y][x]!));
      }
    }

    for (final y in fullRows) {
      for (var x = 0; x < size; x++) {
        collect(x, y);
      }
    }
    for (final x in fullCols) {
      for (var y = 0; y < size; y++) {
        collect(x, y);
      }
    }

    // Очищаем — строки и столбцы одновременно (по собранному множеству).
    for (final c in clearedCells) {
      board[c.pos.y][c.pos.x] = null;
    }

    // Очки: клетки фигуры + бонус за линии (квадратично растёт с числом линий).
    final lines = fullRows.length + fullCols.length;
    final gained = piece.size + _lineBonus(lines);
    score += gained;

    // Новый набор, когда лоток опустел.
    final emptied = piecesLeft == 0;
    if (emptied) _refillTray();

    // Конец игры — если ни одна оставшаяся фигура никуда не лезет.
    dead = !_anyMoveLeft();

    return PlaceResult(
      placed: true,
      placedCells: placedCells,
      clearedRows: fullRows,
      clearedCols: fullCols,
      clearedCells: clearedCells,
      gained: gained,
      newTray: emptied,
      gameOver: dead,
    );
  }

  /// Бонус за одновременно очищенные [lines] линий: 0,10,30,60,100,150…
  /// (растёт быстрее, чем линейно — поощряет «мульти-клиры»).
  static int _lineBonus(int lines) {
    if (lines <= 0) return 0;
    return 10 * lines * (lines + 1) ~/ 2;
  }

  bool _rowFull(int y) {
    for (var x = 0; x < size; x++) {
      if (board[y][x] == null) return false;
    }
    return true;
  }

  bool _colFull(int x) {
    for (var y = 0; y < size; y++) {
      if (board[y][x] == null) return false;
    }
    return true;
  }

  /// Есть ли ход хоть для одной из оставшихся в лотке фигур.
  bool _anyMoveLeft() {
    for (final p in tray) {
      if (p != null && canPlaceAnywhere(p.shape)) return true;
    }
    return false;
  }

  PlaceResult _noPlace() => PlaceResult(
        placed: false,
        placedCells: const [],
        clearedRows: const [],
        clearedCols: const [],
        clearedCells: const [],
        gained: 0,
        newTray: false,
        gameOver: dead,
      );

  /// Заполнить все слоты лотка новыми случайными фигурами и пересчитать `dead`.
  void _refillTray() {
    for (var i = 0; i < traySize; i++) {
      tray[i] = _randomPiece();
    }
    dead = !_anyMoveLeft();
  }

  TrayPiece _randomPiece() {
    final shape = kBlockShapes[_rng.nextInt(kBlockShapes.length)];
    final color = BlockColor.values[_rng.nextInt(BlockColor.values.length)];
    return TrayPiece(shape, color);
  }
}
