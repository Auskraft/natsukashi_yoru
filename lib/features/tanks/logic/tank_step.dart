import 'dart:math';

import 'tank_entities.dart';

/// Уничтоженный танк (для взрыва/очков/звука).
class TankDestroyed {
  TankDestroyed({
    required this.kind,
    required this.center,
    required this.byPlayer,
    required this.score,
  });

  final TankKind kind;
  final Point<double> center;
  final bool byPlayer;
  final int score;
}

/// Попадание в кирпич (крошка/звук).
class BrickHit {
  BrickHit(this.center);
  final Point<double> center;
}

/// Рикошет от стали.
class SteelHit {
  SteelHit(this.center);
  final Point<double> center;
}

/// Рождение пули (вспышка дула/звук).
class BulletSpawned {
  BulletSpawned({
    required this.center,
    required this.dir,
    required this.byPlayer,
  });

  final Point<double> center;
  final Dir dir;
  final bool byPlayer;
}

/// Появление либо взятие бонуса.
class PowerUpEvent {
  PowerUpEvent({required this.type, required this.center});
  final PowerUpType type;
  final Point<double> center;
}

/// Результат одного шага симуляции — единственный «шов» между чистой логикой и
/// слоем рендера/«сока». Логика наполняет его дискретными исходами кадра; сам по
/// себе детерминирован и пригоден для тестов.
class TankStep {
  final List<TankDestroyed> tanksDestroyed = [];
  final List<BrickHit> bricksHit = [];
  final List<SteelHit> steelHits = [];
  final List<Point<double>> bulletClashes = [];
  final List<BulletSpawned> bulletsSpawned = [];
  final List<PowerUpEvent> powerUpsSpawned = [];
  final List<PowerUpEvent> powerUpsTaken = [];
  final List<Point<double>> spawnFlashes = [];

  bool baseHit = false;
  bool playerHit = false;
  bool playerUpgraded = false;
  int gainedScore = 0;
  bool waveCleared = false;
  bool win = false;
  bool gameOver = false;

  /// Ничего значимого не произошло (для тестов и оптимизации рендера).
  bool get isQuiet =>
      tanksDestroyed.isEmpty &&
      bricksHit.isEmpty &&
      steelHits.isEmpty &&
      bulletClashes.isEmpty &&
      bulletsSpawned.isEmpty &&
      powerUpsSpawned.isEmpty &&
      powerUpsTaken.isEmpty &&
      spawnFlashes.isEmpty &&
      !baseHit &&
      !playerHit &&
      !win &&
      !gameOver;
}
