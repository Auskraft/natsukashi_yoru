import 'dart:math';

import 'tank_entities.dart';

/// Директор спавна: выдаёт врагов из ростера по таймеру, не превышая лимит
/// одновременно живых. Точки спавна — тайловые координаты (обычно верхний ряд).
///
/// Чистый и детерминированный: вся случайность (выбор точки, бонус-носители) —
/// на стороне [TanksLogic] с инъекцией Random.
class SpawnDirector {
  SpawnDirector({
    required this.spawnTiles,
    required List<TankKind> roster,
    this.maxConcurrent = 4,
    this.interval = 2.2,
    this.firstDelay = 0.8,
  }) : _roster = List<TankKind>.of(roster);

  /// Тайлы-точки спавна (верхний-левый угол области 2×2 танка).
  final List<Point<int>> spawnTiles;
  final List<TankKind> _roster;

  /// Максимум одновременно живых врагов.
  final int maxConcurrent;

  /// Интервал между спавнами, сек.
  final double interval;

  /// Задержка перед первым спавном, сек.
  final double firstDelay;

  int _index = 0;
  double _timer = 0;
  bool _started = false;

  int get total => _roster.length;
  int get remaining => _roster.length - _index;
  bool get done => _index >= _roster.length;

  /// Тик таймера; true — пора спавнить (подошёл интервал и есть свободное место).
  bool ready(double dt, int aliveCount) {
    if (done) return false;
    _timer += dt;
    final wait = _started ? interval : firstDelay;
    return _timer >= wait && aliveCount < maxConcurrent;
  }

  /// Взять следующий тип из ростера. Вызывать только когда [ready] вернул true
  /// и есть свободная точка спавна.
  TankKind next() {
    _timer = 0;
    _started = true;
    return _roster[_index++];
  }
}
