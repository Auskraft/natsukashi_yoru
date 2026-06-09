import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/breakout/components/breakout_logic.dart';

/// Снять все кирпичи, кроме одного (col,row) — удобно изолировать сценарии
/// очистки уровня и попадания по конкретному кирпичу.
void keepOnlyBrick(BreakoutLogic g, int col, int row) {
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      g.bricks[r][c] = r == row && c == col;
    }
  }
}

/// Снять все кирпичи (поле без кирпичей — для теста очистки уровня).
void clearAllBricks(BreakoutLogic g) {
  for (var r = 0; r < g.rows; r++) {
    for (var c = 0; c < g.cols; c++) {
      g.bricks[r][c] = false;
    }
  }
}

void main() {
  group('старт / reset', () {
    test('начальное состояние: жизни, уровень, счёт, мяч на ракетке', () {
      final g = BreakoutLogic(random: Random(1));
      expect(g.lives, BreakoutLogic.startLives);
      expect(g.level, 1);
      expect(g.score, 0);
      expect(g.gameOver, isFalse);
      expect(g.ballOnPaddle, isTrue);
      // Все кирпичи целы: bricksLeft == rows*cols.
      expect(g.bricksLeft, g.rows * g.cols);
      expect(g.bricks.length, g.rows);
      expect(g.bricks.every((row) => row.length == g.cols), isTrue);
    });

    test('мяч приклеен над ракеткой и не движется до запуска', () {
      final g = BreakoutLogic(random: Random(2));
      expect(g.ballVel, const Point<double>(0, 0));
      // Шаг с приклеенным мячом не порождает событий и не двигает физику.
      final res = g.step(0.016, 0.5);
      expect(res.brokenBricks, isEmpty);
      expect(res.ballLost, isFalse);
      expect(g.ballOnPaddle, isTrue);
    });
  });

  group('launch', () {
    test('запуск отрывает мяч и направляет вверх', () {
      final g = BreakoutLogic(random: Random(3));
      g.launch();
      expect(g.ballOnPaddle, isFalse);
      expect(g.ballVel.y, lessThan(0), reason: 'мяч должен лететь вверх');
      // Модуль скорости близок к baseSpeed на первом уровне.
      final speed =
          sqrt(g.ballVel.x * g.ballVel.x + g.ballVel.y * g.ballVel.y);
      expect(speed, closeTo(BreakoutLogic.baseSpeed, 1e-6));
    });

    test('детерминизм: одно зерно — одинаковое направление запуска', () {
      final a = BreakoutLogic(random: Random(42))..launch();
      final b = BreakoutLogic(random: Random(42))..launch();
      expect(a.ballVel.x, closeTo(b.ballVel.x, 1e-9));
      expect(a.ballVel.y, closeTo(b.ballVel.y, 1e-9));
    });

    test('повторный launch в полёте игнорируется', () {
      final g = BreakoutLogic(random: Random(4))..launch();
      final vel = g.ballVel;
      g.launch();
      expect(g.ballVel, vel);
    });
  });

  group('отскоки от стен и потолка', () {
    test('левая стена разворачивает X вправо', () {
      final g = BreakoutLogic(random: Random(5));
      g.ballOnPaddle = false;
      // Мяч у левого края, летит влево-вверх (вверх, чтобы не задеть ракетку).
      g.ball = Point(BreakoutLogic.ballRadius + 0.002, 0.5);
      g.ballVel = const Point(-0.6, -0.2);
      final res = g.step(0.02, 0.5);
      expect(res.hasBounce(BounceKind.wall), isTrue);
      expect(g.ballVel.x, greaterThan(0), reason: 'X должен стать вправо');
    });

    test('правая стена разворачивает X влево', () {
      final g = BreakoutLogic(random: Random(6));
      g.ballOnPaddle = false;
      g.ball = Point(1 - BreakoutLogic.ballRadius - 0.002, 0.5);
      g.ballVel = const Point(0.6, -0.2);
      final res = g.step(0.02, 0.5);
      expect(res.hasBounce(BounceKind.wall), isTrue);
      expect(g.ballVel.x, lessThan(0));
    });

    test('потолок разворачивает Y вниз', () {
      final g = BreakoutLogic(random: Random(7));
      g.ballOnPaddle = false;
      // Подняли мяч под потолок, чтобы он не задел кирпичи (выше bricksTop).
      g.ball = Point(0.5, BreakoutLogic.ballRadius + 0.002);
      g.ballVel = const Point(0.0, -0.6);
      // Снимем кирпичи, чтобы изолировать отскок от потолка.
      keepOnlyBrick(g, 0, 0);
      final res = g.step(0.02, 0.5);
      expect(res.hasBounce(BounceKind.ceiling), isTrue);
      expect(g.ballVel.y, greaterThan(0));
    });
  });

  group('кирпичи', () {
    test('пересечение с кирпичом разбивает его: +очки, событие, отражение', () {
      final g = BreakoutLogic(random: Random(8));
      const col = 3;
      const row = 1;
      keepOnlyBrick(g, col, row);
      g.bricks[0][0] = true; // запасной кирпич, чтобы разбитие цели не очистило уровень
      expect(g.bricksLeft, 2);

      g.ballOnPaddle = false;
      // Ставим мяч прямо в центр кирпича, лёгкое движение вверх.
      g.ball = g.brickCenter(col, row);
      g.ballVel = const Point(0.0, -0.5);

      final before = g.score;
      final expectedPoints = g.pointsForRow(row);
      final res = g.step(0.016, 0.5);

      expect(res.brokenBricks.length, 1);
      final b = res.brokenBricks.first;
      expect(b.col, col);
      expect(b.row, row);
      expect(b.colorIndex, row);
      expect(b.points, expectedPoints);
      expect(b.points, greaterThan(0));

      expect(res.hasBounce(BounceKind.brick), isTrue);
      expect(res.gainedScore, b.points);
      expect(g.score, before + b.points);
      expect(g.bricks[row][col], isFalse, reason: 'кирпич снят');
      expect(g.bricksLeft, 1);
    });

    test('верхние ряды дороже нижних', () {
      final g = BreakoutLogic(random: Random(9));
      // pointsForRow убывает с ростом индекса ряда (верх = ряд 0).
      expect(g.pointsForRow(0), greaterThan(g.pointsForRow(g.rows - 1)));
    });

    test('мяч мимо кирпичей событий о кирпичах не даёт', () {
      final g = BreakoutLogic(random: Random(10));
      keepOnlyBrick(g, 0, 0);
      g.ballOnPaddle = false;
      g.ball = const Point(0.5, 0.6);
      g.ballVel = const Point(0.1, -0.3);
      final res = g.step(0.016, 0.5);
      expect(res.brokenBricks, isEmpty);
      expect(res.gainedScore, 0);
    });
  });

  group('очистка уровня', () {
    test('разбитие последнего кирпича очищает уровень и поднимает level', () {
      final g = BreakoutLogic(random: Random(11));
      final startLevel = g.level;
      const col = 2;
      const row = 0;
      keepOnlyBrick(g, col, row);

      g.ballOnPaddle = false;
      g.ball = g.brickCenter(col, row);
      g.ballVel = const Point(0.0, -0.5);

      final res = g.step(0.016, 0.5);
      expect(res.levelCleared, isTrue);
      expect(g.level, startLevel + 1);
      // Новый уровень: кирпичи пересобраны (поле снова заполнено),
      // мяч снова приклеен к ракетке.
      expect(g.bricksLeft, g.rows * g.cols);
      expect(g.ballOnPaddle, isTrue);
    });

    test('следующий уровень не медленнее предыдущего', () {
      final g = BreakoutLogic(random: Random(12));
      g.launch();
      final speed1 =
          sqrt(g.ballVel.x * g.ballVel.x + g.ballVel.y * g.ballVel.y);

      // Симулируем переход на уровень 2 через очистку.
      keepOnlyBrick(g, 0, 0);
      keepOnlyBrick(g, 0, 0);
      g.ballOnPaddle = false;
      g.ball = g.brickCenter(0, 0);
      g.ballVel = const Point(0.0, -0.5);
      final res = g.step(0.016, 0.5);
      expect(res.levelCleared, isTrue);

      g.launch();
      final speed2 =
          sqrt(g.ballVel.x * g.ballVel.x + g.ballVel.y * g.ballVel.y);
      expect(speed2, greaterThanOrEqualTo(speed1));
    });
  });

  group('потеря мяча и конец игры', () {
    test('мяч ниже поля → потеря жизни и перезапуск мяча', () {
      final g = BreakoutLogic(random: Random(13));
      keepOnlyBrick(g, 0, 0); // чтобы по пути не разбить кирпич
      final startLives = g.lives;
      g.ballOnPaddle = false;
      // Уже у нижней кромки, летит вниз — за шаг уйдёт за поле.
      g.ball = Point(0.5, g.fieldHeight - 0.001);
      g.ballVel = const Point(0.0, 0.6);

      final res = g.step(0.05, 0.5);
      expect(res.ballLost, isTrue);
      expect(g.lives, startLives - 1);
      expect(res.gameOver, isFalse);
      // Мяч снова приклеен к ракетке после потери.
      expect(g.ballOnPaddle, isTrue);
    });

    test('потеря последней жизни → game over', () {
      final g = BreakoutLogic(random: Random(14));
      keepOnlyBrick(g, 0, 0);
      g.lives = 1;
      g.ballOnPaddle = false;
      g.ball = Point(0.5, g.fieldHeight - 0.001);
      g.ballVel = const Point(0.0, 0.6);

      final res = g.step(0.05, 0.5);
      expect(res.ballLost, isTrue);
      expect(res.gameOver, isTrue);
      expect(g.gameOver, isTrue);
      expect(g.lives, 0);
    });

    test('после game over step ничего не делает', () {
      final g = BreakoutLogic(random: Random(15));
      keepOnlyBrick(g, 0, 0);
      g.lives = 1;
      g.ballOnPaddle = false;
      g.ball = Point(0.5, g.fieldHeight - 0.001);
      g.ballVel = const Point(0.0, 0.6);
      g.step(0.05, 0.5);
      expect(g.gameOver, isTrue);

      final res = g.step(0.05, 0.5);
      expect(res.ballLost, isFalse);
      expect(res.brokenBricks, isEmpty);
      expect(res.gameOver, isFalse);
    });
  });

  group('отскок от ракетки', () {
    test('мяч у ракетки отражается вверх', () {
      final g = BreakoutLogic(random: Random(16));
      keepOnlyBrick(g, 0, 0);
      g.ballOnPaddle = false;
      g.paddleHalfWidth = BreakoutLogic.basePaddleHalfWidth;
      // Мяч в центре ракетки, идёт вниз.
      final top = g.paddleY - BreakoutLogic.paddleHeight / 2;
      g.ball = Point(0.5, top - BreakoutLogic.ballRadius + 0.001);
      g.ballVel = const Point(0.0, 0.6);

      final res = g.step(0.016, 0.5);
      expect(res.hasBounce(BounceKind.paddle), isTrue);
      expect(g.ballVel.y, lessThan(0), reason: 'после ракетки мяч летит вверх');
    });

    test('удар у края ракетки даёт более острый угол, чем по центру', () {
      double horizComponentForHit(double ballX, double paddleX) {
        final g = BreakoutLogic(random: Random(17));
        keepOnlyBrick(g, 0, 0);
        g.ballOnPaddle = false;
        g.paddleHalfWidth = BreakoutLogic.basePaddleHalfWidth;
        final top = g.paddleY - BreakoutLogic.paddleHeight / 2;
        g.ball = Point(ballX, top - BreakoutLogic.ballRadius + 0.001);
        g.ballVel = const Point(0.0, 0.6);
        final res = g.step(0.016, paddleX);
        expect(res.hasBounce(BounceKind.paddle), isTrue);
        return g.ballVel.x.abs();
      }

      const paddleX = 0.5;
      final center = horizComponentForHit(paddleX, paddleX);
      // Удар у правого края ракетки.
      final edgeX = paddleX + BreakoutLogic.basePaddleHalfWidth * 0.9;
      final edge = horizComponentForHit(edgeX, paddleX);

      expect(center, lessThan(edge),
          reason: 'у края горизонтальная составляющая больше (угол острее)');
    });
  });

  group('ракетка', () {
    test('ракетка не выходит за края поля', () {
      final g = BreakoutLogic(random: Random(18));
      g.step(0.016, -5); // далеко за левый край
      expect(g.paddleX, closeTo(g.paddleHalfWidth, 1e-9));
      g.step(0.016, 5); // далеко за правый край
      expect(g.paddleX, closeTo(1 - g.paddleHalfWidth, 1e-9));
    });
  });
}
