import 'dart:math';

import 'tank_entities.dart';

/// Что AI знает о мире. Замыкание [shouldFire] даёт доступ к лучу-проверке без
/// связывания этого файла с [TanksLogic] (чистая логика, легко тестировать).
class AiContext {
  AiContext({
    required this.baseX,
    required this.baseY,
    required this.playerX,
    required this.playerY,
    required this.playerAlive,
    required this.shouldFire,
  });

  /// Центр базы в суб-клетках.
  final int baseX;
  final int baseY;

  /// Центр игрока в суб-клетках.
  final int playerX;
  final int playerY;

  final bool playerAlive;

  /// Стоит ли стрелять прямо сейчас (луч вперёд во врага/базу/кирпич).
  final bool Function(Tank self) shouldFire;
}

/// Команда AI на тике решения.
class AiCommand {
  const AiCommand({this.turnTo, this.fire = false});

  /// Новое направление (null — оставить текущее).
  final Dir? turnTo;
  final bool fire;
}

/// Полу-случайное решение врага: чаще seek к базе/игроку по доминантной оси,
/// иногда по второстепенной, иногда случайно (обход препятствий через
/// перевыбор при упоре). Огонь — по лучу вперёд либо со склонностью [pFire].
/// Детерминировано при одинаковом [rng].
AiCommand decideAi(Tank self, AiContext ctx, Random rng) {
  final aggro = ctx.playerAlive && rng.nextDouble() < self.spec.pAggro;
  final tx = aggro ? ctx.playerX : ctx.baseX;
  final ty = aggro ? ctx.playerY : ctx.baseY;
  final dx = tx - self.cx;
  final dy = ty - self.cy;

  final dominantHoriz = dx.abs() >= dy.abs();
  final towardH = dx >= 0 ? Dir.right : Dir.left;
  final towardV = dy >= 0 ? Dir.down : Dir.up;

  final roll = rng.nextDouble();
  Dir dir;
  if (roll < 0.8) {
    dir = dominantHoriz ? towardH : towardV; // к цели по доминантной оси
  } else if (roll < 0.92) {
    dir = dominantHoriz ? towardV : towardH; // по второстепенной оси
  } else {
    dir = Dir.values[rng.nextInt(4)]; // редкий случайный манёвр
  }

  final fire = ctx.shouldFire(self) || rng.nextDouble() < self.spec.pFire;
  return AiCommand(turnTo: dir, fire: fire);
}
