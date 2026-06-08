import 'dart:math';

/// Сколько цветов пуйо в игре. Цвет кодируется int 0..colorCount-1,
/// чтобы логика не зависела от палитры (её задаст слой рендера).
const int puyoColorCount = 4;

/// Ориентация спутника относительно оси пары.
/// Поворот CW идёт по кругу up -> right -> down -> left.
enum PuyoRotation {
  up(Point(0, -1)),
  right(Point(1, 0)),
  down(Point(0, 1)),
  left(Point(-1, 0));

  const PuyoRotation(this.delta);

  /// Смещение спутника от оси.
  final Point<int> delta;

  /// Следующая ориентация по часовой стрелке.
  PuyoRotation get cw =>
      PuyoRotation.values[(index + 1) % PuyoRotation.values.length];
}

/// Падающая пара пуйо: ось (axisX, axisY), цвет оси, цвет спутника и поворот.
/// Спутник стоит в клетке axis + rotation.delta.
class PuyoPair {
  const PuyoPair({
    required this.axisX,
    required this.axisY,
    required this.axisColor,
    required this.satelliteColor,
    this.rotation = PuyoRotation.up,
  });

  final int axisX;
  final int axisY;
  final int axisColor;
  final int satelliteColor;
  final PuyoRotation rotation;

  /// Позиция спутника на доске.
  Point<int> get satellite =>
      Point(axisX + rotation.delta.x, axisY + rotation.delta.y);

  /// Позиция оси на доске.
  Point<int> get axis => Point(axisX, axisY);

  PuyoPair copyWith({int? axisX, int? axisY, PuyoRotation? rotation}) =>
      PuyoPair(
        axisX: axisX ?? this.axisX,
        axisY: axisY ?? this.axisY,
        axisColor: axisColor,
        satelliteColor: satelliteColor,
        rotation: rotation ?? this.rotation,
      );
}

/// Одна лопнувшая клетка: её позиция и цвет (для частиц «в цвет»).
class PoppedCell {
  const PoppedCell(this.x, this.y, this.color);

  final int x;
  final int y;
  final int color;
}

/// Одна волна цепочки: что лопнуло на этом звене, его множитель и очки.
/// Звенья нумеруются с 1; чем дальше по цепочке — тем больше множитель.
class ChainWave {
  const ChainWave({
    required this.chain,
    required this.popped,
    required this.multiplier,
    required this.gained,
  });

  /// Номер звена цепочки (1 — первое срабатывание).
  final int chain;

  /// Все клетки, лопнувшие в этой волне (могут быть нескольких групп/цветов).
  final List<PoppedCell> popped;

  /// Множитель за номер звена цепочки (растёт от волны к волне).
  final int multiplier;

  /// Очки, начисленные этой волной.
  final int gained;

  /// Сколько пуйо лопнуло в волне.
  int get count => popped.length;
}

/// Итог фиксации пары — список волн цепочки + флаг конца игры.
/// Это данные для «сока»: частицы по [ChainWave.popped] и попапы по очкам.
class PuyoLockResult {
  const PuyoLockResult({
    required this.waves,
    required this.gained,
    required this.gameOver,
  });

  /// Волны цепочки по порядку срабатывания. Пусто — ничего не лопнуло.
  final List<ChainWave> waves;

  /// Суммарные очки за всю фиксацию.
  final int gained;

  /// true, если новая пара не помещается (переполнение стартовой колонки).
  final bool gameOver;

  /// Длина цепочки (число волн).
  int get chainLength => waves.length;
}

/// Чистая логика «Puyo Puyo» без рендера и Flutter-зависимостей — тестируемая.
/// Рендер и «сок» живут в Flame-слое и читают публичные поля доски/пары.
class PuyoPuyoLogic {
  PuyoPuyoLogic({Random? random}) : _rng = random ?? Random() {
    reset();
  }

  /// Ширина поля в клетках.
  static const int cols = 6;

  /// Высота поля в клетках.
  static const int rows = 12;

  /// Минимальный размер одноцветной группы, которая лопается.
  static const int popThreshold = 4;

  /// Столбец, над которым появляется ось новой пары (стартовая колонка).
  static const int spawnColumn = 2;

  final Random _rng;

  /// board[y][x] — цвет (int) закреплённого пуйо или null. y растёт вниз.
  late List<List<int?>> board;

  /// Текущая падающая пара (null после game over).
  PuyoPair? current;

  /// Цвета следующей пары: [цвет оси, цвет спутника].
  late List<int> next;

  int score = 0;

  /// Число лопнувших пуйо за игру (для статистики/рендера).
  int popped = 0;

  /// Длина самой длинной цепочки за игру.
  int maxChain = 0;

  bool dead = false;

  void reset() {
    board = List.generate(rows, (_) => List<int?>.filled(cols, null));
    score = 0;
    popped = 0;
    maxChain = 0;
    dead = false;
    next = _drawColors();
    _spawn();
  }

  /// Случайная пара цветов для следующей фигуры.
  List<int> _drawColors() =>
      [_rng.nextInt(puyoColorCount), _rng.nextInt(puyoColorCount)];

  /// Появление новой пары сверху стартовой колонки.
  /// Если её клетки заняты — игра окончена.
  void _spawn() {
    final colors = next;
    next = _drawColors();
    // Ось внизу (y=1), спутник над ней (y=0) — пара входит вертикально.
    final pair = PuyoPair(
      axisX: spawnColumn,
      axisY: 1,
      axisColor: colors[0],
      satelliteColor: colors[1],
    );
    if (_collides(pair)) {
      current = null;
      dead = true;
    } else {
      current = pair;
    }
  }

  /// Клетка вне поля по бокам/снизу или занята? (сверху, y<0, допускается).
  bool _cellBlocked(int x, int y) {
    if (x < 0 || x >= cols || y >= rows) return true;
    if (y < 0) return false;
    return board[y][x] != null;
  }

  bool _collides(PuyoPair p) {
    if (_cellBlocked(p.axisX, p.axisY)) return true;
    final s = p.satellite;
    return _cellBlocked(s.x, s.y);
  }

  bool _tryReplace(PuyoPair moved) {
    if (_collides(moved)) return false;
    current = moved;
    return true;
  }

  bool moveLeft() {
    if (dead || current == null) return false;
    return _tryReplace(current!.copyWith(axisX: current!.axisX - 1));
  }

  bool moveRight() {
    if (dead || current == null) return false;
    return _tryReplace(current!.copyWith(axisX: current!.axisX + 1));
  }

  /// Поворот по часовой с «отбойниками»: если спутник упирается в стену/пол,
  /// пробуем сдвинуть всю пару на 1 клетку, чтобы поворот удался.
  bool rotateCW() {
    if (dead || current == null) return false;
    final r = current!.rotation.cw;
    const kicks = [Point(0, 0), Point(1, 0), Point(-1, 0), Point(0, -1)];
    for (final k in kicks) {
      final p = current!.copyWith(
        axisX: current!.axisX + k.x,
        axisY: current!.axisY + k.y,
        rotation: r,
      );
      if (!_collides(p)) {
        current = p;
        return true;
      }
    }
    return false;
  }

  /// Мягкий сброс на клетку. Возвращает [PuyoLockResult], если пара села.
  PuyoLockResult? softDrop() {
    if (dead || current == null) return null;
    final moved = current!.copyWith(axisY: current!.axisY + 1);
    if (_tryReplace(moved)) {
      score += 1;
      return null;
    }
    return _lock();
  }

  /// Гравитация: шаг пары вниз. [PuyoLockResult] при фиксации, иначе null.
  PuyoLockResult? gravityTick() {
    if (dead || current == null) return null;
    final moved = current!.copyWith(axisY: current!.axisY + 1);
    if (_tryReplace(moved)) return null;
    return _lock();
  }

  /// Жёсткий сброс до упора. Всегда фиксирует.
  PuyoLockResult? hardDrop() {
    if (dead || current == null) return null;
    while (true) {
      final moved = current!.copyWith(axisY: current!.axisY + 1);
      if (!_tryReplace(moved)) break;
    }
    return _lock();
  }

  /// Фиксация пары: рассыпаем оба пуйо по столбцам, затем считаем цепочку.
  PuyoLockResult _lock() {
    final p = current!;
    // Оба пуйо падают каждый в своём столбце — пара может распасться.
    // Если спутник выше оси и в одном столбце, кладём ось первой, чтобы
    // порядок укладки был «снизу вверх».
    final cellsToPlace = <_PlacedPuyo>[
      _PlacedPuyo(p.axisX, p.axisY, p.axisColor),
      _PlacedPuyo(p.satellite.x, p.satellite.y, p.satelliteColor),
    ]..sort((a, b) => b.y.compareTo(a.y)); // ниже (больший y) — первым

    for (final cell in cellsToPlace) {
      _dropIntoColumn(cell.x, cell.color);
    }

    final waves = _resolveChains();

    var gained = 0;
    for (final w in waves) {
      gained += w.gained;
    }
    score += gained;
    if (waves.length > maxChain) maxChain = waves.length;

    current = null;
    _spawn();

    return PuyoLockResult(waves: waves, gained: gained, gameOver: dead);
  }

  /// Уронить одиночный пуйо цвета [color] в столбец [x] до опоры.
  /// Пуйо, упавший целиком выше поля (нет места), молча отбрасывается —
  /// переполнение ловится отдельно при спавне следующей пары.
  void _dropIntoColumn(int x, int color) {
    for (var y = rows - 1; y >= 0; y--) {
      if (board[y][x] == null) {
        board[y][x] = color;
        return;
      }
    }
  }

  /// Считает цепочку: повторяет «лопнуть группы ≥4 -> обвалить столбцы»,
  /// пока что-то лопается. Возвращает волны по порядку.
  List<ChainWave> _resolveChains() {
    final waves = <ChainWave>[];
    var chain = 0;
    while (true) {
      final groups = _findPopGroups();
      if (groups.isEmpty) break;
      chain++;

      final cells = <PoppedCell>[];
      for (final g in groups) {
        for (final pt in g) {
          final color = board[pt.y][pt.x]!;
          cells.add(PoppedCell(pt.x, pt.y, color));
          board[pt.y][pt.x] = null;
        }
      }
      popped += cells.length;

      // Растущий множитель за номер звена — фишка Puyo: 1, 8, 16, 32, ...
      final multiplier = chain == 1 ? 1 : 1 << (chain - 1);
      // Базовые очки = число лопнувших * 10, усиленные множителем звена.
      final gained = cells.length * 10 * multiplier;

      waves.add(
        ChainWave(
          chain: chain,
          popped: cells,
          multiplier: multiplier,
          gained: gained,
        ),
      );

      _applyGravity();
    }
    return waves;
  }

  /// Находит все одноцветные 4-связные группы размером >= [popThreshold].
  List<List<Point<int>>> _findPopGroups() {
    final visited = List.generate(rows, (_) => List<bool>.filled(cols, false));
    final groups = <List<Point<int>>>[];

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final color = board[y][x];
        if (color == null || visited[y][x]) continue;

        // BFS по 4-связности одного цвета.
        final group = <Point<int>>[];
        final queue = <Point<int>>[Point(x, y)];
        visited[y][x] = true;
        while (queue.isNotEmpty) {
          final cur = queue.removeLast();
          group.add(cur);
          for (final d in const [
            Point(0, -1),
            Point(0, 1),
            Point(-1, 0),
            Point(1, 0),
          ]) {
            final nx = cur.x + d.x;
            final ny = cur.y + d.y;
            if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
            if (visited[ny][nx]) continue;
            if (board[ny][nx] != color) continue;
            visited[ny][nx] = true;
            queue.add(Point(nx, ny));
          }
        }

        if (group.length >= popThreshold) groups.add(group);
      }
    }
    return groups;
  }

  /// Гравитация по столбцам: пуйо проваливаются вниз, заполняя пустоты.
  void _applyGravity() {
    for (var x = 0; x < cols; x++) {
      var write = rows - 1;
      for (var y = rows - 1; y >= 0; y--) {
        final c = board[y][x];
        if (c != null) {
          board[write][x] = c;
          if (write != y) board[y][x] = null;
          write--;
        }
      }
    }
  }
}

/// Вспомогательная пара «координата + цвет» для укладки при фиксации.
class _PlacedPuyo {
  const _PlacedPuyo(this.x, this.y, this.color);

  final int x;
  final int y;
  final int color;
}
