import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/storage/game_storage.dart';
import 'game/block_puzzle_flame_game.dart';
import 'ui/block_puzzle_overlays.dart';

/// Точка входа фичи «1010!»: хостит [BlockPuzzleFlameGame], пробрасывает жесты
/// перетаскивания (взял фигуру из лотка → ведёшь → отпустил на поле) и рисует
/// оверлей по фазе. Рекорд/стрик пишутся в [GameStorage].
class BlockPuzzleScreen extends StatefulWidget {
  const BlockPuzzleScreen({super.key});

  @override
  State<BlockPuzzleScreen> createState() => _BlockPuzzleScreenState();
}

class _BlockPuzzleScreenState extends State<BlockPuzzleScreen> {
  static const _gameId = 'block_puzzle';

  late final BlockPuzzleFlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _game = BlockPuzzleFlameGame(onGameOver: _handleGameOver);
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

    unawaited(storage.submitScore(_gameId, score));
    unawaited(storage.registerPlay(DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanStart: (d) => _game.onDragStart(d.localPosition),
        onPanUpdate: (d) => _game.onDragUpdate(d.localPosition),
        onPanEnd: (_) => _game.onDragEnd(),
        onPanCancel: _game.onDragCancel,
        child: Stack(
          children: [
            GameWidget<BlockPuzzleFlameGame>(game: _game),
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
                    case BlockPuzzlePhase.ready:
                      return ReadyPanel(
                        emoji: '🧩',
                        title: '1010!',
                        subtitle:
                            'Тяни фигуры на поле • Собирай строки и столбцы',
                        onStart: _game.start,
                      );
                    case BlockPuzzlePhase.running:
                      return BlockPuzzleHud(game: _game, best: _best);
                    case BlockPuzzlePhase.dead:
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
