import 'package:flutter/material.dart';

/// Переиспользуемые элементы оверлеев игр (старт / game over / HUD-блоки),
/// чтобы не дублировать их в каждой фиче.

/// Затемняющая подложка по центру экрана.
class GameScrim extends StatelessWidget {
  const GameScrim({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E0B1A).withValues(alpha: 0.82),
      alignment: Alignment.center,
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }
}

/// Крупная кнопка действия.
class PlayButton extends StatelessWidget {
  const PlayButton({super.key, required this.label, required this.onTap});
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      child: Text(label),
    );
  }
}

/// Подпись + значение (СЧЁТ / РЕКОРД / УРОВЕНЬ …).
class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.label,
    required this.value,
    this.color = Colors.white,
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

/// Бейдж комбо, анимированно «выпрыгивает» при combo >= 2.
class ComboBadge extends StatelessWidget {
  const ComboBadge({super.key, required this.combo, this.label = 'COMBO'});

  final int combo;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: combo >= 2 ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6FAE), Color(0xFFFFD54F)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'x$combo $label',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// Стартовый экран фичи: эмодзи, название, подсказка, кнопка «играть».
class ReadyPanel extends StatelessWidget {
  const ReadyPanel({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onStart,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return GameScrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 72)),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          PlayButton(label: 'ИГРАТЬ', onTap: onStart),
        ],
      ),
    );
  }
}

/// Компактная круглая кнопка паузы для встраивания в HUD.
class PauseButton extends StatelessWidget {
  const PauseButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.pause_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// Экран паузы: продолжить, начать заново, выйти в меню.
class PausePanel extends StatelessWidget {
  const PausePanel({
    super.key,
    required this.onResume,
    required this.onRestart,
    required this.onExit,
  });

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return GameScrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⏸', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 8),
          Text('Пауза', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 28),
          PlayButton(label: 'ПРОДОЛЖИТЬ', onTap: onResume),
          TextButton(
            onPressed: onRestart,
            child: Text(
              'Заново',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
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

/// Экран конца игры: рекорд, счёт, мгновенный рестарт и выход в меню.
class GameOverPanel extends StatelessWidget {
  const GameOverPanel({
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
    return GameScrim(
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
          PlayButton(label: 'ЕЩЁ РАЗОК', onTap: onRetry),
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
