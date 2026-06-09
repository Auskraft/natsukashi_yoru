import 'dart:math';

/// Направление хода игрока и его смещение по сетке.
enum SokoDir {
  up(Point(0, -1)),
  down(Point(0, 1)),
  left(Point(-1, 0)),
  right(Point(1, 0));

  const SokoDir(this.delta);

  /// Смещение клетки при ходе в эту сторону.
  final Point<int> delta;
}

/// Тип тайла поля.
///
/// «Цель» и «ящик» — независимые сущности: ящик может стоять на полу или на
/// цели. Чтобы рендеру/логике было удобно, мы кодируем комбинации одним enum:
/// [boxOnGoal] — ящик стоит на цели (зачтённый), [goal] — пустая цель.
enum SokoTile {
  /// Стена — непроходима, в неё нельзя ходить и толкать.
  wall,

  /// Пустой пол.
  floor,

  /// Пустая цель (пол с меткой назначения).
  goal,

  /// Ящик на полу (ещё не на цели).
  box,

  /// Ящик, стоящий на цели (зачтённый).
  boxOnGoal;

  /// Есть ли на этой клетке ящик (на полу или на цели).
  bool get hasBox => this == SokoTile.box || this == SokoTile.boxOnGoal;

  /// Является ли клетка целью (пустой или с ящиком).
  bool get isGoalSquare => this == SokoTile.goal || this == SokoTile.boxOnGoal;

  /// Можно ли войти/толкнуть ящик на эту клетку (пол или пустая цель).
  bool get isWalkable => this == SokoTile.floor || this == SokoTile.goal;
}

/// Результат одного хода [SokobanLogic.move] — описывает, ЧТО изменилось,
/// чтобы слой «сока» знал, что показать (частицы/попапы/вспышки).
enum SokoMoveKind {
  /// Ход невозможен (упёрлись в стену / в ящик у стены / в два ящика подряд /
  /// после победы). Состояние не изменилось, счётчик ходов не растёт.
  blocked,

  /// Игрок просто прошёл на свободную клетку (без толкания).
  walked,

  /// Игрок толкнул ящик; ящик НЕ встал на цель этим ходом.
  pushed,

  /// Игрок толкнул ящик, и ящик ВСТАЛ на цель этим ходом (акцент-вспышка).
  pushedOntoGoal,

  /// Игрок толкнул ящик, и ящик СОШЁЛ с цели этим ходом.
  pushedOffGoal,
}

/// Полный исход хода: вид события и затронутые клетки (для эффектов).
class SokoMoveResult {
  const SokoMoveResult({
    required this.kind,
    required this.player,
    this.box,
    required this.solved,
  });

  /// Невозможный ход — ничего не поменялось.
  const SokoMoveResult.blocked()
      : kind = SokoMoveKind.blocked,
        player = const Point(-1, -1),
        box = null,
        solved = false;

  /// Что произошло за ход.
  final SokoMoveKind kind;

  /// Новая позиция игрока после хода (для [SokoMoveKind.blocked] не валидна).
  final Point<int> player;

  /// Новая позиция толкнутого ящика, либо null если ящик не двигали.
  final Point<int>? box;

  /// Стал ли уровень решён ИМЕННО этим ходом (все ящики на целях).
  final bool solved;

  /// Двигался ли ящик этим ходом.
  bool get movedBox => box != null;
}

/// Чистая логика «Сокобана» без рендера и Flutter/Flame-зависимостей —
/// поэтому легко тестируется. Поле — сетка [SokoTile]; позиция игрока хранится
/// отдельно (под игроком — обычный пол или цель). «Сок» питается из
/// [SokoMoveResult].
class SokobanLogic {
  /// Создаёт логику и загружает первый уровень.
  ///
  /// [random] инъектируется для детерминизма (в текущих правилах прямой
  /// случайности нет, но конструктор-контракт единый со всеми играми; поле
  /// сохранено для возможной будущей рандомизации стартового уровня).
  SokobanLogic({Random? random, List<List<String>>? levels})
      : _rng = random ?? Random(),
        _levels = levels ?? kSokobanLevels {
    assert(_levels.isNotEmpty, 'нужен хотя бы один уровень');
    reset();
  }

  // ignore: unused_field — зарезервировано под будущую рандомизацию уровней.
  final Random _rng;
  final List<List<String>> _levels;

  /// board[y][x] — тайл поля. Публично для рендера.
  late List<List<SokoTile>> board;

  /// Позиция игрока.
  late Point<int> player;

  int _cols = 0;
  int _rows = 0;
  int _levelIndex = 0;
  int _moves = 0;
  int _boxesOnGoal = 0;
  int _goalCount = 0;
  bool _solved = false;

  /// Ширина текущего уровня в клетках.
  int get cols => _cols;

  /// Высота текущего уровня в клетках.
  int get rows => _rows;

  /// Индекс текущего уровня (0-based).
  int get levelIndex => _levelIndex;

  /// Человеко-понятный номер уровня (1-based).
  int get levelNumber => _levelIndex + 1;

  /// Всего встроенных уровней.
  int get levelCount => _levels.length;

  /// Сколько ходов сделано на текущем уровне.
  int get moves => _moves;

  /// Сколько всего целей на уровне.
  int get goalCount => _goalCount;

  /// Сколько ящиков уже стоит на целях.
  int get boxesOnGoal => _boxesOnGoal;

  /// Решён ли текущий уровень (все ящики на целях).
  bool get solved => _solved;

  /// Есть ли следующий уровень после текущего.
  bool get hasNextLevel => _levelIndex < _levels.length - 1;

  /// Тайл в (x, y); за пределами поля считаем стеной.
  SokoTile tileAt(int x, int y) {
    if (!_inBounds(x, y)) return SokoTile.wall;
    return board[y][x];
  }

  bool _inBounds(int x, int y) => x >= 0 && y >= 0 && x < _cols && y < _rows;

  /// Сбросить на первый уровень.
  void reset() {
    _levelIndex = 0;
    _loadLevel(_levelIndex);
  }

  /// Перезапустить текущий уровень (сброс ходов и расстановки).
  void restartLevel() {
    _loadLevel(_levelIndex);
  }

  /// Перейти на следующий уровень. Если его нет — остаётся на текущем и
  /// возвращает false.
  bool nextLevel() {
    if (!hasNextLevel) return false;
    _levelIndex++;
    _loadLevel(_levelIndex);
    return true;
  }

  /// Сделать ход в направлении [dir]. Правила:
  /// - после победы ход игнорируется (blocked);
  /// - впереди стена → blocked;
  /// - впереди ящик: толкаем, только если за ящиком свободно (пол/цель);
  ///   нельзя толкать в стену и нельзя толкать два ящика подряд → blocked;
  /// - иначе игрок проходит на свободную клетку.
  /// Счётчик ходов растёт на любом НЕ-blocked ходе.
  SokoMoveResult move(SokoDir dir) {
    if (_solved) return const SokoMoveResult.blocked();

    final nx = player.x + dir.delta.x;
    final ny = player.y + dir.delta.y;
    final ahead = tileAt(nx, ny);

    if (ahead == SokoTile.wall) return const SokoMoveResult.blocked();

    if (ahead.hasBox) {
      // За ящиком — клетка, куда он поедет.
      final bx = nx + dir.delta.x;
      final by = ny + dir.delta.y;
      final beyond = tileAt(bx, by);
      // Толкать можно только на пол/цель: не в стену и не в другой ящик.
      if (!beyond.isWalkable) return const SokoMoveResult.blocked();

      final wasOnGoal = ahead == SokoTile.boxOnGoal;
      final nowOnGoal = beyond == SokoTile.goal;

      // Сдвигаем ящик: освобождаем его прежнюю клетку, занимаем целевую.
      board[ny][nx] = wasOnGoal ? SokoTile.goal : SokoTile.floor;
      board[by][bx] = nowOnGoal ? SokoTile.boxOnGoal : SokoTile.box;

      if (wasOnGoal && !nowOnGoal) _boxesOnGoal--;
      if (!wasOnGoal && nowOnGoal) _boxesOnGoal++;

      player = Point(nx, ny);
      _moves++;

      final solvedNow = _goalCount > 0 && _boxesOnGoal == _goalCount;
      _solved = solvedNow;

      final SokoMoveKind kind;
      if (nowOnGoal && !wasOnGoal) {
        kind = SokoMoveKind.pushedOntoGoal;
      } else if (!nowOnGoal && wasOnGoal) {
        kind = SokoMoveKind.pushedOffGoal;
      } else {
        kind = SokoMoveKind.pushed;
      }

      return SokoMoveResult(
        kind: kind,
        player: player,
        box: Point(bx, by),
        solved: solvedNow,
      );
    }

    // Свободная клетка (пол или пустая цель) — просто шаг.
    player = Point(nx, ny);
    _moves++;
    return SokoMoveResult(
      kind: SokoMoveKind.walked,
      player: player,
      solved: false,
    );
  }

  /// Разобрать ASCII-карту уровня в сетку тайлов и позицию игрока.
  ///
  /// Символы карты:
  /// - `#` стена, ` ` (пробел) пол, `.` цель,
  /// - `$` ящик, `*` ящик-на-цели,
  /// - `@` игрок, `+` игрок-на-цели.
  /// Строки выравниваются по самой длинной (недостающее — пол).
  void _loadLevel(int index) {
    final map = _levels[index];
    _rows = map.length;
    _cols = map.fold(0, (m, row) => max(m, row.length));

    board = List.generate(
      _rows,
      (_) => List.filled(_cols, SokoTile.floor, growable: false),
    );

    _moves = 0;
    _boxesOnGoal = 0;
    _goalCount = 0;
    _solved = false;
    Point<int>? start;

    for (var y = 0; y < _rows; y++) {
      final row = map[y];
      for (var x = 0; x < _cols; x++) {
        final ch = x < row.length ? row[x] : ' ';
        switch (ch) {
          case '#':
            board[y][x] = SokoTile.wall;
          case '.':
            board[y][x] = SokoTile.goal;
            _goalCount++;
          case r'$':
            board[y][x] = SokoTile.box;
          case '*':
            board[y][x] = SokoTile.boxOnGoal;
            _goalCount++;
            _boxesOnGoal++;
          case '@':
            board[y][x] = SokoTile.floor;
            start = Point(x, y);
          case '+':
            board[y][x] = SokoTile.goal;
            _goalCount++;
            start = Point(x, y);
          default:
            board[y][x] = SokoTile.floor;
        }
      }
    }

    assert(start != null, 'на карте уровня нет игрока (@ или +)');
    player = start ?? const Point(0, 0);
    // Согласованность карты: число ящиков должно равняться числу целей.
    _solved = _goalCount > 0 && _boxesOnGoal == _goalCount;
  }
}

/// Встроенные уровни «Сокобана» по возрастанию сложности (компактные ≤10×10).
///
/// Каждый уровень — список строк (ASCII-карта). Символы см. в `_loadLevel`.
/// Все уровни проверены на решаемость; в комментарии — пример решения
/// (последовательность ходов игрока), чтобы правки не сломали проходимость.
const List<List<String>> kSokobanLevels = [
  // 1 — знакомство: один ящик, прямой толчок вправо.
  // @(1,1) box(2,1) goal(3,1). Решение: R (box 2→3 = цель).
  [
    '#####',
    '#@\$.#',
    '#####',
  ],
  // 2 — толчок по двум клеткам.
  // @(1,1) box(2,1) goal(4,1). Решение: R, R.
  [
    '######',
    '#@\$ .#',
    '######',
  ],
  // 3 — два ящика, два прямых толчка.
  // @(1,2) boxes (2,1),(2,3) goals (4,1),(4,3).
  // Решение: U,R,R (верхний ящик 2→4), D,D,R,R (нижний ящик 2→4).
  [
    '######',
    '# \$ .#',
    '#@   #',
    '# \$ .#',
    '######',
  ],
  // 4 — поворот: толкнуть ящик вниз, обойти и дотолкнуть влево.
  // @(3,1) box(3,2) goal(1,3). Решение: D, R, D, L, L.
  [
    '######',
    '#  @ #',
    '#  \$ #',
    '#.   #',
    '######',
  ],
  // 5 — три ящика в ряд, три цели в ряд (склад).
  // @(1,1) boxes (1,2),(2,2),(3,2) goals (1,4),(2,4),(3,4).
  // Каждый ящик толкается строго вниз на 2 клетки.
  [
    '######',
    '#@   #',
    '#\$\$\$ #',
    '#    #',
    '#... #',
    '######',
  ],
  // 6 — финал: четыре ящика двумя парами, каждый — прямой толчок вниз.
  // Пары разнесены зазором по центру, чтобы не мешать друг другу.
  // boxes (1,3),(2,3),(5,3),(6,3) → goals (1,4),(2,4),(5,4),(6,4).
  [
    '########',
    '#  @   #',
    '#      #',
    '#\$\$  \$\$#',
    '#..  ..#',
    '#      #',
    '########',
  ],
];
