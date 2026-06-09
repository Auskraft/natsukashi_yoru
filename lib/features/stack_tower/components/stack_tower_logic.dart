import 'dart:math';

/// Чем закончилась фиксация блока ([StackTowerLogic.drop]) — данные для «сока»
/// (частицы отрезанной части, попап, вспышка на идеале) и счёта. Рендер и
/// эффекты живут в Flame-слое, поэтому здесь только числа, без Flutter/Flame.
enum DropResult {
  /// Блок уложен с обрезкой свисающей части.
  placed,

  /// Идеальная установка: перекрытие почти полное (в пределах допуска).
  perfect,

  /// Нет перекрытия с блоком ниже — башня обрушилась, конец игры.
  gameOver,
}

/// Сторона, с которой отрезана свисающая часть при обычной укладке.
enum CutSide { none, left, right }

/// Исход одного хода-фиксации. Один объект — всё, что нужно слою «сока»:
/// какой блок лёг (его левый край и ширина), что и где отрезано, было ли
/// идеально и какова серия идеальных подряд.
class DropOutcome {
  const DropOutcome({
    required this.result,
    required this.placedLeft,
    required this.placedWidth,
    required this.overlap,
    required this.cutWidth,
    required this.cutLeft,
    required this.cutSide,
    required this.perfectStreak,
  });

  /// Чем закончился ход.
  final DropResult result;

  /// Левый край и ширина легшего (обрезанного) блока — в абстрактных единицах
  /// поля [StackTowerLogic.fieldWidth]. При [DropResult.gameOver] — края
  /// несостоявшегося блока (на момент фиксации), для эффекта падения.
  final double placedLeft;
  final double placedWidth;

  /// Ширина перекрытия с блоком ниже (= ширина уложенного блока без бонуса).
  final double overlap;

  /// Ширина и левый край отрезанной свисающей части (0, если идеал/обрыв нет).
  final double cutWidth;
  final double cutLeft;

  /// С какой стороны отрезано (для направления полёта частиц).
  final CutSide cutSide;

  /// Длина текущей серии идеальных установок подряд (0, если серия прервалась).
  final int perfectStreak;

  bool get isPerfect => result == DropResult.perfect;
  bool get isGameOver => result == DropResult.gameOver;
}

/// Один уложенный блок башни: левый край и ширина в единицах [fieldWidth].
class Block {
  const Block(this.left, this.width);

  final double left;
  final double width;

  double get right => left + width;
  double get center => left + width / 2;
}

/// Чистая логика игры «Stack»: горизонтально едущий блок над верхним; фиксация
/// задаёт перекрытие (новую ширину), свисающая часть отрезается; нет перекрытия
/// — конец. Идеальная установка (в пределах допуска) даёт серию и лёгкое
/// расширение блока. Без рендера и Flutter/Flame — легко тестируется.
///
/// Реалтайм-движение (когда вызывать [advance]/[drop]) живёт в Flame-слое;
/// здесь — детерминированная модель ширины/края/скорости и расчёт фиксации.
class StackTowerLogic {
  StackTowerLogic({
    Random? random,
    this.fieldWidth = 100.0,
    this.baseWidth = 60.0,
    this.baseSpeed = 60.0,
    this.speedGain = 2.4,
    this.maxSpeed = 150.0,
    this.perfectTolerance = 1.2,
    this.perfectBonus = 1.6,
  }) : _rng = random ?? Random() {
    reset();
  }

  // ── Параметры (в абстрактных единицах поля) ──────────────────────────────

  /// Ширина игрового поля; левый край блока в диапазоне [0, fieldWidth].
  final double fieldWidth;

  /// Стартовая ширина основания и движущегося блока.
  final double baseWidth;

  /// Скорость движения на первом блоке (единиц поля в секунду).
  final double baseSpeed;

  /// Прирост скорости за каждый уложенный блок.
  final double speedGain;

  /// Потолок скорости, чтобы игра оставалась проходимой.
  final double maxSpeed;

  /// Допуск идеальной установки: |смещение| <= tolerance → perfect.
  final double perfectTolerance;

  /// На сколько единиц расширяется блок при идеальной установке (не больше,
  /// чем отнято ранее, и не выходя за пределы поля).
  final double perfectBonus;

  final Random _rng;

  // ── Состояние (публично читаемо) ─────────────────────────────────────────

  /// Уложенные блоки снизу вверх; первый — основание. Не пустой после [reset].
  late List<Block> tower;

  /// Левый край движущегося блока.
  late double currentLeft;

  /// Ширина движущегося блока (= ширина верхнего уложенного).
  late double currentWidth;

  /// Направление движения: +1 вправо, -1 влево.
  late int currentDir;

  /// Текущая скорость движущегося блока (единиц/сек, всегда > 0).
  late double currentSpeed;

  /// Серия идеальных установок подряд.
  late int perfectStreak;

  /// Башня обрушилась — игра окончена.
  late bool dead;

  /// Верхний уложенный блок — опора для текущего.
  Block get top => tower.last;

  /// Сколько блоков уложено сверх основания (= счёт партии).
  int get height => tower.length - 1;

  /// Правый край движущегося блока.
  double get currentRight => currentLeft + currentWidth;

  // ── Управление ───────────────────────────────────────────────────────────

  void reset() {
    final baseLeft = (fieldWidth - baseWidth) / 2;
    tower = [Block(baseLeft, baseWidth)];
    currentWidth = baseWidth;
    currentSpeed = baseSpeed;
    perfectStreak = 0;
    dead = false;
    _spawnMover();
  }

  /// Поставить новый движущийся блок над вершиной: ширина = у вершины, заходит
  /// с края поля, направление к центру. Сторона входа случайна (инъект. Random).
  void _spawnMover() {
    currentWidth = top.width;
    currentSpeed =
        min(maxSpeed, baseSpeed + speedGain * height);
    if (_rng.nextBool()) {
      // Заходит слева, едет вправо.
      currentLeft = 0;
      currentDir = 1;
    } else {
      // Заходит справа, едет влево.
      currentLeft = fieldWidth - currentWidth;
      currentDir = -1;
    }
  }

  /// Сдвинуть движущийся блок за [dt] секунд с отскоком от стен поля.
  /// Детерминированно (без системных часов) — драйвит реалтайм Flame-слой.
  void advance(double dt) {
    if (dead) return;
    final maxLeft = fieldWidth - currentWidth;
    // Блок шире/равен полю — двигаться некуда, держим у левого края.
    if (maxLeft <= 0) {
      currentLeft = 0;
      return;
    }
    var next = currentLeft + currentDir * currentSpeed * dt;

    // Отскок от обеих стен (на случай очень большого dt — несколько отражений).
    while (next < 0 || next > maxLeft) {
      if (next < 0) {
        next = -next;
        currentDir = 1;
      } else {
        next = 2 * maxLeft - next;
        currentDir = -1;
      }
    }
    currentLeft = next;
  }

  /// Зафиксировать движущийся блок в его текущей позиции.
  DropOutcome drop() => dropAt(currentLeft);

  /// Зафиксировать движущийся блок так, будто его левый край в [left].
  /// Вынесено отдельно от реалтайма ради детерминированных тестов.
  ///
  /// Перекрытие с верхним блоком задаёт ширину нового; свисающая часть
  /// отрезается. Нет перекрытия → [DropResult.gameOver]. Перекрытие почти
  /// полное (|смещение центра| <= [perfectTolerance]) → [DropResult.perfect]:
  /// серия растёт, блок чуть расширяется на [perfectBonus] (не выходя за поле).
  DropOutcome dropAt(double left) {
    if (dead) {
      return DropOutcome(
        result: DropResult.gameOver,
        placedLeft: left,
        placedWidth: currentWidth,
        overlap: 0,
        cutWidth: 0,
        cutLeft: left,
        cutSide: CutSide.none,
        perfectStreak: perfectStreak,
      );
    }

    final movingRight = left + currentWidth;
    final overlapLeft = max(left, top.left);
    final overlapRight = min(movingRight, top.right);
    final overlap = overlapRight - overlapLeft;

    // Нет перекрытия — башня рухнула.
    if (overlap <= 0) {
      dead = true;
      perfectStreak = 0;
      return DropOutcome(
        result: DropResult.gameOver,
        placedLeft: left,
        placedWidth: currentWidth,
        overlap: 0,
        cutWidth: currentWidth,
        cutLeft: left,
        cutSide: CutSide.none,
        perfectStreak: 0,
      );
    }

    // Идеал: центр движущегося почти совпал с центром опоры.
    final offset = (left + currentWidth / 2) - top.center;
    if (offset.abs() <= perfectTolerance) {
      perfectStreak++;
      // Лёгкое расширение, не выходя за пределы поля.
      final grown = min(currentWidth + perfectBonus, fieldWidth);
      // Выравниваем по опоре и держим внутри поля (max/min дают double для
      // double-аргументов — без num→double конверсии, как у .clamp).
      final newLeft = max(0.0, min(top.center - grown / 2, fieldWidth - grown));
      final block = Block(newLeft, grown);
      tower.add(block);
      currentWidth = grown;
      _spawnMover();
      return DropOutcome(
        result: DropResult.perfect,
        placedLeft: block.left,
        placedWidth: block.width,
        overlap: overlap,
        cutWidth: 0,
        cutLeft: block.left,
        cutSide: CutSide.none,
        perfectStreak: perfectStreak,
      );
    }

    // Обычная укладка: новый блок = зона перекрытия, остаток отрезан.
    perfectStreak = 0;
    final CutSide side;
    final double cutLeft;
    if (left < top.left) {
      // Свисает слева.
      side = CutSide.left;
      cutLeft = left;
    } else {
      // Свисает справа.
      side = CutSide.right;
      cutLeft = overlapRight;
    }
    final cutWidth = currentWidth - overlap;
    final block = Block(overlapLeft, overlap);
    tower.add(block);
    currentWidth = overlap;
    _spawnMover();
    return DropOutcome(
      result: DropResult.placed,
      placedLeft: block.left,
      placedWidth: block.width,
      overlap: overlap,
      cutWidth: cutWidth,
      cutLeft: cutLeft,
      cutSide: side,
      perfectStreak: 0,
    );
  }
}
