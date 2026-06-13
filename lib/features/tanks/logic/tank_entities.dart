import 'dart:math';

import 'tank_geometry.dart';

/// Направление (4 стороны). Дельта — в суб-клетках на единицу пути.
enum Dir {
  up(0, -1),
  right(1, 0),
  down(0, 1),
  left(-1, 0);

  const Dir(this.dx, this.dy);

  final int dx;
  final int dy;

  bool get isHorizontal => this == Dir.left || this == Dir.right;

  Dir get opposite => switch (this) {
        Dir.up => Dir.down,
        Dir.down => Dir.up,
        Dir.left => Dir.right,
        Dir.right => Dir.left,
      };
}

/// Тип танка: игрок + классические архетипы Battle City + босс.
enum TankKind { player, basic, fast, power, armor, boss }

/// Кто выпустил пулю (дружественный огонь выключен; встречные пули гасятся).
enum BulletOwner { player, enemy }

/// Тип бонуса.
enum PowerUpType { star, grenade, helmet, shovel, life, freeze }

/// Максимальный тир апгрейда игрока.
const int kMaxUpgradeTier = 3;

/// Сила пули, ломающей сталь (тир-3 игрока / босс).
const int kSteelBreakPower = 2;

/// Длительность жизни невзятого бонуса, сек.
const double kPowerUpLifetime = 12;

/// Тех-параметры архетипа танка. Тюнинг — это данные, не код.
class TankSpec {
  const TankSpec({
    required this.speed,
    required this.hp,
    required this.bulletSpeed,
    required this.fireCooldown,
    required this.score,
    this.pAggro = 0.5,
    this.pFire = 0.4,
  });

  /// Скорость, суб-клеток/сек.
  final double speed;

  /// Очки здоровья (число попаданий до уничтожения).
  final int hp;

  /// Скорость пули, суб-клеток/сек.
  final double bulletSpeed;

  /// Перезарядка между выстрелами, сек.
  final double fireCooldown;

  /// Очки за уничтожение.
  final int score;

  /// Склонность целиться в базу/игрока (для AI).
  final double pAggro;

  /// Склонность стрелять на тике решения (для AI).
  final double pFire;
}

/// Таблица характеристик по типам танков. Значения — стартовые, под тюнинг.
const Map<TankKind, TankSpec> kTankSpecs = {
  TankKind.player:
      TankSpec(speed: 38, hp: 1, bulletSpeed: 150, fireCooldown: 0.32, score: 0),
  TankKind.basic: TankSpec(
      speed: 24,
      hp: 1,
      bulletSpeed: 95,
      fireCooldown: 1.1,
      score: 100,
      pAggro: 0.5,
      pFire: 0.35),
  TankKind.fast: TankSpec(
      speed: 46,
      hp: 1,
      bulletSpeed: 95,
      fireCooldown: 1.0,
      score: 200,
      pAggro: 0.8,
      pFire: 0.3),
  TankKind.power: TankSpec(
      speed: 28,
      hp: 1,
      bulletSpeed: 165,
      fireCooldown: 0.7,
      score: 300,
      pAggro: 0.5,
      pFire: 0.65),
  TankKind.armor: TankSpec(
      speed: 20,
      hp: 4,
      bulletSpeed: 95,
      fireCooldown: 1.0,
      score: 400,
      pAggro: 0.6,
      pFire: 0.5),
  TankKind.boss: TankSpec(
      speed: 22,
      hp: 12,
      bulletSpeed: 150,
      fireCooldown: 0.75,
      score: 1000,
      pAggro: 0.7,
      pFire: 0.7),
};

/// Танк — игрок или враг. Позиция — верхне-левый угол AABB в суб-клетках.
class Tank {
  Tank({
    required this.id,
    required this.kind,
    required this.sx,
    required this.sy,
    required this.dir,
    required this.isPlayer,
    int? hp,
  }) : hp = hp ?? kTankSpecs[kind]!.hp;

  final int id;
  TankKind kind;
  int sx;
  int sy;
  Dir dir;
  final bool isPlayer;
  int hp;

  /// Тир апгрейда (только игрок): 0..[kMaxUpgradeTier].
  int tier = 0;

  /// Накопитель суб-клеток движения (дробный остаток держится здесь).
  double moveAccum = 0;

  /// Текущая перезарядка выстрела, сек.
  double fireCooldown = 0;

  /// Таймер неуязвимости (щит / после спавна), сек.
  double shieldTimer = 0;

  /// Таймер заморозки (вражеский бонус «таймер»), сек.
  double freezeTimer = 0;

  /// Остаток дрифта по льду в суб-клетках.
  int slideRemaining = 0;

  /// Таймер до следующего решения AI, сек.
  double decisionTimer = 0;

  /// Двигался ли танк в последнем кадре (для траков/звука).
  bool moved = false;

  TankSpec get spec => kTankSpecs[kind]!;

  bool get frozen => freezeTimer > 0;
  bool get shielded => shieldTimer > 0;
  bool get alive => hp > 0;

  /// Центр танка в суб-клетках.
  int get cx => sx + TankGeo.tankSize ~/ 2;
  int get cy => sy + TankGeo.tankSize ~/ 2;

  /// Центр в нормализованных координатах.
  Point<double> get centerNorm => Point(TankGeo.norm(cx), TankGeo.norm(cy));
}

/// Пуля. Позиция — точка-остриё в суб-клетках (double ради плавности и
/// субшага анти-туннелинга).
class Bullet {
  Bullet({
    required this.id,
    required this.ownerId,
    required this.owner,
    required this.x,
    required this.y,
    required this.dir,
    required this.speed,
    required this.power,
  });

  final int id;
  final int ownerId;
  final BulletOwner owner;
  double x;
  double y;
  final Dir dir;
  final double speed;
  final int power;
  bool dead = false;

  bool get byPlayer => owner == BulletOwner.player;

  Point<double> get posNorm => Point(TankGeo.norm(x), TankGeo.norm(y));
}

/// Бонус на поле.
class PowerUp {
  PowerUp({required this.type, required this.tileX, required this.tileY});

  final PowerUpType type;
  final int tileX;
  final int tileY;

  /// Фаза мигания (для рендера).
  double blink = 0;

  /// Остаток жизни бонуса, сек.
  double timer = kPowerUpLifetime;

  Point<double> get centerNorm => TankGeo.tileCenterNorm(tileX, tileY);
}

/// База-орёл. Занимает один тайл; разрушение = проигрыш.
class Eagle {
  Eagle({required this.tileX, required this.tileY});

  final int tileX;
  final int tileY;
  bool destroyed = false;

  Point<double> get centerNorm => TankGeo.tileCenterNorm(tileX, tileY);
}
