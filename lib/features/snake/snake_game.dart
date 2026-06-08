import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/storage/game_storage.dart';
import 'components/snake_logic.dart';
import 'game/snake_flame_game.dart';
import 'ui/snake_overlays.dart';

/// Точка входа фичи «Snake»: хостит [SnakeFlameGame], ловит свайпы,
/// управляет оверлеями и пишет рекорд/стрик в [GameStorage].
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
    _game.phase.addListener(_onPhase);
  }

  @override
  void dispose() {
    _game.phase.removeListener(_onPhase);
    super.dispose();
  }

  void _onPhase() {
    switch (_game.phase.value) {
      case SnakePhase.ready:
        _setOverlays({'ready'});
      case SnakePhase.running:
        _setOverlays({'hud'});
      case SnakePhase.dead:
        // Оверлей конца игры показывает _handleGameOver (после подсчёта рекорда).
        break;
    }
  }

  void _setOverlays(Set<String> names) {
    for (final n in List<String>.from(_game.overlays.activeOverlays)) {
      _game.overlays.remove(n);
    }
    for (final n in names) {
      _game.overlays.add(n);
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
    _setOverlays({'gameover'});

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
        child: GameWidget<SnakeFlameGame>(
          game: _game,
          overlayBuilderMap: {
            'hud': (_, game) => SnakeHud(game: game, best: _best),
            'ready': (_, game) => SnakeReadyOverlay(onStart: game.start),
            'gameover': (_, _) => SnakeGameOverOverlay(
                  score: _lastScore,
                  best: _best,
                  isRecord: _isRecord,
                  onRetry: _game.start,
                  onExit: () => Navigator.of(context).pop(),
                ),
          },
          initialActiveOverlays: const ['ready'],
        ),
      ),
    );
  }
}
