import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _game = SnakeFlameGame(onGameOver: _handleGameOver);
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
              child: ValueListenableBuilder<SnakePhase>(
                valueListenable: _game.phase,
                builder: (context, phase, _) {
                  switch (phase) {
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
          ],
        ),
      ),
    );
  }
}
