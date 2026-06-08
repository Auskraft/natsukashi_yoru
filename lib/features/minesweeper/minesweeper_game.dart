import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/storage/game_storage.dart';
import 'game/minesweeper_flame_game.dart';
import 'ui/minesweeper_overlays.dart';

/// Точка входа фичи «Minesweeper»: тап — открыть клетку, удержание — флаг.
/// Ретеншн — лучшее ВРЕМЯ победы (меньше лучше) + дневной стрик.
class MinesweeperScreen extends StatefulWidget {
  const MinesweeperScreen({super.key});

  @override
  State<MinesweeperScreen> createState() => _MinesweeperScreenState();
}

class _MinesweeperScreenState extends State<MinesweeperScreen> {
  static const _gameId = 'minesweeper';

  late final MinesweeperFlameGame _game;
  bool _won = false;
  int _lastTime = 0;
  late int _bestTime;
  bool _isRecord = false;

  @override
  void initState() {
    super.initState();
    _bestTime = GameStorage.instance.bestTime(_gameId);
    _game = MinesweeperFlameGame(onOver: _handleOver);
  }

  void _handleOver(bool won, int seconds) {
    final storage = GameStorage.instance;
    final prevBest = storage.bestTime(_gameId);
    final record = won && (prevBest == 0 || seconds < prevBest);

    setState(() {
      _won = won;
      _lastTime = seconds;
      _isRecord = record;
      _bestTime = record ? seconds : prevBest;
    });

    if (won) unawaited(storage.submitTime(_gameId, seconds));
    unawaited(storage.registerPlay(DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTapUp: (d) => _game.revealAt(d.localPosition),
        onLongPressStart: (d) => _game.flagAt(d.localPosition),
        child: Stack(
          children: [
            GameWidget<MinesweeperFlameGame>(game: _game),
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
                    case MinesweeperPhase.ready:
                      return ReadyPanel(
                        emoji: '🚩',
                        title: 'Minesweeper',
                        subtitle:
                            'Открой все клетки без мин • Тап — открыть • Удержание — флаг',
                        onStart: _game.start,
                      );
                    case MinesweeperPhase.running:
                      return MinesweeperHud(game: _game);
                    case MinesweeperPhase.won:
                    case MinesweeperPhase.lost:
                      return MinesweeperEndPanel(
                        won: _won,
                        seconds: _lastTime,
                        bestSeconds: _bestTime,
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
