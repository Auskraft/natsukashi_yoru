import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/control_pad.dart';
import '../../core/components/overlay_kit.dart';
import '../../core/input/control_scheme.dart';
import '../../core/storage/game_storage.dart';
import 'game/breakout_flame_game.dart';
import 'ui/breakout_overlays.dart';

/// Точка входа фичи «Breakout»: хостит [BreakoutFlameGame], ведёт ракетку за
/// пальцем (горизонтальная тяга) и тапом запускает приклеенный мяч. Рисует
/// поверх игры оверлей по текущей фазе. Рекорд/стрик пишутся в [GameStorage].
class BreakoutScreen extends StatefulWidget {
  const BreakoutScreen({super.key});

  @override
  State<BreakoutScreen> createState() => _BreakoutScreenState();
}

class _BreakoutScreenState extends State<BreakoutScreen> {
  static const _gameId = 'breakout';

  late final BreakoutFlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;
  late ControlScheme _controls;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _controls = GameStorage.instance.controlScheme(_gameId);
    _game = BreakoutFlameGame(
      onGameOver: _handleGameOver,
      bottomInset: _controls == ControlScheme.paddleButtons ? 130 : 28,
    );
  }

  @override
  void dispose() {
    // Сохранить рекорд и при выходе живым: счёт копится по уровням, а game over
    // может не наступить (игрок ушёл в меню) — иначе прогресс терялся бы.
    final s = _game.score.value;
    if (s > 0) {
      unawaited(GameStorage.instance.submitScore(_gameId, s));
      unawaited(GameStorage.instance.registerPlay(DateTime.now()));
    }
    super.dispose();
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

  void _onTapDown(TapDownDetails d) {
    // При кнопочной схеме поле не реагирует — управление через пад.
    if (_controls == ControlScheme.paddleButtons) return;
    // Тап одновременно наводит ракетку и запускает приклеенный мяч.
    _game.aimAt(d.localPosition.dx);
    _game.launch();
  }

  void _onPanStart(DragStartDetails d) {
    if (_controls == ControlScheme.paddleButtons) return;
    _game.aimAt(d.localPosition.dx);
    _game.launch();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_controls == ControlScheme.paddleButtons) return;
    _game.aimAt(d.localPosition.dx);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTapDown: _onTapDown,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        child: Stack(
          children: [
            GameWidget<BreakoutFlameGame>(game: _game),
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
                    case BreakoutPhase.ready:
                      return ReadyPanel(
                        emoji: '🧱',
                        title: 'Bricks',
                        subtitle:
                            'Веди ракетку пальцем • Тап — запуск мяча • Разбей все кирпичи',
                        onStart: _game.start,
                      );
                    case BreakoutPhase.running:
                      return BreakoutHud(game: _game, best: _best);
                    case BreakoutPhase.dead:
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
                  final running = _game.phase.value == BreakoutPhase.running &&
                      !_game.isPaused.value;
                  return PaddleControls(
                    scheme: _controls,
                    visible: running,
                    accent: const Color(0xFF60A5FA),
                    onMove: _game.setPaddleDir,
                    onLaunch: _game.launch,
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
