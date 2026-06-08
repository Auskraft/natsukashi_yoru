import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../components/tetris_logic.dart';
import '../game/tetris_flame_game.dart';
import 'tetris_style.dart';

/// HUD: счёт, рекорд, уровень/линии, превью следующей фигуры, бейдж комбо
/// и подсказка по управлению снизу.
class TetrisHud extends StatelessWidget {
  const TetrisHud({super.key, required this.game, required this.best});

  final TetrisFlameGame game;
  final int best;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: game.score,
                  builder: (_, score, _) =>
                      _Stat(label: 'СЧЁТ', value: '$score', color: Colors.white),
                ),
                ValueListenableBuilder<Tetromino>(
                  valueListenable: game.next,
                  builder: (_, t, _) => _NextBox(piece: t),
                ),
                _Stat(
                  label: 'РЕКОРД',
                  value: '$best',
                  color: const Color(0xFFFFD54F),
                  alignEnd: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: Listenable.merge([game.level, game.lines]),
              builder: (_, _) => Text(
                'УРОВЕНЬ ${game.level.value}     ·     ЛИНИИ ${game.lines.value}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: ValueListenableBuilder<int>(
                valueListenable: game.combo,
                builder: (_, combo, _) => AnimatedScale(
                  scale: combo >= 2 ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: _ComboBadge(combo: combo),
                ),
              ),
            ),
            const Spacer(),
            _ControlsHint(game: game),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _NextBox extends StatelessWidget {
  const _NextBox({required this.piece});

  final Tetromino piece;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'ДАЛЕЕ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 72,
          height: 44,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF161126),
            borderRadius: BorderRadius.circular(10),
          ),
          child: CustomPaint(painter: _NextPiecePainter(piece)),
        ),
      ],
    );
  }
}

class _NextPiecePainter extends CustomPainter {
  _NextPiecePainter(this.piece);

  final Tetromino piece;

  @override
  void paint(Canvas canvas, Size size) {
    final cells = tetrominoCells(piece, 0);
    final xs = cells.map((c) => c.x);
    final ys = cells.map((c) => c.y);
    final minX = xs.reduce(min), maxX = xs.reduce(max);
    final minY = ys.reduce(min), maxY = ys.reduce(max);
    final wCells = maxX - minX + 1;
    final hCells = maxY - minY + 1;
    final cell = min(size.width / wCells, size.height / hCells);
    final ox = (size.width - wCells * cell) / 2 - minX * cell;
    final oy = (size.height - hCells * cell) / 2 - minY * cell;
    final color = tetrominoColor(piece);

    for (final c in cells) {
      final rect = Rect.fromLTWH(
        ox + c.x * cell,
        oy + c.y * cell,
        cell,
        cell,
      ).deflate(cell * 0.08);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.2)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_NextPiecePainter old) => old.piece != piece;
}

class _ComboBadge extends StatelessWidget {
  const _ComboBadge({required this.combo});

  final int combo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6FAE), Color(0xFFFFD54F)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'x$combo COMBO',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ControlsHint extends StatelessWidget {
  const _ControlsHint({required this.game});

  final TetrisFlameGame game;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.35),
      fontSize: 12,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    );
    final hint = Text('ТАП — поворот · ТЯНИ — двигай · ВНИЗ — сброс',
        style: style, textAlign: TextAlign.center);
    if (!kDebugMode) return Center(child: hint);
    return Column(
      children: [
        Center(child: hint),
        const SizedBox(height: 2),
        ValueListenableBuilder<double>(
          valueListenable: game.fps,
          builder: (_, fps, _) => Text('${fps.round()} FPS', style: style),
        ),
      ],
    );
  }
}

/// Стартовый оверлей — тап начинает партию.
class TetrisReadyOverlay extends StatelessWidget {
  const TetrisReadyOverlay({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return _Scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🧱', style: TextStyle(fontSize: 72)),
          const SizedBox(height: 16),
          Text('Tetris', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(
            'Тап — поворот • Тяни — двигай • Свайп вниз — сброс',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _PlayButton(label: 'ИГРАТЬ', onTap: onStart),
        ],
      ),
    );
  }
}

/// Оверлей конца игры с рекордом и мгновенным рестартом.
class TetrisGameOverOverlay extends StatelessWidget {
  const TetrisGameOverOverlay({
    super.key,
    required this.score,
    required this.best,
    required this.isRecord,
    required this.onRetry,
    required this.onExit,
  });

  final int score;
  final int best;
  final bool isRecord;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return _Scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRecord) ...[
            const Text('🏆', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 8),
            const Text(
              'НОВЫЙ РЕКОРД!',
              style: TextStyle(
                color: Color(0xFFFFD54F),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ] else
            Text('Игра окончена',
                style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'рекорд: $best',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 28),
          _PlayButton(label: 'ЕЩЁ РАЗОК', onTap: onRetry),
          TextButton(
            onPressed: onExit,
            child: Text(
              'В меню',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E0B1A).withValues(alpha: 0.82),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF7C5CFF),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      child: Text(label),
    );
  }
}
