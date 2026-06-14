import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/control_pad.dart';
import '../../core/components/overlay_kit.dart';
import '../../core/input/control_scheme.dart';
import '../../core/storage/game_storage.dart';
import 'game/tetris_flame_game.dart';
import 'ui/tetris_overlays.dart';

/// Точка входа фичи «Tetris»: хостит [TetrisFlameGame], раскладывает жесты
/// (тап — поворот, горизонтальная тяга — сдвиг по клеткам, свайп вниз — hard
/// drop) и рисует оверлей по фазе. Рекорд/стрик пишутся в [GameStorage].
class TetrisScreen extends StatefulWidget {
  const TetrisScreen({super.key});

  @override
  State<TetrisScreen> createState() => _TetrisScreenState();
}

class _TetrisScreenState extends State<TetrisScreen> {
  static const _gameId = 'tetris';

  late final TetrisFlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;

  // Аккумуляторы жеста.
  double _dxStep = 0;
  double _dxTotal = 0;
  double _dyTotal = 0;
  bool _hardDropped = false;
  late ControlScheme _controls;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _controls = GameStorage.instance.controlScheme(_gameId);
    _game = TetrisFlameGame(
      onGameOver: _handleGameOver,
      bottomInset: _bottomReserve(_controls),
    );
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

    // Решительный свайп вниз — hard drop (однократно за жест).
    if (!_hardDropped && _dyTotal > 40 && _dyTotal > _dxTotal.abs()) {
      _game.hardDrop();
      _hardDropped = true;
      return;
    }
    if (_hardDropped) return;

    // Горизонтальная тяга — сдвиг по клеткам.
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

  // Резерв снизу под выбранную схему (для тетрис-пада).
  static double _bottomReserve(ControlScheme s) =>
      s == ControlScheme.tetrisButtons ? 130 : 44;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _game.rotate,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        child: Stack(
          children: [
            GameWidget<TetrisFlameGame>(game: _game),
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
                    case TetrisPhase.ready:
                      return TetrisReadyOverlay(onStart: _game.start);
                    case TetrisPhase.running:
                      return TetrisHud(game: _game, best: _best);
                    case TetrisPhase.dead:
                      return TetrisGameOverOverlay(
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: Listenable.merge([_game.phase, _game.isPaused]),
                builder: (context, _) {
                  final running = _game.phase.value == TetrisPhase.running &&
                      !_game.isPaused.value;
                  return TetrisControls(
                    scheme: _controls,
                    visible: running,
                    accent: const Color(0xFF818CF8),
                    onLeft: _game.moveLeft,
                    onRight: _game.moveRight,
                    onRotate: _game.rotate,
                    onDrop: _game.hardDrop,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
