import 'dart:math';

/// Цвет пузыря. Пять видов; хранится как enum, чтобы слой Flame сам выбрал
/// палитру (никаких Color здесь — логика остаётся чистой и тестируемой).
enum Bubble { red, yellow, green, blue, purple }

/// Координата ячейки в сотах: [row] сверху вниз, [col] слева направо внутри ряда.
///
/// Ряды смещены через один (odd-row offset): чётные ряды стоят «как есть»,
/// нечётные — сдвинуты вправо на пол-ячейки. Поэтому соседи зависят от чётности
/// ряда. Класс — самостоятельный ключ (нужен для Set/Map в BFS), с равенством
/// по обоим полям.
class HexCell {
  const HexCell(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is HexCell && other.row == row && other.col == col;

  @override
  int get hashCode => row * 1000003 ^ col;

  @override
  String toString() => 'HexCell($row,$col)';
}

/// Один лопнувший пузырь: его ячейка и цвет (до удаления). Нужен слою рендера
/// для частиц «в цвет» и попапов в точке взрыва.
class PoppedBubble {
  const PoppedBubble(this.cell, this.bubble);

  final HexCell cell;
  final Bubble bubble;

  @override
  String toString() => 'PoppedBubble($cell,$bubble)';
}

/// Один упавший («висевший») пузырь: ячейка и цвет на момент отрыва. Падшие
/// пузыри дороже лопнутых — слой рендера анимирует их падение и салютует.
class DroppedBubble {
  const DroppedBubble(this.cell, this.bubble);

  final HexCell cell;
  final Bubble bubble;

  @override
  String toString() => 'DroppedBubble($cell,$bubble)';
}

/// Итог одного выстрела [BubbleShooterLogic.fire].
///
/// Описывает всё, что изменилось, — достаточно для «сока» (частицы/попапы/
/// падение/тряска) и для начисления очков на слое Flame.
class ShotResult {
  ShotResult({
    required this.landed,
    required this.color,
    required this.cleared,
    required this.dropped,
    required this.gained,
    required this.gameOver,
  });

  /// Ячейка, в которую прилип выпущенный пузырь (его исходная позиция).
  /// null только если выстрел вообще не нашёл места (теоретически не бывает —
  /// верхний ряд всегда даёт точку прилипания).
  final HexCell? landed;

  /// Цвет выпущенного пузыря.
  final Bubble color;

  /// Лопнувшие пузыри (кластер ≥3, включая прилипший) — для частиц/попапов.
  /// Пусто, если кластер меньше трёх (пузырь просто остался на поле).
  final List<PoppedBubble> cleared;

  /// «Висящие» пузыри, осыпавшиеся после лопания кластера, — для анимации
  /// падения. Пусто, если ничего не оторвалось.
  final List<DroppedBubble> dropped;

  /// Очки за выстрел: лопнутые + упавшие (упавшие дороже).
  final int gained;

  /// Достиг ли какой-либо пузырь нижней линии после выстрела — конец партии.
  final bool gameOver;

  /// Удалось ли вообще прилепить пузырь к полю.
  bool get didLand => landed != null;

  /// Сколько всего пузырей убрано за ход (лопнуто + упало).
  int get removed => cleared.length + dropped.length;
}

/// Чистая логика «Bubble Shooter» без рендера и Flutter/Flame-зависимостей —
/// поэтому легко тестируется.
///
/// Соты пузырей сверху (ряды со смещением), снизу пушка с текущим и следующим
/// цветом. [fire] трассирует выстрел по углу с отскоком от боковых стен,
/// прилепляет пузырь к ближайшей валидной ячейке у препятствия, лопает кластер
/// ≥3 одного цвета (BFS по соседям-соты) и роняет «висящие» пузыри (не связанные
/// BFS с верхним рядом). Поле, счёт, пушка и исход хода читаются публично.
class BubbleShooterLogic {
  BubbleShooterLogic({
    this.cols = 11,
    this.rows = 14,
    this.startRows = 5,
    Random? random,
  })  : assert(cols >= 2),
        assert(rows >= startRows + 2),
        _rng = random ?? Random() {
    reset();
  }

  /// Число столбцов в ЧЁТНОМ ряду. Нечётные ряды содержат [cols] - 1 столбец
  /// (классическое смещение сот), что даёт ровные края слева и справа.
  final int cols;

  /// Полная высота поля в рядах (включая «мёртвую зону» снизу до линии проигрыша).
  final int rows;

  /// Сколько верхних рядов заполнено цветными пузырями на старте.
  final int startRows;

  final Random _rng;

  /// Ширина поля в «диаметрах пузыря» (диаметр = 1). Чётный ряд занимает [cols]
  /// ячеек; левый край ячейки 0 в нём — x=0, правый край последней — x=cols.
  double get fieldWidth => cols.toDouble();

  /// Радиус пузыря в тех же единицах (диаметр = 1).
  static const double radius = 0.5;

  /// Высота ряда: соты упакованы плотно, центры соседних рядов по вертикали
  /// отстоят на sqrt(3)/2 диаметра.
  static final double rowHeight = sqrt(3) / 2;

  /// Сетка пузырей: grid[row][col] — цвет или null (пусто). Длина ряда зависит
  /// от чётности (см. [colsInRow]).
  late List<List<Bubble?>> grid;

  /// Текущий цвет в пушке (вылетит следующим выстрелом).
  late Bubble current;

  /// Следующий цвет (показывается игроку как «на очереди»).
  late Bubble next;

  /// Накопленные очки за партию.
  int score = 0;

  /// Партия окончена (пузырь достиг нижней линии).
  bool gameOver = false;

  /// Очки за один лопнутый пузырь.
  static const int popPoints = 10;

  /// Очки за один упавший («висевший») пузырь — дороже лопнутого.
  static const int dropPoints = 20;

  /// Сколько столбцов в ряду [row]: чётный — [cols], нечётный — [cols] - 1.
  int colsInRow(int row) => row.isEven ? cols : cols - 1;

  /// Заново раздать поле: верхние [startRows] рядов случайных цветов, остальное
  /// пусто; обновить пушку и обнулить счёт.
  void reset() {
    score = 0;
    gameOver = false;
    grid = List.generate(
      rows,
      (row) => List<Bubble?>.filled(colsInRow(row), null),
    );
    for (var row = 0; row < startRows; row++) {
      for (var col = 0; col < colsInRow(row); col++) {
        grid[row][col] = _randomBubble();
      }
    }
    current = _randomBubbleOnField();
    next = _randomBubbleOnField();
  }

  /// Цвет в ячейке или null (пусто/вне поля).
  Bubble? bubbleAt(int row, int col) {
    if (row < 0 || row >= rows) return null;
    if (col < 0 || col >= colsInRow(row)) return null;
    return grid[row][col];
  }

  bool _inBounds(HexCell c) =>
      c.row >= 0 && c.row < rows && c.col >= 0 && c.col < colsInRow(c.row);

  bool _isEmpty(HexCell c) => _inBounds(c) && grid[c.row][c.col] == null;

  bool _isFilled(HexCell c) => _inBounds(c) && grid[c.row][c.col] != null;

  /// Центр ячейки в координатах поля (диаметр = 1). Нечётные ряды сдвинуты
  /// вправо на пол-ячейки, поэтому их крайние ячейки не упираются в стены.
  Point<double> centerOf(HexCell c) {
    final x = c.row.isEven ? c.col + radius : c.col + 1.0;
    final y = c.row * rowHeight + radius;
    return Point(x, y);
  }

  /// Шесть соседей ячейки в сотах. Набор зависит от чётности ряда: при смещении
  /// «верх-лево/верх-право» (и низ) попадают в разные столбцы.
  List<HexCell> neighbors(HexCell c) {
    final r = c.row;
    final col = c.col;
    if (r.isEven) {
      return [
        HexCell(r, col - 1),
        HexCell(r, col + 1),
        HexCell(r - 1, col - 1),
        HexCell(r - 1, col),
        HexCell(r + 1, col - 1),
        HexCell(r + 1, col),
      ];
    }
    return [
      HexCell(r, col - 1),
      HexCell(r, col + 1),
      HexCell(r - 1, col),
      HexCell(r - 1, col + 1),
      HexCell(r + 1, col),
      HexCell(r + 1, col + 1),
    ];
  }

  /// Только существующие соседи (внутри поля).
  Iterable<HexCell> _validNeighbors(HexCell c) =>
      neighbors(c).where(_inBounds);

  // ── Трассировка выстрела ───────────────────────────────────────────────────

  /// Сколько шагов трассировки максимум (защита от зацикливания при почти
  /// горизонтальном угле с бесконечными отскоками).
  static const int _maxTraceSteps = 4000;

  /// Шаг трассировки в долях диаметра — мелкий ради точного контакта.
  static const double _traceStep = 0.05;

  /// Оттрассировать выстрел из пушки под углом [angleRad] и вернуть ячейку
  /// прилипания (не меняя поле). Угол отсчитывается от вертикали вверх:
  /// 0 — прямо вверх, отрицательный — влево, положительный — вправо.
  ///
  /// Пузырь летит по прямой, отражаясь от боковых стен (x ∈ [radius,
  /// fieldWidth - radius]); останавливается при касании верхней границы или
  /// существующего пузыря и прилипает к ближайшей свободной валидной ячейке.
  /// Публичный — слой рендера рисует им предпросмотр траектории/цель.
  HexCell? trace(double angleRad) {
    // Старт — из центра пушки у нижней кромки поля, чуть выше неё.
    var pos = Point<double>(fieldWidth / 2, _cannonY);
    // Направление вверх: dy<0. Угол от вертикали.
    final dir = Point<double>(sin(angleRad), -cos(angleRad));
    final minX = radius;
    final maxX = fieldWidth - radius;

    var vx = dir.x;
    var vy = dir.y;
    // Нормировать на всякий случай (sin/cos уже единичны, но угол может прийти
    // нестрого — оставим устойчивым).
    final len = sqrt(vx * vx + vy * vy);
    if (len == 0) return null;
    vx /= len;
    vy /= len;

    for (var step = 0; step < _maxTraceSteps; step++) {
      var nx = pos.x + vx * _traceStep;
      var ny = pos.y + vy * _traceStep;

      // Отскок от боковых стен: отражаем X и возвращаем точку внутрь.
      if (nx < minX) {
        nx = minX + (minX - nx);
        vx = -vx;
      } else if (nx > maxX) {
        nx = maxX - (nx - maxX);
        vx = -vx;
      }

      final p = Point<double>(nx, ny);

      // Контакт с верхней границей — прилипаем к ближайшей ячейке у верха.
      if (ny <= radius) {
        return _snapTo(p, hitTop: true);
      }

      // Контакт с существующим пузырём — прилипаем рядом.
      if (_hitsBubble(p)) {
        return _snapTo(p, hitTop: false);
      }

      pos = p;
    }
    // Аварийный выход (почти невозможен): прилипнуть к текущей точке.
    return _snapTo(pos, hitTop: pos.y <= radius);
  }

  /// Y-координата центра вылета из пушки — у нижней кромки поля.
  double get _cannonY => rows * rowHeight + radius;

  /// Пересекает ли движущийся пузырь (центр [p], радиус [radius]) какой-либо
  /// существующий пузырь. Контакт — когда расстояние между центрами < диаметра.
  bool _hitsBubble(Point<double> p) {
    // Проверяем только окрестные ряды ради дешевизны.
    final approxRow = (p.y - radius) / rowHeight;
    final rLo = max(0, approxRow.floor() - 2);
    final rHi = min(rows - 1, approxRow.ceil() + 2);
    for (var row = rLo; row <= rHi; row++) {
      for (var col = 0; col < colsInRow(row); col++) {
        if (grid[row][col] == null) continue;
        final c = centerOf(HexCell(row, col));
        final dx = c.x - p.x;
        final dy = c.y - p.y;
        if (dx * dx + dy * dy < 1.0) return true; // диаметр^2 = 1
      }
    }
    return false;
  }

  /// Выбрать свободную ячейку, ближайшую к точке контакта [p].
  ///
  /// Кандидаты — пустые ячейки поля, чьи центры лежат недалеко от [p]; среди них
  /// берём ту, чей центр ближе всего. При [hitTop] гарантируем, что кандидат
  /// есть в самом верхнем ряду. Возвращает null, если свободных ячеек нет вовсе.
  HexCell? _snapTo(Point<double> p, {required bool hitTop}) {
    HexCell? best;
    var bestDist = double.infinity;

    final approxRow = (p.y - radius) / rowHeight;
    final rLo = max(0, approxRow.floor() - 2);
    final rHi = min(rows - 1, approxRow.ceil() + 2);

    for (var row = rLo; row <= rHi; row++) {
      for (var col = 0; col < colsInRow(row); col++) {
        if (grid[row][col] != null) continue;
        final cell = HexCell(row, col);
        // Свободная ячейка валидна как точка прилипания, только если она
        // примыкает к препятствию: к верхнему ряду или к существующему пузырю.
        final adjacentToBubble = _validNeighbors(cell).any(_isFilled);
        final atTop = row == 0;
        if (!adjacentToBubble && !atTop) continue;

        final c = centerOf(cell);
        final dx = c.x - p.x;
        final dy = c.y - p.y;
        final d = dx * dx + dy * dy;
        if (d < bestDist) {
          bestDist = d;
          best = cell;
        }
      }
    }

    // Если не нашли (контакт с верхом, но окрестность занята) — берём ближайшую
    // свободную ячейку верхнего ряда.
    if (best == null && hitTop) {
      for (var col = 0; col < colsInRow(0); col++) {
        if (grid[0][col] != null) continue;
        final cell = HexCell(0, col);
        final c = centerOf(cell);
        final dx = c.x - p.x;
        final d = dx * dx;
        if (d < bestDist) {
          bestDist = d;
          best = cell;
        }
      }
    }
    return best;
  }

  // ── Выстрел ────────────────────────────────────────────────────────────────

  /// Выстрелить текущим цветом под углом [angleRad]. Прилепляет пузырь, лопает
  /// кластер ≥3, роняет «висящие», начисляет очки, сдвигает пушку (current←next,
  /// next←random) и проверяет конец партии. Возвращает [ShotResult].
  ///
  /// Если партия окончена или прилепить некуда — возвращает «пустой» исход без
  /// изменения поля.
  ShotResult fire(double angleRad) {
    final shotColor = current;
    if (gameOver) {
      return ShotResult(
        landed: null,
        color: shotColor,
        cleared: const [],
        dropped: const [],
        gained: 0,
        gameOver: true,
      );
    }

    final cell = trace(angleRad);
    if (cell == null || !_isEmpty(cell)) {
      // Прилепить некуда — ход «вхолостую», но пушку всё равно прокручиваем,
      // чтобы игрок не застрял на одном цвете.
      cycleCannon();
      return ShotResult(
        landed: null,
        color: shotColor,
        cleared: const [],
        dropped: const [],
        gained: 0,
        gameOver: gameOver,
      );
    }

    final result = placeAndResolve(cell, shotColor);
    cycleCannon();
    return result;
  }

  /// Прилепить пузырь цвета [color] в свободную ячейку [cell] и разрешить ход:
  /// лопнуть кластер ≥3 (BFS по соседям-соты через [cell]), уронить «висящие»
  /// (не связанные BFS с верхним рядом), начислить очки и проверить нижнюю
  /// линию. НЕ трогает пушку — отделено от [fire] ради детерминированных тестов
  /// (можно задать точную ячейку и цвет, минуя трассировку и случай).
  ///
  /// Предполагает, что [cell] валидна и пуста; иначе вернёт «пустой» исход.
  ShotResult placeAndResolve(HexCell cell, Bubble color) {
    if (gameOver || !_isEmpty(cell)) {
      return ShotResult(
        landed: null,
        color: color,
        cleared: const [],
        dropped: const [],
        gained: 0,
        gameOver: gameOver,
      );
    }

    grid[cell.row][cell.col] = color;

    // Кластер одного цвета через прилипшую ячейку.
    final cluster = _colorCluster(cell);
    final cleared = <PoppedBubble>[];
    final dropped = <DroppedBubble>[];
    var gained = 0;

    if (cluster.length >= 3) {
      for (final c in cluster) {
        cleared.add(PoppedBubble(c, grid[c.row][c.col]!));
        grid[c.row][c.col] = null;
      }
      gained += cluster.length * popPoints;

      // «Висящие» пузыри: всё, что больше не связано с верхним рядом, падает.
      final floating = _floatingBubbles();
      for (final c in floating) {
        dropped.add(DroppedBubble(c, grid[c.row][c.col]!));
        grid[c.row][c.col] = null;
      }
      gained += floating.length * dropPoints;
    }

    score += gained;

    final over = _reachedBottom();
    if (over) gameOver = true;

    return ShotResult(
      landed: cell,
      color: color,
      cleared: cleared,
      dropped: dropped,
      gained: gained,
      gameOver: over,
    );
  }

  /// Прокрутить пушку: current←next, next←случайный цвет с поля. Публичный, т.к.
  /// слой Flame применяет ход по прилёте снаряда отдельно от трассировки.
  void cycleCannon() {
    current = next;
    next = _randomBubbleOnField();
  }

  // ── BFS-механики ────────────────────────────────────────────────────────────

  /// Связная (по соседям-соты) группа ячеек одного цвета, содержащая [start].
  /// [start] должна быть заполнена. BFS останавливается на других цветах/пустоте.
  Set<HexCell> _colorCluster(HexCell start) {
    final color = grid[start.row][start.col];
    final seen = <HexCell>{start};
    final queue = <HexCell>[start];
    while (queue.isNotEmpty) {
      final c = queue.removeLast();
      for (final n in _validNeighbors(c)) {
        if (seen.contains(n)) continue;
        if (grid[n.row][n.col] != color) continue;
        seen.add(n);
        queue.add(n);
      }
    }
    return seen;
  }

  /// Все «висящие» пузыри — заполненные ячейки, не связанные BFS (по любым
  /// цветам) с верхним рядом (row == 0). Именно они осыпаются после лопания.
  Set<HexCell> _floatingBubbles() {
    // 1) Достижимое от верхнего ряда множество заполненных ячеек.
    final anchored = <HexCell>{};
    final queue = <HexCell>[];
    for (var col = 0; col < colsInRow(0); col++) {
      if (grid[0][col] != null) {
        final c = HexCell(0, col);
        anchored.add(c);
        queue.add(c);
      }
    }
    while (queue.isNotEmpty) {
      final c = queue.removeLast();
      for (final n in _validNeighbors(c)) {
        if (anchored.contains(n)) continue;
        if (grid[n.row][n.col] == null) continue;
        anchored.add(n);
        queue.add(n);
      }
    }

    // 2) Всё заполненное, чего нет в anchored, — висит.
    final floating = <HexCell>{};
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < colsInRow(row); col++) {
        if (grid[row][col] == null) continue;
        final c = HexCell(row, col);
        if (!anchored.contains(c)) floating.add(c);
      }
    }
    return floating;
  }

  /// Достиг ли какой-либо заполненный пузырь нижней линии — последнего ряда.
  bool _reachedBottom() {
    final last = rows - 1;
    for (var col = 0; col < colsInRow(last); col++) {
      if (grid[last][col] != null) return true;
    }
    return false;
  }

  // ── Утилиты ──────────────────────────────────────────────────────────────

  /// Какие цвета сейчас присутствуют на поле (для пушки: не выдавать цвет,
  /// которого уже нет, — иначе им нечего лопать).
  Set<Bubble> colorsOnField() {
    final set = <Bubble>{};
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < colsInRow(row); col++) {
        final b = grid[row][col];
        if (b != null) set.add(b);
      }
    }
    return set;
  }

  /// Случайный цвет из присутствующих на поле; если поле пусто — любой.
  Bubble _randomBubbleOnField() {
    final present = colorsOnField().toList();
    if (present.isEmpty) return _randomBubble();
    return present[_rng.nextInt(present.length)];
  }

  Bubble _randomBubble() => Bubble.values[_rng.nextInt(Bubble.values.length)];

  /// Сколько пузырей сейчас на поле (для статистики/HUD).
  int get bubbleCount {
    var n = 0;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < colsInRow(row); col++) {
        if (grid[row][col] != null) n++;
      }
    }
    return n;
  }
}
