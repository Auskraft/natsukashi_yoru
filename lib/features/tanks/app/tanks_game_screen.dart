import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/components/dpad_control.dart';
import '../../../core/components/overlay_kit.dart';
import '../../../core/storage/game_storage.dart';
import '../game/tanks_flame_game.dart';
import '../logic/tank_entities.dart';
import '../ui/tanks_overlays.dart';

/// Экран-хост боя «Танчиков»: держит [TanksFlameGame], рисует поверх него
/// оверлей по фазе/паузе и панель управления (D-pad + огонь). Рекорд/стрик
/// пишутся в [GameStorage]. На фазе 2 уровень — демо (буферный, до парсера).
class TanksGameScreen extends StatefulWidget {
  const TanksGameScreen({super.key});

  @override
  State<TanksGameScreen> createState() => _TanksGameScreenState();
}

class _TanksGameScreenState extends State<TanksGameScreen> {
  static const _gameId = 'tanks_campaign';

  late final TanksFlameGame _game;
  late int _best;
  int _lastScore = 0;
  bool _isRecord = false;

  @override
  void initState() {
    super.initState();
    _best = GameStorage.instance.highScore(_gameId);
    _game = TanksFlameGame(onGameOver: _handleGameOver);
  }

  @override
  void dispose() {
    final s = _game.score.value;
    if (s > 0) {
      unawaited(GameStorage.instance.submitScore(_gameId, s));
      unawaited(GameStorage.instance.registerPlay(DateTime.now()));
    }
    super.dispose();
  }

  void _handleGameOver(int score, bool win) {
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

  /// Выход «в меню». Пока (фазы 2–3) игра — корневой экран, и popать некуда
  /// (это давало чёрный экран), поэтому возвращаемся на стартовый экран игры.
  /// В фазе 5, когда появится домашняя витрина, pop вернёт на неё.
  void _exit() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      _game.toReady();
    }
  }

  Dir? _toDir(AxisDirection? a) => switch (a) {
        null => null,
        AxisDirection.up => Dir.up,
        AxisDirection.down => Dir.down,
        AxisDirection.left => Dir.left,
        AxisDirection.right => Dir.right,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GameWidget<TanksFlameGame>(game: _game),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_game.phase, _game.isPaused]),
              builder: (context, _) {
                if (_game.isPaused.value) {
                  return PausePanel(
                    onResume: _game.togglePause,
                    onRestart: _game.start,
                    onExit: _exit,
                  );
                }
                switch (_game.phase.value) {
                  case TanksPhase.ready:
                    return ReadyPanel(
                      emoji: '🪖',
                      title: 'Танчики',
                      subtitle:
                          'Веди крестом • кнопка — огонь • защити базу и зачисти врагов',
                      onStart: _game.start,
                    );
                  case TanksPhase.running:
                    return Stack(
                      children: [
                        TanksHud(game: _game),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: SafeArea(
                            top: false,
                            child: DpadControl(
                              onDirection: (a) => _game.setMoveDir(_toDir(a)),
                              onFireChanged: _game.setFire,
                            ),
                          ),
                        ),
                      ],
                    );
                  case TanksPhase.dead:
                    return GameOverPanel(
                      score: _lastScore,
                      best: _best,
                      isRecord: _isRecord,
                      onRetry: _game.start,
                      onExit: _exit,
                    );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
