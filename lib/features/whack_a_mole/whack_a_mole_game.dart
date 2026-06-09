import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/storage/game_storage.dart';
import 'game/whack_a_mole_flame_game.dart';
import 'ui/whack_a_mole_overlays.dart';

/// Точка входа фичи «Whack-a-Mole»: хостит [WhackaMoleFlameGame], ловит тап по
/// норе и рисует оверлей по текущей фазе. Рекорд/стрик пишутся в [GameStorage].
class WhackAMoleScreen extends StatefulWidget {
  const WhackAMoleScreen({super.key});

  @override
  State<WhackAMoleScreen> createState() => _WhackAMoleScreenState();
}

class _WhackAMoleScreenState extends State<WhackAMoleScreen> {
  static const _gameId = 'whack_a_mole';

  late final WhackaMoleFlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _game = WhackaMoleFlameGame(onGameOver: _handleGameOver);
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
        onTapDown: (d) => _game.whackAt(d.localPosition),
        child: Stack(
          children: [
            GameWidget<WhackaMoleFlameGame>(game: _game),
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
                    case WhackPhase.ready:
                      return ReadyPanel(
                        emoji: '🐹',
                        title: 'Whack-a-Mole',
                        subtitle: 'Блиц 30 секунд • Бей кротов, что вылезли',
                        onStart: _game.start,
                      );
                    case WhackPhase.running:
                      return WhackAMoleHud(game: _game, best: _best);
                    case WhackPhase.dead:
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
