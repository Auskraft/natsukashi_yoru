import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/storage/game_storage.dart';
import 'game/lights_out_flame_game.dart';
import 'ui/lights_out_overlays.dart';

/// Точка входа фичи «Lights Out»: тап переключает клетку и её ортогональных
/// соседей; цель — погасить все лампочки. Ретеншн — лучшее (минимальное) число
/// ходов (меньше лучше, через bestTime/submitTime) + дневной стрик.
class LightsOutScreen extends StatefulWidget {
  const LightsOutScreen({super.key});

  @override
  State<LightsOutScreen> createState() => _LightsOutScreenState();
}

class _LightsOutScreenState extends State<LightsOutScreen> {
  static const _gameId = 'lights_out';

  late final LightsOutFlameGame _game;
  int _lastMoves = 0;
  late int _bestMoves;
  bool _isRecord = false;

  @override
  void initState() {
    super.initState();
    // Семантика «меньше — лучше»: храним лучшее число ходов как bestTime.
    _bestMoves = GameStorage.instance.bestTime(_gameId);
    _game = LightsOutFlameGame(onWin: _handleWin);
  }

  void _handleWin(int moves) {
    final storage = GameStorage.instance;
    final prevBest = storage.bestTime(_gameId);
    final record = prevBest == 0 || moves < prevBest;

    setState(() {
      _lastMoves = moves;
      _isRecord = record;
      _bestMoves = record ? moves : prevBest;
    });

    unawaited(storage.submitTime(_gameId, moves));
    unawaited(storage.registerPlay(DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTapUp: (d) => _game.tapAt(d.localPosition),
        child: Stack(
          children: [
            GameWidget<LightsOutFlameGame>(game: _game),
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
                    case LightsOutPhase.ready:
                      return ReadyPanel(
                        emoji: '💡',
                        title: 'Lights Out',
                        subtitle:
                            'Погаси все лампочки • Тап переключает клетку и соседей',
                        onStart: _game.start,
                      );
                    case LightsOutPhase.running:
                      return LightsOutHud(game: _game, best: _bestMoves);
                    case LightsOutPhase.won:
                      return GameOverPanel(
                        score: _lastMoves,
                        best: _bestMoves,
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
