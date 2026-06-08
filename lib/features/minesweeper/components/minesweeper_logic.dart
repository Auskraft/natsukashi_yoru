import 'dart:math';

/// Видимое состояние клетки на доске.
enum CellState { hidden, revealed, flagged }

/// Одна клетка поля. Содержимое (мина / число соседей) хранится всегда —
/// слой рендера сам решает, что показывать в зависимости от [state].
class Cell {
  Cell();

  /// Видимость клетки для игрока.
  CellState state = CellState.hidden;

  /// Есть ли под клеткой мина.
  bool mine = false;

  /// Сколько мин в 8 соседях (0..8). Валидно после расстановки мин.
  int adjacent = 0;
}

/// Раскрытая клетка для анимации: позиция и число соседних мин.
/// Используется слоем «сока», чтобы знать, какие плитки «откинуть» и какое
/// число на них показать (0 — пустая, 1..8 — с подсказкой).
class RevealedCell {
  const RevealedCell(this.x, this.y, this.adjacent);

  final int x;
  final int y;
  final int adjacent;
}

/// Итог одного хода [MinesweeperLogic.reveal] — данные для частиц и попапов.
///
/// Описывает, ЧТО изменилось за ход: какие клетки раскрылись (и их числа),
/// попали ли по мине, какие мины при этом вскрылись, и достигнута ли победа.
class RevealResult {
  RevealResult({
    required this.revealed,
    required this.hitMine,
    required this.explodedMines,
    required this.won,
  });

  /// Пустой исход — клик проигнорирован (по флагу, по уже открытой,
  /// вне поля или после конца игры). Ничего не изменилось.
  factory RevealResult.empty() => RevealResult(
        revealed: const [],
        hitMine: false,
        explodedMines: const [],
        won: false,
      );

  /// Раскрытые этим ходом клетки (одна при числе, целый каскад при нуле).
  final List<RevealedCell> revealed;

  /// Попал ли игрок по мине (проигрыш).
  final bool hitMine;

  /// Позиции мин, вскрытых на проигрыше (все мины поля) — для «бабаха».
  /// Непусто только когда [hitMine] == true.
  final List<Point<int>> explodedMines;

  /// Достигнута ли победа этим ходом (раскрыты все не-минные клетки).
  final bool won;

  /// Размер каскада — сколько клеток раскрылось (для попапа/комбо).
  int get cascade => revealed.length;
}

/// Чистая логика «Сапёра» без рендера и Flutter-зависимостей — тестируемая.
/// Состояние ([board], [won], [lost], [remainingMines]) публично читаемо,
/// чтобы Flame-слой мог его отрисовать; «сок» питается из [RevealResult].
class MinesweeperLogic {
  MinesweeperLogic(this.cols, this.rows, this.mines, {Random? random})
      : assert(cols > 0 && rows > 0, 'размеры поля должны быть положительны'),
        // Безопасная зона 3×3 вокруг первого клика не может содержать мин,
        // поэтому мин не должно быть больше, чем клеток за её пределами.
        assert(mines >= 0 && mines <= cols * rows - 9 || cols * rows < 9,
            'слишком много мин для такого поля'),
        _rng = random ?? Random() {
    reset();
  }

  final int cols;
  final int rows;
  final int mines;
  final Random _rng;

  /// board[y][x] — клетка поля. Публично для рендера.
  late List<List<Cell>> board;

  /// Расставлены ли уже мины (после первого раскрытия).
  bool _minesPlaced = false;
  bool _won = false;
  bool _lost = false;
  int _flags = 0;

  /// Победа: раскрыты все не-минные клетки.
  bool get won => _won;

  /// Проигрыш: раскрыта мина.
  bool get lost => _lost;

  /// Игра завершена (победа или поражение).
  bool get isOver => _won || _lost;

  /// Сколько флагов сейчас выставлено.
  int get flags => _flags;

  /// «Осталось мин» по счётчику: всего мин минус выставленные флаги.
  /// Может быть отрицательным, если флагов поставили больше, чем мин.
  int get remainingMines => mines - _flags;

  Cell cellAt(int x, int y) => board[y][x];

  void reset() {
    board = List.generate(rows, (_) => List.generate(cols, (_) => Cell()));
    _minesPlaced = false;
    _won = false;
    _lost = false;
    _flags = 0;
  }

  bool _inBounds(int x, int y) => x >= 0 && y >= 0 && x < cols && y < rows;

  /// Переключить флаг на скрытой клетке. На раскрытой — игнор.
  /// Возвращает true, если состояние флага реально изменилось.
  bool toggleFlag(int x, int y) {
    if (isOver || !_inBounds(x, y)) return false;
    final c = board[y][x];
    if (c.state == CellState.revealed) return false;
    if (c.state == CellState.flagged) {
      c.state = CellState.hidden;
      _flags--;
    } else {
      c.state = CellState.flagged;
      _flags++;
    }
    return true;
  }

  /// Раскрыть клетку (x, y). Правила:
  /// - по флагу / уже открытой / вне поля / после конца игры — пустой исход;
  /// - первый в партии reveal расставляет мины так, чтобы (x, y) и её 8
  ///   соседей были безопасны;
  /// - мина → проигрыш (исход содержит все мины поля);
  /// - 0 соседних мин → флуд-филл соседей;
  /// - иначе раскрывается одна клетка с числом 1..8;
  /// - если раскрыты все не-минные клетки → победа.
  RevealResult reveal(int x, int y) {
    if (isOver || !_inBounds(x, y)) return RevealResult.empty();
    final c = board[y][x];
    if (c.state != CellState.hidden) return RevealResult.empty();

    // Первый клик безопасен: расставляем мины уже зная (x, y).
    if (!_minesPlaced) _placeMines(x, y);

    // Подрыв.
    if (c.mine) {
      c.state = CellState.revealed;
      _lost = true;
      final exploded = <Point<int>>[];
      for (var yy = 0; yy < rows; yy++) {
        for (var xx = 0; xx < cols; xx++) {
          if (board[yy][xx].mine) exploded.add(Point(xx, yy));
        }
      }
      return RevealResult(
        revealed: [RevealedCell(x, y, c.adjacent)],
        hitMine: true,
        explodedMines: exploded,
        won: false,
      );
    }

    // Безопасное раскрытие: одиночная клетка или флуд-филл при нуле.
    final revealed = <RevealedCell>[];
    _floodReveal(x, y, revealed);

    final justWon = _checkWin();
    _won = justWon;
    return RevealResult(
      revealed: revealed,
      hitMine: false,
      explodedMines: const [],
      won: justWon,
    );
  }

  /// Итеративный флуд-филл (без рекурсии — поле может быть большим).
  /// Раскрывает (sx, sy); если у клетки 0 соседних мин — добавляет в обход
  /// её скрытых не-помеченных соседей. Флагнутые клетки не трогаем.
  void _floodReveal(int sx, int sy, List<RevealedCell> out) {
    final stack = <Point<int>>[Point(sx, sy)];
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final cell = board[p.y][p.x];
      if (cell.state != CellState.hidden) continue;
      cell.state = CellState.revealed;
      out.add(RevealedCell(p.x, p.y, cell.adjacent));
      if (cell.adjacent != 0) continue;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = p.x + dx;
          final ny = p.y + dy;
          if (!_inBounds(nx, ny)) continue;
          if (board[ny][nx].state == CellState.hidden) {
            stack.add(Point(nx, ny));
          }
        }
      }
    }
  }

  /// Расстановка мин ПОСЛЕ первого клика. Запретная зона — сама клетка
  /// (fx, fy) и её 8 соседей (безопасный квадрат 3×3). Затем считаем
  /// числа-подсказки для всех клеток.
  void _placeMines(int fx, int fy) {
    final forbidden = <Point<int>>{};
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final nx = fx + dx;
        final ny = fy + dy;
        if (_inBounds(nx, ny)) forbidden.add(Point(nx, ny));
      }
    }

    // Кандидаты под мины — все клетки вне запретной зоны.
    final candidates = <Point<int>>[];
    for (var yy = 0; yy < rows; yy++) {
      for (var xx = 0; xx < cols; xx++) {
        final p = Point(xx, yy);
        if (!forbidden.contains(p)) candidates.add(p);
      }
    }

    // На случай мелких полей не пытаемся поставить больше мин, чем кандидатов.
    final toPlace = min(mines, candidates.length);
    // Частичный Фишер–Йейтс: тасуем первые toPlace позиций детерминированно.
    for (var i = 0; i < toPlace; i++) {
      final j = i + _rng.nextInt(candidates.length - i);
      final tmp = candidates[i];
      candidates[i] = candidates[j];
      candidates[j] = tmp;
      final m = candidates[i];
      board[m.y][m.x].mine = true;
    }

    // Числа-подсказки.
    for (var yy = 0; yy < rows; yy++) {
      for (var xx = 0; xx < cols; xx++) {
        if (board[yy][xx].mine) continue;
        var n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = xx + dx;
            final ny = yy + dy;
            if (_inBounds(nx, ny) && board[ny][nx].mine) n++;
          }
        }
        board[yy][xx].adjacent = n;
      }
    }

    _minesPlaced = true;
  }

  /// Победа, если КАЖДАЯ не-минная клетка раскрыта.
  bool _checkWin() {
    for (var yy = 0; yy < rows; yy++) {
      for (var xx = 0; xx < cols; xx++) {
        final c = board[yy][xx];
        if (!c.mine && c.state != CellState.revealed) return false;
      }
    }
    return true;
  }
}
