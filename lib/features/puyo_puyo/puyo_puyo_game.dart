import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/storage/game_storage.dart';
import 'game/puyo_puyo_flame_game.dart';
import 'ui/puyo_puyo_overlays.dart';

/// Точка входа фичи «Puyo Puyo»: тап — поворот, горизонтальная тяга — сдвиг
/// пары, свайп вниз — hard drop. Оверлей по фазе, рекорд/стрик в [GameStorage].
class PuyoPuyoScreen extends StatefulWidget {
  const PuyoPuyoScreen({super.key});

  @override
  State<PuyoPuyoScreen> createState() => _PuyoPuyoScreenState();
}

class _PuyoPuyoScreenState extends State<PuyoPuyoScreen> {
  static const _gameId = 'puyo_puyo';

  late final PuyoPuyoFlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;

  double _dxStep = 0;
  double _dxTotal = 0;
  double _dyTotal = 0;
  bool _hardDropped = false;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _game = PuyoPuyoFlameGame(onGameOver: _handleGameOver);
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

  void _onPanStart(DragStartDetails _) {
    _dxStep = 0;
    _dxTotal = 0;
    _dyTotal = 0;
    _hardDropped = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _dxTotal += d.delta.dx;
    _dyTotal += d.delta.dy;

    if (!_hardDropped && _dyTotal > 40 && _dyTotal > _dxTotal.abs()) {
      _game.hardDrop();
      _hardDropped = true;
      return;
    }
    if (_hardDropped) return;

    _dxStep += d.delta.dx;
    final cw = _game.cellSize > 0 ? _game.cellSize : 24.0;
    while (_dxStep.abs() >= cw) {
      if (_dxStep > 0) {
        _game.moveRight();
        _dxStep -= cw;
      } else {
        _game.moveLeft();
        _dxStep += cw;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _game.rotate,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        child: Stack(
          children: [
            GameWidget<PuyoPuyoFlameGame>(game: _game),
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
                    case PuyoPhase.ready:
                      return ReadyPanel(
                        emoji: '🟢',
                        title: 'Drops',
                        subtitle:
                            'Собери 4+ одного цвета • Тап — поворот • Свайп вниз — сброс',
                        onStart: _game.start,
                      );
                    case PuyoPhase.running:
                      return PuyoHud(game: _game, best: _best);
                    case PuyoPhase.dead:
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
