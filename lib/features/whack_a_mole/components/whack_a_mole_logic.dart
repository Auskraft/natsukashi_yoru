import 'dart:math';

/// Тип события, произошедшего на одной норе за тик симуляции.
enum HoleChange { popUp, hide }

/// Изменение состояния одной норы за [WhackAMoleLogic.tick] — данные для «сока»
/// (частицы/попапы): индекс норы и что с ней случилось (крот вылез / спрятался).
class HoleEvent {
  const HoleEvent(this.index, this.change);

  /// Индекс норы 0..count-1 (слева направо, сверху вниз).
  final int index;

  /// Что произошло с норой.
  final HoleChange change;

  @override
  String toString() => 'HoleEvent($index, $change)';
}

/// Исход хода [WhackAMoleLogic.hit] — данные для частиц/попапов и HUD.
///
/// Описывает, ЧТО изменилось от тапа: попал ли игрок по «вылезшему» кроту,
/// сколько начислено очков (с учётом комбо) и каким стало комбо после хода.
class HitResult {
  const HitResult({
    required this.index,
    required this.hit,
    required this.gained,
    required this.combo,
  });

  /// Пустой исход — тап проигнорирован (вне поля или игра не идёт).
  /// Ничего не изменилось, промахом не считается.
  factory HitResult.ignored() =>
      const HitResult(index: -1, hit: false, gained: 0, combo: 0);

  /// Индекс норы, по которой тапнули (-1 для [HitResult.ignored]).
  final int index;

  /// Попал ли тап по «вылезшему» кроту (true) или это промах (false).
  final bool hit;

  /// Начислено очков за ход (0 при промахе/игноре).
  final int gained;

  /// Комбо ПОСЛЕ хода: растёт при попадании, сбрасывается в 0 при промахе.
  final int combo;

  /// Это игнор (тап вне поля / партия не идёт), а не промах.
  bool get ignored => index < 0;
}

/// Состояние одной норы: пуста или крот «наверху» с остатком времени.
class Hole {
  /// Есть ли сейчас крот наверху (доступен для удара).
  bool up = false;

  /// Остаток времени, пока крот наверху (сек). Валидно при [up] == true.
  double remaining = 0;

  void clear() {
    up = false;
    remaining = 0;
  }
}

/// Чистая логика «Whack-a-Mole» без рендера и Flutter/Flame-зависимостей —
/// поэтому легко тестируется. Рендер, таймер партии и «сок» живут в Flame-слое.
///
/// Расписание появления кротов детерминировано по инъектированному [Random]:
/// при [tick] копится таймер спавна; когда он созревает, в случайную свободную
/// нору сажается крот на короткое время. Темп растёт по мере накопления
/// [elapsed] (интервал между появлениями плавно сокращается).
class WhackAMoleLogic {
  WhackAMoleLogic({
    this.cols = 3,
    this.rows = 3,
    Random? random,
  }) : _rng = random ?? Random() {
    holes = List.generate(cols * rows, (_) => Hole());
    reset();
  }

  final int cols;
  final int rows;
  final Random _rng;

  /// Норы по индексам 0..count-1 (строки сверху вниз). Публично для рендера.
  late final List<Hole> holes;

  /// Базовые очки за попадание (далее умножаются на комбо).
  static const int basePoints = 10;

  // Темп появления: интервал между спавнами сокращается от старта к концу
  // по мере роста [elapsed], но не быстрее [_minInterval].
  static const double _startInterval = 0.85;
  static const double _minInterval = 0.32;
  // За сколько секунд игры интервал сходит от старта к минимуму.
  static const double _rampSeconds = 25;

  // Сколько крот сидит наверху; ближе к концу — чуть быстрее прячется.
  static const double _startUpTime = 1.15;
  static const double _minUpTime = 0.7;

  /// Текущее комбо (серия попаданий без промаха). Публично для HUD/«сока».
  int combo = 0;

  /// Сколько всего попаданий за партию (для статистики/HUD).
  int hits = 0;

  /// Сколько всего кротов было упущено (спрятались без удара).
  int misses = 0;

  /// Накопленное игровое время с момента [reset] (сек). Управляет темпом.
  double elapsed = 0;

  double _spawnTimer = 0;

  int get count => holes.length;

  /// Сколько кротов сейчас наверху.
  int get moleCount {
    var n = 0;
    for (final h in holes) {
      if (h.up) n++;
    }
    return n;
  }

  /// Текущий интервал между появлениями — линейно сокращается со временем.
  double get spawnInterval {
    final t = (elapsed / _rampSeconds).clamp(0.0, 1.0);
    return _startInterval + (_minInterval - _startInterval) * t;
  }

  /// Текущее время «наверху» для нового крота — со временем чуть короче.
  double get upTime {
    final t = (elapsed / _rampSeconds).clamp(0.0, 1.0);
    return _startUpTime + (_minUpTime - _startUpTime) * t;
  }

  /// Полный сброс: все норы пусты, счётчики и таймеры обнулены.
  void reset() {
    for (final h in holes) {
      h.clear();
    }
    combo = 0;
    hits = 0;
    misses = 0;
    elapsed = 0;
    // Первый крот появляется не мгновенно, а через половину стартового интервала
    // — даёт игроку миг сориентироваться и делает старт детерминированным.
    _spawnTimer = _startInterval * 0.5;
  }

  /// Продвинуть симуляцию на [dt] секунд. Прячет кротов, у которых вышло время,
  /// и по расписанию (детерминированно по [Random]) сажает новых.
  ///
  /// Возвращает список изменений нор за этот тик (для частиц/попапов): сначала
  /// спрятавшиеся (упущенные) кроты, затем новые появившиеся.
  List<HoleEvent> tick(double dt) {
    if (dt <= 0) return const [];
    elapsed += dt;
    final events = <HoleEvent>[];

    // 1. Прячем кротов, чьё время вышло (это упущенные — промахом игрока их
    //    не считаем, но сбрасываем комбо: зевок ломает серию).
    for (var i = 0; i < holes.length; i++) {
      final h = holes[i];
      if (!h.up) continue;
      h.remaining -= dt;
      if (h.remaining <= 0) {
        h.clear();
        misses++;
        combo = 0;
        events.add(HoleEvent(i, HoleChange.hide));
      }
    }

    // 2. Спавн по таймеру. Цикл (а не один спавн) — на случай крупного dt.
    _spawnTimer -= dt;
    while (_spawnTimer <= 0) {
      _spawnTimer += spawnInterval;
      final i = _spawnRandomMole();
      if (i >= 0) events.add(HoleEvent(i, HoleChange.popUp));
    }

    return events;
  }

  /// Удар по норе [index]. Если там «вылезший» крот — попадание: крот прячется,
  /// комбо растёт, начисляются очки (× комбо). Если нора пуста — промах: комбо
  /// сбрасывается. Тап вне поля возвращает [HitResult.ignored].
  HitResult hit(int index) {
    if (index < 0 || index >= holes.length) return HitResult.ignored();
    final h = holes[index];

    if (h.up) {
      h.clear();
      hits++;
      combo++;
      final gained = basePoints * combo;
      return HitResult(index: index, hit: true, gained: gained, combo: combo);
    }

    // Промах по пустой норе — серия прервана.
    combo = 0;
    return HitResult(index: index, hit: false, gained: 0, combo: 0);
  }

  /// Посадить крота в случайную свободную нору. Возвращает её индекс или -1,
  /// если все норы заняты (тогда спавн пропускается).
  int _spawnRandomMole() {
    final free = <int>[];
    for (var i = 0; i < holes.length; i++) {
      if (!holes[i].up) free.add(i);
    }
    if (free.isEmpty) return -1;
    final i = free[_rng.nextInt(free.length)];
    holes[i]
      ..up = true
      ..remaining = upTime;
    return i;
  }
}
