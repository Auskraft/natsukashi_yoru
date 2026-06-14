import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/components/control_pad.dart';
import '../../core/input/control_scheme.dart';
import '../../core/storage/game_storage.dart';
import 'components/snake_logic.dart';
import 'game/snake_flame_game.dart';
import 'ui/snake_overlays.dart';

/// Точка входа фичи «Snake»: хостит [SnakeFlameGame], ловит свайпы и рисует
/// поверх игры оверлей по текущей фазе. Рекорд/стрик пишутся в [GameStorage].
///
/// Оверлеи — обычный Flutter `Stack`, переключаемый по [SnakeFlameGame.phase].
/// Так исключено наложение экранов (раньше rebuild возвращал стартовый оверлей).
class SnakeScreen extends StatefulWidget {
  const SnakeScreen({super.key});

  @override
  State<SnakeScreen> createState() => _SnakeScreenState();
}

class _SnakeScreenState extends State<SnakeScreen> {
  static const _gameId = 'snake';

  late final SnakeFlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;
  Offset _drag = Offset.zero;
  late ControlScheme _controls;
  StreamSubscription<AccelerometerEvent>? _accel;
  Direction? _lastTiltDir;
  double? _baseX;
  double? _baseY;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _controls = GameStorage.instance.controlScheme(_gameId);
    _game = SnakeFlameGame(
      onGameOver: _handleGameOver,
      bottomInset: _bottomReserve(_controls),
    );
    if (_controls == ControlScheme.gyro) {
      _accel = accelerometerEventStream().listen(_onTilt);
    }
  }

  @override
  void dispose() {
    _accel?.cancel();
    super.dispose();
  }

  // Управление наклоном: телефон наклоняешь — змейка едет туда. Базовый наклон
  // калибруется по первому замеру (любой хват). Пороги/знаки — на глаз; если оси
  // инвертированы под твой хват, поменяем знаки. Срабатывает при смене курса.
  void _onTilt(AccelerometerEvent e) {
    _baseX ??= e.x;
    _baseY ??= e.y;
    final dx = e.x - _baseX!;
    final dy = e.y - _baseY!;
    const threshold = 2.5;
    Direction? dir;
    if (dx.abs() > dy.abs()) {
      if (dx > threshold) {
        dir = Direction.left;
      } else if (dx < -threshold) {
        dir = Direction.right;
      }
    } else {
      if (dy > threshold) {
        dir = Direction.down;
      } else if (dy < -threshold) {
        dir = Direction.up;
      }
    }
    if (dir != null && dir != _lastTiltDir) {
      _lastTiltDir = dir;
      _game.steer(dir);
    }
  }

  void _handleGameOver(int score) {
    final storage = GameStorage.instance;
    final prevBest = storage.highScore(_gameId);
    final record = score > prevBest;

    setState(() {
      _lastScore = score;
      _isRecord = record;
      _best = record ? score : prevBest;
    });

    // Персист — не блокирует показ оверлея.
    unawaited(storage.submitScore(_gameId, score));
    unawaited(storage.registerPlay(DateTime.now()));
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _drag += d.delta;
    if (_drag.distance < 24) return;
    final dir = _drag.dx.abs() > _drag.dy.abs()
        ? (_drag.dx > 0 ? Direction.right : Direction.left)
        : (_drag.dy > 0 ? Direction.down : Direction.up);
    _game.steer(dir);
    _drag = Offset.zero;
  }

  static Direction _dirOf(PadDir d) => switch (d) {
        PadDir.up => Direction.up,
        PadDir.down => Direction.down,
        PadDir.left => Direction.left,
        PadDir.right => Direction.right,
      };

  // Сколько резервировать снизу под выбранную схему (чтобы поле не налезало
  // на контролы). Раздельным раскладкам нужно меньше места, чем крестовине.
  static double _bottomReserve(ControlScheme s) => switch (s) {
        ControlScheme.gestures ||
        ControlScheme.gyro ||
        ControlScheme.tetrisButtons ||
        ControlScheme.paddleButtons =>
          28,
        ControlScheme.dpadSplitLeft || ControlScheme.dpadSplitRight => 160,
        ControlScheme.turnButtons => 150,
        ControlScheme.dpad || ControlScheme.joystick => 212,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanStart: (_) => _drag = Offset.zero,
        onPanUpdate: _onPanUpdate,
        child: Stack(
          children: [
            GameWidget<SnakeFlameGame>(game: _game),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: Listenable.merge([_game.phase, _game.isPaused]),
                builder: (context, _) {
                  if (_game.isPaused.value) {
                    return PausePanel(
                      onResume: _game.togglePause,
                      onRestart: _game.start,
                      onExit: () => Navigator.of(context).pop(),
                    );
                  }
                  switch (_game.phase.value) {
                    case SnakePhase.ready:
                      return SnakeReadyOverlay(onStart: _game.start);
                    case SnakePhase.running:
                      return SnakeHud(game: _game, best: _best);
                    case SnakePhase.dead:
                      return SnakeGameOverOverlay(
                        score: _lastScore,
                        best: _best,
                        isRecord: _isRecord,
                        onRetry: _game.start,
                        onExit: () => Navigator.of(context).pop(),
                      );
                  }
                },
              ),
            ),
            // Экранные контролы (если выбраны в «Управление»); жесты остаются.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: Listenable.merge([_game.phase, _game.isPaused]),
                builder: (context, _) {
                  final running = _game.phase.value == SnakePhase.running &&
                      !_game.isPaused.value;
                  return ControlOverlay(
                    scheme: _controls,
                    visible: running,
                    accent: const Color(0xFF34D399),
                    onDir: (d) => _game.steer(_dirOf(d)),
                    onTurn: (cw) => _game.turn(cw),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
