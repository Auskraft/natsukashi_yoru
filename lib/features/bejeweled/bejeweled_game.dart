import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/storage/game_storage.dart';
import 'game/bejeweled_flame_game.dart';
import 'ui/bejeweled_overlays.dart';

/// Точка входа фичи «Bejeweled»: свайп камня к соседу (обмен), бюджет ходов,
/// особые камни. Оверлей по фазе, рекорд/стрик в [GameStorage].
class BejeweledScreen extends StatefulWidget {
  const BejeweledScreen({super.key});

  @override
  State<BejeweledScreen> createState() => _BejeweledScreenState();
}

class _BejeweledScreenState extends State<BejeweledScreen> {
  static const _gameId = 'bejeweled';

  late final BejeweledFlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;

  Point<int>? _startCell;
  Offset _drag = Offset.zero;
  bool _swapped = false;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _game = BejeweledFlameGame(onGameOver: _handleGameOver);
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

  void _onPanStart(DragStartDetails d) {
    _startCell = _game.cellAt(d.localPosition);
    _drag = Offset.zero;
    _swapped = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_swapped || _startCell == null) return;
    _drag += d.delta;
    if (_drag.distance < 18) return;

    final start = _startCell!;
    final target = _drag.dx.abs() > _drag.dy.abs()
        ? Point(start.x + (_drag.dx > 0 ? 1 : -1), start.y)
        : Point(start.x, start.y + (_drag.dy > 0 ? 1 : -1));
    _game.trySwapCells(start, target);
    _swapped = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        child: Stack(
          children: [
            GameWidget<BejeweledFlameGame>(game: _game),
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
                    case BejeweledPhase.ready:
                      return ReadyPanel(
                        emoji: '💠',
                        title: 'Bejeweled',
                        subtitle:
                            '25 ходов • Свайп к соседу • матч-4/5 → особые камни',
                        onStart: _game.start,
                      );
                    case BejeweledPhase.running:
                      return BejeweledHud(game: _game, best: _best);
                    case BejeweledPhase.dead:
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
