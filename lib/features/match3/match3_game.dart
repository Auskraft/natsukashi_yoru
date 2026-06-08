import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/storage/game_storage.dart';
import 'game/match3_flame_game.dart';
import 'ui/match3_overlays.dart';

/// Точка входа фичи «Match3»: хостит [Match3FlameGame], ловит свайп фишки
/// в сторону соседа (обмен) и рисует оверлей по фазе.
class Match3Screen extends StatefulWidget {
  const Match3Screen({super.key});

  @override
  State<Match3Screen> createState() => _Match3ScreenState();
}

class _Match3ScreenState extends State<Match3Screen> {
  static const _gameId = 'match3';

  late final Match3FlameGame _game;
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
    _game = Match3FlameGame(onGameOver: _handleGameOver);
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
            GameWidget<Match3FlameGame>(game: _game),
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
                    case Match3Phase.ready:
                      return ReadyPanel(
                        emoji: '💎',
                        title: 'Match3',
                        subtitle: 'Блиц 60 секунд • Свайпни фишку к соседу',
                        onStart: _game.start,
                      );
                    case Match3Phase.running:
                      return Match3Hud(game: _game, best: _best);
                    case Match3Phase.dead:
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
