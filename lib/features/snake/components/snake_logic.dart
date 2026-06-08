import 'dart:math';

/// Направление движения и его смещение по сетке.
enum Direction {
  up(Point(0, -1)),
  down(Point(0, 1)),
  left(Point(-1, 0)),
  right(Point(1, 0));

  const Direction(this.delta);
  final Point<int> delta;

  bool isOpposite(Direction other) =>
      delta.x == -other.delta.x && delta.y == -other.delta.y;
}

/// Результат одного шага симуляции.
enum StepOutcome { moved, ate, died }

/// Чистая логика «змейки» без рендера и Flutter-зависимостей —
/// поэтому легко тестируется. Рендер и «сок» живут в Flame-слое.
class SnakeLogic {
  SnakeLogic({required this.cols, required this.rows, Random? random})
      : _rng = random ?? Random() {
    reset();
  }

  final int cols;
  final int rows;
  final Random _rng;

  /// Голова — первый элемент.
  late List<Point<int>> snake;
  late Point<int> food;
  late Direction _dir;
  Direction? _pendingDir;
  bool dead = false;

  Direction get direction => _dir;
  Point<int> get head => snake.first;
  int get length => snake.length;

  void reset() {
    final cx = cols ~/ 2;
    final cy = rows ~/ 2;
    snake = [Point(cx, cy), Point(cx - 1, cy), Point(cx - 2, cy)];
    _dir = Direction.right;
    _pendingDir = null;
    dead = false;
    _placeFood();
  }

  /// Поставить поворот в очередь (применяется на следующем [step]).
  /// Разворот на 180° и повтор текущего направления игнорируются.
  void steer(Direction d) {
    final base = _pendingDir ?? _dir;
    if (d == base || d.isOpposite(base)) return;
    _pendingDir = d;
  }

  StepOutcome step() {
    if (dead) return StepOutcome.died;

    if (_pendingDir != null) {
      _dir = _pendingDir!;
      _pendingDir = null;
    }

    final next = Point(head.x + _dir.delta.x, head.y + _dir.delta.y);

    // Столкновение со стеной.
    if (next.x < 0 || next.y < 0 || next.x >= cols || next.y >= rows) {
      dead = true;
      return StepOutcome.died;
    }

    final ate = next == food;
    // Если не едим — хвост освободит клетку, значит наступить на неё можно.
    final body = ate ? snake : snake.sublist(0, snake.length - 1);
    if (body.contains(next)) {
      dead = true;
      return StepOutcome.died;
    }

    snake.insert(0, next);
    if (ate) {
      _placeFood();
      return StepOutcome.ate;
    }
    snake.removeLast();
    return StepOutcome.moved;
  }

  void _placeFood() {
    final occupied = snake.toSet();
    final free = <Point<int>>[];
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final p = Point(x, y);
        if (!occupied.contains(p)) free.add(p);
      }
    }
    if (free.isEmpty) {
      // Поле заполнено целиком — победа; некуда ставить еду.
      dead = true;
      return;
    }
    food = free[_rng.nextInt(free.length)];
  }
}
