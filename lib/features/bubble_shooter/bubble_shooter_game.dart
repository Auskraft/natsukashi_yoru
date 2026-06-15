import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/control_pad.dart';
import '../../core/components/overlay_kit.dart';
import '../../core/input/control_scheme.dart';
import '../../core/storage/game_storage.dart';
import 'game/bubble_shooter_flame_game.dart';
import 'ui/bubble_shooter_overlays.dart';

/// Точка входа фичи «Bubble Shooter»: хостит [BubbleShooterFlameGame], наводит
/// пушку перетаскиванием и стреляет по отпусканию пальца или тапу. Оверлей —
/// обычный Flutter `Stack`, переключаемый по фазе. Ретеншн — рекорд счёта +
/// дневной стрик в [GameStorage].
class BubbleShooterScreen extends StatefulWidget {
  const BubbleShooterScreen({super.key});

  @override
  State<BubbleShooterScreen> createState() => _BubbleShooterScreenState();
}

class _BubbleShooterScreenState extends State<BubbleShooterScreen> {
  static const _gameId = 'bubble_shooter';

  late final BubbleShooterFlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;
  late ControlScheme _controls;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _controls = GameStorage.instance.controlScheme(_gameId);
    _game = BubbleShooterFlameGame(onGameOver: _handleGameOver);
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

  @override
  Widget build(BuildContext context) {
    // При схеме «кнопки» полностью отключаем жесты поля (null-обработчики):
    // иначе их pan-распознаватель перехватывает удержание кнопок прицела.
    final buttons = _controls == ControlScheme.paddleButtons;
    return Scaffold(
      body: GestureDetector(
        onTapDown: buttons ? null : (d) => _game.aimAt(d.localPosition),
        onTapUp: buttons ? null : (_) => _game.shoot(),
        onPanStart: buttons ? null : (d) => _game.aimAt(d.localPosition),
        onPanUpdate: buttons ? null : (d) => _game.aimAt(d.localPosition),
        onPanEnd: buttons ? null : (_) => _game.shoot(),
        child: Stack(
          children: [
            GameWidget<BubbleShooterFlameGame>(game: _game),
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
                    case BubbleShooterPhase.ready:
                      return ReadyPanel(
                        emoji: '🫧',
                        title: 'Bubble Shooter',
                        subtitle:
                            'Веди — целься • Отпусти или тапни — выстрел • Собери 3+ в цвет',
                        onStart: _game.start,
                      );
                    case BubbleShooterPhase.running:
                      return BubbleShooterHud(game: _game, best: _best);
                    case BubbleShooterPhase.dead:
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: Listenable.merge([_game.phase, _game.isPaused]),
                builder: (context, _) {
                  final running =
                      _game.phase.value == BubbleShooterPhase.running &&
                          !_game.isPaused.value;
                  return PaddleControls(
                    scheme: _controls,
                    visible: running,
                    accent: const Color(0xFFFB7185),
                    onMove: _game.setAimDir,
                    onLaunch: _game.shoot,
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
