import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/storage/game_storage.dart';
import 'game/stack_tower_flame_game.dart';
import 'ui/stack_tower_overlays.dart';

/// Точка входа фичи «Stack»: хостит [StackFlameGame], ловит тап (фиксация
/// блока) и рисует оверлей по текущей фазе. Рекорд (выше — лучше) и дневной
/// стрик пишутся в [GameStorage].
class StackTowerScreen extends StatefulWidget {
  const StackTowerScreen({super.key});

  @override
  State<StackTowerScreen> createState() => _StackTowerScreenState();
}

class _StackTowerScreenState extends State<StackTowerScreen> {
  static const _gameId = 'stack_tower';

  late final StackFlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _game = StackFlameGame(onGameOver: _handleGameOver);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTapDown: (_) => _game.drop(),
        child: Stack(
          children: [
            GameWidget<StackFlameGame>(game: _game),
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
                    case StackPhase.ready:
                      return ReadyPanel(
                        emoji: '🗼',
                        title: 'Stack',
                        subtitle:
                            'Тап — поставить блок • Точно по центру — серия идеалов',
                        onStart: _game.start,
                      );
                    case StackPhase.running:
                      return StackTowerHud(game: _game, best: _best);
                    case StackPhase.dead:
                      return GameOverPanel(
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
