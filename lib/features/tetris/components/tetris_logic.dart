import 'dart:math';

/// Семь тетрамино.
enum Tetromino { i, o, t, s, z, j, l }

class _Shape {
  const _Shape(this.size, this.cells);

  /// Сторона квадрата, в котором заданы клетки (нужно для вращения).
  final int size;
  final List<Point<int>> cells;
}

/// Базовые формы (поворот 0) в своём квадрате size×size.
const Map<Tetromino, _Shape> _shapes = {
  Tetromino.i: _Shape(4, [Point(0, 1), Point(1, 1), Point(2, 1), Point(3, 1)]),
  Tetromino.o: _Shape(2, [Point(0, 0), Point(1, 0), Point(0, 1), Point(1, 1)]),
  Tetromino.t: _Shape(3, [Point(1, 0), Point(0, 1), Point(1, 1), Point(2, 1)]),
  Tetromino.s: _Shape(3, [Point(1, 0), Point(2, 0), Point(0, 1), Point(1, 1)]),
  Tetromino.z: _Shape(3, [Point(0, 0), Point(1, 0), Point(1, 1), Point(2, 1)]),
  Tetromino.j: _Shape(3, [Point(0, 0), Point(0, 1), Point(1, 1), Point(2, 1)]),
  Tetromino.l: _Shape(3, [Point(2, 0), Point(0, 1), Point(1, 1), Point(2, 1)]),
};

int tetrominoSize(Tetromino t) => _shapes[t]!.size;

/// Клетки фигуры для заданного поворота (CW), относительно её квадрата.
List<Point<int>> tetrominoCells(Tetromino t, [int rot = 0]) {
  final s = _shapes[t]!;
  final n = s.size;
  var cells = s.cells;
  for (var r = 0; r < (rot % 4); r++) {
    cells = cells.map((p) => Point(n - 1 - p.y, p.x)).toList(); // поворот 90° CW
  }
  return cells;
}

/// Фигура на доске: тип, позиция квадрата (x,y) и поворот.
class Piece {
  Piece(this.type, this.x, this.y, [this.rot = 0]);

  final Tetromino type;
  final int x;
  final int y;
  final int rot;

  /// Абсолютные клетки на доске.
  List<Point<int>> cells() =>
      tetrominoCells(type, rot).map((p) => Point(p.x + x, p.y + y)).toList();
}

/// Итог фиксации фигуры — данные для счёта и «сока».
class LockResult {
  LockResult({
    required this.clearedRows,
    required this.gained,
    required this.gameOver,
    required this.tetris,
    required this.backToBack,
  });

  final List<int> clearedRows;
  final int gained;
  final bool gameOver;
  final bool tetris;
  final bool backToBack;

  int get cleared => clearedRows.length;
}

/// Чистая логика «Tetris» без рендера и Flutter-зависимостей — тестируемая.
class TetrisLogic {
  TetrisLogic({Random? random}) : _rng = random ?? Random() {
    reset();
  }

  static const int cols = 10;
  static const int rows = 20;

  final Random _rng;

  /// board[y][x] — тип закреплённой клетки или null.
  late List<List<Tetromino?>> board;
  late Piece current;
  late Tetromino next;
  final List<Tetromino> _bag = [];

  int score = 0;
  int lines = 0;
  int level = 1;
  bool dead = false;
  bool _b2b = false; // была ли предыдущая зачистка «Тетрисом»

  void reset() {
    board = List.generate(rows, (_) => List<Tetromino?>.filled(cols, null));
    score = 0;
    lines = 0;
    level = 1;
    dead = false;
    _b2b = false;
    _bag.clear();
    next = _draw();
    _spawn();
  }

  // 7-bag: каждые 7 фигур — все типы по разу, в случайном порядке (честно).
  Tetromino _draw() {
    if (_bag.isEmpty) {
      _bag.addAll(Tetromino.values);
      _bag.shuffle(_rng);
    }
    return _bag.removeLast();
  }

  void _spawn() {
    final t = next;
    next = _draw();
    final cells = tetrominoCells(t);
    final minY = cells.map((p) => p.y).reduce(min);
    final n = tetrominoSize(t);
    current = Piece(t, (cols - n) ~/ 2, -minY);
    if (_collides(current)) dead = true;
  }

  bool _collides(Piece p) {
    for (final c in p.cells()) {
      if (c.x < 0 || c.x >= cols || c.y >= rows) return true;
      if (c.y >= 0 && board[c.y][c.x] != null) return true;
    }
    return false;
  }

  bool _tryShift(int dx, int dy) {
    final moved = Piece(current.type, current.x + dx, current.y + dy, current.rot);
    if (_collides(moved)) return false;
    current = moved;
    return true;
  }

  bool moveLeft() => !dead && _tryShift(-1, 0);
  bool moveRight() => !dead && _tryShift(1, 0);

  /// Поворот по часовой с простыми «отбойниками» от стен.
  bool rotateCW() {
    if (dead) return false;
    final r = (current.rot + 1) % 4;
    for (final kick in const [0, -1, 1, -2, 2]) {
      final p = Piece(current.type, current.x + kick, current.y, r);
      if (!_collides(p)) {
        current = p;
        return true;
      }
    }
    return false;
  }

  /// Мягкий сброс на клетку. Возвращает [LockResult], если приземлились.
  LockResult? softDrop() {
    if (dead) return null;
    if (_tryShift(0, 1)) {
      score += 1;
      return null;
    }
    return _lock();
  }

  /// Гравитация: шаг вниз. [LockResult] при фиксации, иначе null.
  LockResult? gravityTick() {
    if (dead) return null;
    if (_tryShift(0, 1)) return null;
    return _lock();
  }

  /// Жёсткий сброс до упора. Всегда фиксирует.
  LockResult hardDrop() {
    var dist = 0;
    while (_tryShift(0, 1)) {
      dist++;
    }
    score += dist * 2;
    return _lock();
  }

  /// Куда упадёт текущая фигура (для «призрака»).
  Piece ghost() {
    var g = current;
    while (true) {
      final p = Piece(g.type, g.x, g.y + 1, g.rot);
      if (_collides(p)) return g;
      g = p;
    }
  }

  LockResult _lock() {
    for (final c in current.cells()) {
      if (c.y >= 0 && c.y < rows && c.x >= 0 && c.x < cols) {
        board[c.y][c.x] = current.type;
      }
    }

    final clearedRows = <int>[];
    final kept = <List<Tetromino?>>[];
    for (var y = 0; y < rows; y++) {
      if (board[y].every((c) => c != null)) {
        clearedRows.add(y);
      } else {
        kept.add(board[y]);
      }
    }
    while (kept.length < rows) {
      kept.insert(0, List<Tetromino?>.filled(cols, null));
    }
    board = kept;

    final count = clearedRows.length;
    final isTetris = count == 4;
    var gained = const [0, 100, 300, 500, 800][count] * level;
    var b2b = false;
    if (isTetris && _b2b) {
      gained = (gained * 1.5).round(); // бонус за back-to-back Тетрис
      b2b = true;
    }
    if (count > 0) {
      _b2b = isTetris; // зачистка без Тетриса сбрасывает серию
    }

    score += gained;
    lines += count;
    level = 1 + lines ~/ 10;

    _spawn();

    return LockResult(
      clearedRows: clearedRows,
      gained: gained,
      gameOver: dead,
      tetris: isTetris,
      backToBack: b2b,
    );
  }
}
