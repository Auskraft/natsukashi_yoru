import 'dart:math';

/// Одна переключённая ходом клетка: её координаты и НОВОЕ состояние (вкл/выкл).
/// Нужна слою рендера, чтобы «вспыхнуть» именно затронутыми клетками и понять,
/// какого они теперь цвета (зажглись или погасли).
class ToggledCell {
  const ToggledCell(this.x, this.y, this.on);

  final int x;
  final int y;

  /// Состояние клетки ПОСЛЕ переключения: true — горит, false — погасла.
  final bool on;

  @override
  String toString() => 'ToggledCell($x,$y,${on ? 'on' : 'off'})';
}

/// Итог одного хода [LightsOutLogic.tap] — данные для «сока» и счётчика.
///
/// Описывает, ЧТО изменилось за тап: какие клетки переключились (крест из
/// центра и ортогональных соседей, обрезанный по краям), стал ли ход
/// засчитанным (валидный тап по полю) и достигнута ли победа этим ходом.
class TapResult {
  TapResult({
    required this.applied,
    required this.toggled,
    required this.won,
  });

  /// Пустой исход — тап вне поля или после победы. Ничего не изменилось,
  /// ход не засчитан.
  factory TapResult.empty() =>
      TapResult(applied: false, toggled: const [], won: false);

  /// Был ли тап валидным (по клетке поля в активной партии) и засчитан как ход.
  final bool applied;

  /// Переключённые этим ходом клетки (центр + ортогональные соседи) с их
  /// новым состоянием. Пусто при [applied] == false.
  final List<ToggledCell> toggled;

  /// Достигнута ли победа этим ходом (все клетки погасли).
  final bool won;

  /// Сколько клеток переключилось (3 в углу, 4 у края, 5 в центре).
  int get affected => toggled.length;
}

/// Чистая логика «Lights Out» без рендера и Flutter/Flame-зависимостей —
/// тестируемая. Поле [size]×[size] лампочек (вкл/выкл). Тап инвертирует клетку
/// и её ортогональных соседей («плюс»). Цель — погасить все.
///
/// Старт генерируется заведомо РЕШАЕМЫМ и не пустым: от полностью погашенного
/// поля применяется набор случайных тапов (через инъектированный [Random]) —
/// это гарантирует существование решения и непустой стартовый узор.
///
/// Состояние ([grid], [won], [moves]) публично читаемо для слоя рендера; «сок»
/// питается из [TapResult].
class LightsOutLogic {
  LightsOutLogic({
    this.size = 5,
    this.scramble = 6,
    Random? random,
  })  : assert(size > 0, 'размер поля должен быть положительным'),
        assert(scramble > 0, 'нужно хотя бы одно перемешивающее нажатие'),
        _rng = random ?? Random() {
    reset();
  }

  /// Сторона квадратного поля.
  final int size;

  /// Сколько случайных тапов применяется к погашенному полю при генерации.
  final int scramble;

  final Random _rng;

  /// grid[y][x] — горит ли лампочка. Публично для рендера.
  late List<List<bool>> grid;

  bool _won = false;
  int _moves = 0;

  /// Победа: все лампочки погашены.
  bool get won => _won;

  /// Сколько ходов сделано в текущей партии (засчитанных тапов).
  int get moves => _moves;

  /// Состояние клетки (горит ли). Вне поля — false.
  bool isOn(int x, int y) => _inBounds(x, y) && grid[y][x];

  /// Сколько лампочек сейчас горит — для HUD/победы.
  int get litCount {
    var n = 0;
    for (final row in grid) {
      for (final on in row) {
        if (on) n++;
      }
    }
    return n;
  }

  /// Сбросить партию: сгенерировать новый решаемый пазл и обнулить ходы.
  void reset() {
    grid = List.generate(size, (_) => List.filled(size, false));
    _moves = 0;
    _won = false;
    _scramble();
  }

  bool _inBounds(int x, int y) => x >= 0 && y >= 0 && x < size && y < size;

  /// Переключить клетку (x, y) и её ортогональных соседей, БЕЗ учёта ходов и
  /// победы. Возвращает список переключённых клеток с их новым состоянием
  /// (крест, обрезанный по краям поля). Общая «механика плюса» для тапа игрока
  /// и для генератора.
  List<ToggledCell> _flipCross(int x, int y) {
    const deltas = [
      Point(0, 0),
      Point(1, 0),
      Point(-1, 0),
      Point(0, 1),
      Point(0, -1),
    ];
    final out = <ToggledCell>[];
    for (final d in deltas) {
      final nx = x + d.x;
      final ny = y + d.y;
      if (!_inBounds(nx, ny)) continue;
      final next = !grid[ny][nx];
      grid[ny][nx] = next;
      out.add(ToggledCell(nx, ny, next));
    }
    return out;
  }

  /// Тап игрока по клетке (x, y). Правила:
  /// - вне поля или после победы → пустой исход (ход не засчитан);
  /// - иначе инвертируем крест (центр + 4 ортогональных соседа, по краям
  ///   меньше), увеличиваем счётчик ходов;
  /// - если все клетки погасли → победа.
  TapResult tap(int x, int y) {
    if (_won || !_inBounds(x, y)) return TapResult.empty();

    final toggled = _flipCross(x, y);
    _moves++;

    final justWon = litCount == 0;
    _won = justWon;
    return TapResult(applied: true, toggled: toggled, won: justWon);
  }

  /// Сгенерировать решаемый стартовый узор: от погашенного поля применяем
  /// [scramble] случайных «крестов». Любая комбинация крестов решаема (повтор
  /// тех же тапов гасит поле), поэтому решение гарантированно существует.
  ///
  /// Если жребий выпал так, что поле оказалось полностью погашенным (узор
  /// «схлопнулся»), повторяем перемешивание — старт обязан быть не пустым.
  void _scramble() {
    do {
      for (final row in grid) {
        row.fillRange(0, size, false);
      }
      for (var i = 0; i < scramble; i++) {
        _flipCross(_rng.nextInt(size), _rng.nextInt(size));
      }
    } while (litCount == 0);
  }
}
