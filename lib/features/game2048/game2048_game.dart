import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/storage/game_storage.dart';
import 'components/game2048_logic.dart';
import 'game/game2048_flame_game.dart';
import 'ui/game2048_overlays.dart';

/// Точка входа фичи «2048»: хостит [Game2048FlameGame], ловит свайпы и рисует
/// поверх игры оверлей по текущей фазе. Рекорд/стрик пишутся в [GameStorage].
///
/// Режим — endless + рекорд: чем выше счёт, тем лучше ([GameStorage.submitScore]).
class Game2048Screen extends StatefulWidget {
  const Game2048Screen({super.key});

  @override
  State<Game2048Screen> createState() => _Game2048ScreenState();
}

class _Game2048ScreenState extends State<Game2048Screen> {
  static const _gameId = 'game2048';

  // Порог распознавания свайпа (в логических пикселях).
  static const double _swipeThreshold = 24;

  late final Game2048FlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;

  Offset _drag = Offset.zero;
  // Один ход на жест: после срабатывания игнорируем остаток текущего свайпа.
  bool _consumed = false;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _game = Game2048FlameGame(onGameOver: _handleGameOver);
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
    if (_consumed) return;
    _drag += d.delta;
    if (_drag.distance < _swipeThreshold) return;
    final dir = _drag.dx.abs() > _drag.dy.abs()
        ? (_drag.dx > 0 ? SlideDirection.right : SlideDirection.left)
        : (_drag.dy > 0 ? SlideDirection.down : SlideDirection.up);
    _game.swipe(dir);
    _consumed = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanStart: (_) {
          _drag = Offset.zero;
          _consumed = false;
        },
        onPanUpdate: _onPanUpdate,
        onPanEnd: (_) => _consumed = false,
        child: Stack(
          children: [
            GameWidget<Game2048FlameGame>(game: _game),
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
                    case Game2048Phase.ready:
                      return ReadyPanel(
                        emoji: '🔢',
                        title: '2048',
                        subtitle:
                            'Свайп двигает плитки • Одинаковые сливаются • Собери 2048',
                        onStart: _game.start,
                      );
                    case Game2048Phase.running:
                      return Game2048Hud(game: _game, best: _best);
                    case Game2048Phase.dead:
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
