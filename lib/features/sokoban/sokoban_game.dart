import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/overlay_kit.dart';
import '../../core/storage/game_storage.dart';
import 'components/sokoban_logic.dart';
import 'game/sokoban_flame_game.dart';
import 'ui/sokoban_overlays.dart';

/// Точка входа фичи «Сокобан»: хостит [SokobanFlameGame], ловит свайпы по 4
/// сторонам (экран → направление хода) и рисует оверлей по фазе. Ретеншн —
/// лучший результат в ХОДАХ (меньше лучше) + дневной стрик в [GameStorage].
class SokobanScreen extends StatefulWidget {
  const SokobanScreen({super.key});

  @override
  State<SokobanScreen> createState() => _SokobanScreenState();
}

class _SokobanScreenState extends State<SokobanScreen> {
  static const _gameId = 'sokoban';

  late final SokobanFlameGame _game;
  late int _bestMoves;
  int _lastMoves = 0;
  bool _isRecord = false;
  bool _hasNext = false;
  Offset _drag = Offset.zero;

  @override
  void initState() {
    super.initState();
    _bestMoves = GameStorage.instance.bestTime(_gameId);
    _game = SokobanFlameGame(onLevelSolved: _handleSolved);
  }

  void _handleSolved(int moves, int level) {
    final storage = GameStorage.instance;
    final prevBest = storage.bestTime(_gameId);
    final record = prevBest == 0 || moves < prevBest;

    setState(() {
      _lastMoves = moves;
      _isRecord = record;
      _bestMoves = record ? moves : prevBest;
      _hasNext = level < kSokobanLevels.length;
    });

    // Персист — не блокирует показ оверлея. «Меньше — лучше» через submitTime.
    unawaited(storage.submitTime(_gameId, moves));
    unawaited(storage.registerPlay(DateTime.now()));
  }

  void _onPanStart(DragStartDetails _) => _drag = Offset.zero;

  void _onPanUpdate(DragUpdateDetails d) {
    _drag += d.delta;
    if (_drag.distance < 24) return;
    final dir = _drag.dx.abs() > _drag.dy.abs()
        ? (_drag.dx > 0 ? SokoDir.right : SokoDir.left)
        : (_drag.dy > 0 ? SokoDir.down : SokoDir.up);
    _game.step(dir);
    _drag = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        child: Stack(
          children: [
            GameWidget<SokobanFlameGame>(game: _game),
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
                    case SokobanPhase.ready:
                      return ReadyPanel(
                        emoji: '📦',
                        title: 'Sokoban',
                        subtitle:
                            'Свайп — ход • Толкай ящики на цели • Меньше ходов — лучше',
                        onStart: _game.start,
                      );
                    case SokobanPhase.running:
                      return SokobanHud(game: _game);
                    case SokobanPhase.won:
                      return SokobanWonPanel(
                        moves: _lastMoves,
                        bestMoves: _bestMoves,
                        isRecord: _isRecord,
                        hasNext: _hasNext,
                        onNext: _game.advanceLevel,
                        onRestart: _game.restartLevel,
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
