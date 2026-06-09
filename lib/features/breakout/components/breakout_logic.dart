import 'dart:math';

/// Чистая логика «Breakout/Арканоид» без рендера и Flutter/Flame-зависимостей —
/// поэтому легко тестируется. Рендер и «сок» живут в Flame-слое.
///
/// Координаты нормализованы: поле по ширине [0, 1], по высоте [0, [fieldHeight]]
/// (ось Y вниз). Слой рендера сам масштабирует это в пиксели. Радиусы/размеры —
/// в тех же единицах, чтобы физика не зависела от размера экрана.
///
/// Случайность инъектируется через конструктор (детерминизм в тестах);
/// системные часы/глобальный Random в логике не используются.

/// Тип события отскока — для тактильной отдачи и эффектов на Flame-слое.
enum BounceKind { wall, ceiling, paddle, brick }

/// Один разбитый кирпич за шаг: его место в сетке, центр (для частиц/попапов)
/// и индекс цвета ряда (рендер сам выберет палитру — здесь никаких Color).
class BrokenBrick {
  const BrokenBrick({
    required this.col,
    required this.row,
    required this.center,
    required this.colorIndex,
    required this.points,
  });

  /// Колонка/ряд в сетке кирпичей.
  final int col;
  final int row;

  /// Центр кирпича в нормализованных координатах поля (для искр/попапов).
  final Point<double> center;

  /// Индекс цвета ряда (0..) — рендер маппит на палитру.
  final int colorIndex;

  /// Сколько очков начислено за этот кирпич.
  final int points;

  @override
  String toString() =>
      'BrokenBrick($col,$row,color=$colorIndex,+$points)';
}

/// Исход одного [BreakoutLogic.step]: всё, что изменилось за кадр, — для «сока»
/// (частицы/попапы/тряска/хаптика) и для HUD. Один объект на кадр.
class StepResult {
  StepResult({
    required this.bounces,
    required this.brokenBricks,
    required this.gainedScore,
    required this.ballLost,
    required this.levelCleared,
    required this.gameOver,
  });

  /// Виды отскоков за кадр (стены/потолок/ракетка/кирпич) — для хаптики.
  final List<BounceKind> bounces;

  /// Разбитые за кадр кирпичи (позиции, цвета, очки) — для частиц и попапов.
  final List<BrokenBrick> brokenBricks;

  /// Очки, начисленные за кадр (сумма по [brokenBricks]).
  final int gainedScore;

  /// Мяч ушёл ниже ракетки (потеря жизни) на этом кадре.
  final bool ballLost;

  /// Последний кирпич уровня разбит на этом кадре (переход на следующий).
  final bool levelCleared;

  /// Жизни кончились на этом кадре (конец партии).
  final bool gameOver;

  /// Был ли отскок указанного вида на этом кадре.
  bool hasBounce(BounceKind kind) => bounces.contains(kind);

  /// Пустой исход «ничего не произошло» — мяч просто летел.
  static StepResult empty() => StepResult(
        bounces: const [],
        brokenBricks: const [],
        gainedScore: 0,
        ballLost: false,
        levelCleared: false,
        gameOver: false,
      );
}

/// Состояние партии «Breakout»: ракетка, мяч и сетка кирпичей.
///
/// Поле, счёт, жизни, уровень и наличие кирпичей читаются публично; шаг
/// симуляции [step] продвигает физику и возвращает [StepResult].
class BreakoutLogic {
  BreakoutLogic({
    this.cols = 8,
    this.fieldHeight = 1.4,
    Random? random,
  }) : _rng = random ?? Random() {
    reset();
  }

  // ── Конфигурация поля/физики (в нормализованных единицах) ──────────────────

  /// Число колонок кирпичей.
  final int cols;

  /// Высота поля (ширина всегда 1). Чуть выше ширины — поле «портретное».
  final double fieldHeight;

  final Random _rng;

  /// Радиус мяча.
  static const double ballRadius = 0.018;

  /// Полуширина ракетки (полная ширина = 2× этого).
  static const double basePaddleHalfWidth = 0.11;

  /// Высота ракетки.
  static const double paddleHeight = 0.022;

  /// Отступ ракетки от низа поля (центр ракетки по Y = fieldHeight - этого).
  static const double paddleBottomGap = 0.05;

  /// Вертикальные отступы блока кирпичей (сверху — под HUD визуально).
  static const double bricksTop = 0.12;

  /// Зазор между кирпичами (по обеим осям) в долях ширины поля.
  static const double brickGap = 0.012;

  /// Высота одного кирпича.
  static const double brickHeight = 0.04;

  /// Базовая скорость мяча (модуль), единиц/сек. Растёт с уровнем.
  static const double baseSpeed = 0.85;

  /// Прибавка к скорости за каждый уровень.
  static const double speedPerLevel = 0.08;

  /// Максимальный модуль скорости — чтобы на высоких уровнях мяч оставался
  /// управляемым и под-шаги физики не «протыкали» кирпичи.
  static const double maxSpeed = 1.8;

  /// Стартовое число рядов кирпичей.
  static const int baseRows = 4;

  /// Максимум рядов (ограничено сверху по доступной высоте поля).
  static const int maxRows = 8;

  /// Очки за кирпич = (число рядов - индекс ряда) — верхние ряды дороже.
  /// Базовый множитель очков на кирпич.
  static const int basePointsPerBrick = 10;

  /// Стартовое число жизней.
  static const int startLives = 3;

  // ── Публичное состояние ────────────────────────────────────────────────────

  /// Сетка кирпичей: bricks[row][col] == true — кирпич цел.
  late List<List<bool>> bricks;

  /// Текущее число рядов (может расти с уровнем).
  late int rows;

  /// Позиция центра мяча.
  late Point<double> ball;

  /// Скорость мяча (единиц/сек) по осям.
  late Point<double> ballVel;

  /// Позиция центра ракетки по X (Y фиксирован у низа).
  late double paddleX;

  /// Полуширина ракетки (может меняться при желании; пока константна).
  double paddleHalfWidth = basePaddleHalfWidth;

  int score = 0;
  int lives = startLives;
  int level = 1;

  /// Мяч «приклеен» к ракетке (ждёт запуска после старта/потери жизни).
  bool ballOnPaddle = true;

  /// Партия окончена (жизни кончились).
  bool gameOver = false;

  // ── Производные геометрические величины ────────────────────────────────────

  /// Y центра ракетки.
  double get paddleY => fieldHeight - paddleBottomGap;

  /// Ширина одного кирпича (с учётом зазоров и краёв поля).
  double get brickWidth => (1 - brickGap * (cols + 1)) / cols;

  /// Текущий модуль скорости мяча для уровня.
  double get _speed =>
      min(maxSpeed, baseSpeed + (level - 1) * speedPerLevel);

  /// Сколько кирпичей ещё цело.
  int get bricksLeft {
    var n = 0;
    for (final row in bricks) {
      for (final b in row) {
        if (b) n++;
      }
    }
    return n;
  }

  /// Центр кирпича (col,row) в координатах поля.
  Point<double> brickCenter(int col, int row) {
    final x = brickGap + col * (brickWidth + brickGap) + brickWidth / 2;
    final y = bricksTop + row * (brickHeight + brickGap) + brickHeight / 2;
    return Point(x, y);
  }

  /// Очки за кирпич в ряду [row] (верхние ряды дороже).
  int pointsForRow(int row) => basePointsPerBrick * (rows - row);

  // ── Управление состоянием ──────────────────────────────────────────────────

  /// Полный сброс партии к началу первого уровня.
  void reset() {
    score = 0;
    lives = startLives;
    level = 1;
    gameOver = false;
    paddleHalfWidth = basePaddleHalfWidth;
    paddleX = 0.5;
    _buildBricks();
    _resetBall();
  }

  /// Перейти на следующий уровень: добрать ряд (до максимума), пересобрать
  /// кирпичи, переставить мяч на ракетку. Скорость вырастет через [_speed].
  void _nextLevel() {
    level++;
    _buildBricks();
    _resetBall();
  }

  /// Собрать сетку кирпичей под текущий уровень. Число рядов растёт с уровнем,
  /// но не больше [maxRows] и не больше, чем влезает по высоте до ракетки.
  void _buildBricks() {
    final wanted = baseRows + (level - 1);
    final fitByHeight = _maxRowsByHeight();
    final cap = min(maxRows, fitByHeight);
    rows = wanted < baseRows
        ? baseRows
        : (wanted > cap ? cap : wanted);
    bricks = List.generate(rows, (_) => List<bool>.filled(cols, true));
  }

  /// Сколько рядов помещается между [bricksTop] и верхом ракетки с запасом.
  int _maxRowsByHeight() {
    final available = paddleY - paddleHeight / 2 - bricksTop - 0.18;
    final per = brickHeight + brickGap;
    final n = (available / per).floor();
    return n < 1 ? 1 : n;
  }

  /// Поставить мяч на центр ракетки и «приклеить» (ждём запуска).
  void _resetBall() {
    ballOnPaddle = true;
    ball = Point(paddleX, paddleY - paddleHeight / 2 - ballRadius);
    ballVel = const Point<double>(0, 0);
  }

  /// Запустить приклеенный мяч вверх под небольшим случайным углом.
  /// Игнорируется, если мяч уже в полёте или партия окончена.
  void launch() {
    if (gameOver || !ballOnPaddle) return;
    ballOnPaddle = false;
    // Угол ±35° от вертикали вверх, чтобы старт не был строго вертикальным.
    final spread = (_rng.nextDouble() * 2 - 1) * (35 * pi / 180);
    final angle = -pi / 2 + spread; // вверх
    ballVel = Point(cos(angle) * _speed, sin(angle) * _speed);
  }

  // ── Шаг симуляции ──────────────────────────────────────────────────────────

  /// Продвинуть физику на [dt] секунд при позиции ракетки [paddleX] (центр,
  /// в нормализованных координатах; будет ограничена краями поля).
  ///
  /// Использует под-шаги, чтобы быстрый мяч не «протыкал» кирпичи/стены.
  /// Возвращает [StepResult] со всем, что произошло за кадр.
  StepResult step(double dt, double paddleX) {
    // Ракетка следует за пальцем, но не вылезает за края поля.
    this.paddleX = paddleX.clamp(paddleHalfWidth, 1 - paddleHalfWidth);

    if (gameOver) return StepResult.empty();

    if (ballOnPaddle) {
      // Мяч едет вместе с ракеткой до запуска.
      ball = Point(this.paddleX, paddleY - paddleHeight / 2 - ballRadius);
      return StepResult.empty();
    }

    final bounces = <BounceKind>[];
    final broken = <BrokenBrick>[];
    var gained = 0;
    var ballLost = false;
    var levelCleared = false;
    var over = false;

    // Под-шаги: дробим dt так, чтобы за под-шаг мяч проходил не больше
    // ~половины своего радиуса. Это устраняет туннелирование сквозь кирпичи.
    final dist = _speed * dt;
    final steps = max(1, (dist / (ballRadius * 0.5)).ceil());
    final h = dt / steps;

    for (var i = 0; i < steps; i++) {
      _integrate(h, bounces, broken);

      // Потеря мяча: ушёл ниже нижней кромки поля.
      if (ball.y - ballRadius > fieldHeight) {
        ballLost = true;
        break;
      }

      // Уровень очищен — мяч больше не нужен в этом кадре.
      if (bricksLeft == 0) {
        levelCleared = true;
        break;
      }
    }

    for (final b in broken) {
      gained += b.points;
    }
    score += gained;

    if (levelCleared) {
      _nextLevel();
    } else if (ballLost) {
      lives--;
      if (lives <= 0) {
        lives = 0;
        gameOver = true;
        over = true;
      } else {
        _resetBall();
      }
    }

    return StepResult(
      bounces: bounces,
      brokenBricks: broken,
      gainedScore: gained,
      ballLost: ballLost,
      levelCleared: levelCleared,
      gameOver: over,
    );
  }

  /// Один под-шаг интегрирования: двигает мяч и разрешает столкновения со
  /// стенами, потолком, ракеткой и (одним) кирпичом. Накапливает события.
  void _integrate(
    double h,
    List<BounceKind> bounces,
    List<BrokenBrick> broken,
  ) {
    ball = Point(ball.x + ballVel.x * h, ball.y + ballVel.y * h);

    // Боковые стены.
    if (ball.x - ballRadius < 0) {
      ball = Point(ballRadius, ball.y);
      ballVel = Point(ballVel.x.abs(), ballVel.y);
      bounces.add(BounceKind.wall);
    } else if (ball.x + ballRadius > 1) {
      ball = Point(1 - ballRadius, ball.y);
      ballVel = Point(-ballVel.x.abs(), ballVel.y);
      bounces.add(BounceKind.wall);
    }

    // Потолок.
    if (ball.y - ballRadius < 0) {
      ball = Point(ball.x, ballRadius);
      ballVel = Point(ballVel.x, ballVel.y.abs());
      bounces.add(BounceKind.ceiling);
    }

    _collidePaddle(bounces);
    _collideBricks(bounces, broken);
  }

  /// Отскок от ракетки: только когда мяч идёт вниз и пересекает верхнюю кромку
  /// ракетки в пределах её ширины. Угол отлёта зависит от точки удара —
  /// ближе к краю ракетки угол острее (классика арканоида).
  void _collidePaddle(List<BounceKind> bounces) {
    if (ballVel.y <= 0) return; // летит вверх — мимо

    final top = paddleY - paddleHeight / 2;
    if (ball.y + ballRadius < top) return; // ещё не достал
    if (ball.y - ballRadius > paddleY + paddleHeight / 2) return; // уже ниже

    if (ball.x < paddleX - paddleHalfWidth - ballRadius ||
        ball.x > paddleX + paddleHalfWidth + ballRadius) {
      return; // мимо по X
    }

    // Точка удара: -1 (левый край) .. +1 (правый край).
    final rel =
        ((ball.x - paddleX) / paddleHalfWidth).clamp(-1.0, 1.0);
    // Максимальный угол отлёта от вертикали — 60°.
    const maxAngle = 60 * pi / 180;
    final angle = -pi / 2 + rel * maxAngle; // вверх, отклонён к краю удара
    final spd = _speed;
    ballVel = Point(cos(angle) * spd, sin(angle) * spd);
    // Поднимаем мяч над ракеткой, чтобы не залипал внутри.
    ball = Point(ball.x, top - ballRadius);
    bounces.add(BounceKind.paddle);
  }

  /// Столкновение с кирпичами: ищем кирпич, чей прямоугольник пересекает мяч.
  /// Разбиваем не более одного кирпича за под-шаг (под-шаги мелкие — этого
  /// достаточно), отражаем скорость по оси наименьшего проникновения.
  void _collideBricks(List<BounceKind> bounces, List<BrokenBrick> broken) {
    // Быстрый отбор по вертикальной полосе кирпичей.
    final minY = bricksTop;
    final maxY = bricksTop + rows * (brickHeight + brickGap);
    if (ball.y + ballRadius < minY || ball.y - ballRadius > maxY) return;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if (!bricks[row][col]) continue;

        final c = brickCenter(col, row);
        final halfW = brickWidth / 2;
        final halfH = brickHeight / 2;

        // Ближайшая к центру мяча точка прямоугольника кирпича.
        final nearestX = ball.x.clamp(c.x - halfW, c.x + halfW);
        final nearestY = ball.y.clamp(c.y - halfH, c.y + halfH);
        final dx = ball.x - nearestX;
        final dy = ball.y - nearestY;
        if (dx * dx + dy * dy > ballRadius * ballRadius) continue;

        // Пересечение есть — определяем ось отражения по глубине проникновения.
        final overlapX = halfW + ballRadius - (ball.x - c.x).abs();
        final overlapY = halfH + ballRadius - (ball.y - c.y).abs();
        if (overlapX < overlapY) {
          // Отражаем по X, выталкиваем по X.
          final dir = ball.x < c.x ? -1.0 : 1.0;
          ballVel = Point(dir * ballVel.x.abs(), ballVel.y);
          ball = Point(ball.x + dir * overlapX, ball.y);
        } else {
          final dir = ball.y < c.y ? -1.0 : 1.0;
          ballVel = Point(ballVel.x, dir * ballVel.y.abs());
          ball = Point(ball.x, ball.y + dir * overlapY);
        }

        bricks[row][col] = false;
        final pts = pointsForRow(row);
        broken.add(BrokenBrick(
          col: col,
          row: row,
          center: c,
          colorIndex: row,
          points: pts,
        ));
        bounces.add(BounceKind.brick);
        return; // один кирпич за под-шаг
      }
    }
  }
}
