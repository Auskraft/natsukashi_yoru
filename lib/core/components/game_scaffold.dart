import 'package:flutter/material.dart';

/// Общий каркас экрана игры: фон из темы, AppBar с названием и кнопкой назад,
/// слот под содержимое (игровое поле / HUD).
///
/// На этапе каркаса игры используют [GameScaffold] с заглушкой
/// [ComingSoonBody]. Когда появится логика на Flame, в `body` поедет
/// `GameWidget(game: ...)` с оверлеями HUD/паузы.
class GameScaffold extends StatelessWidget {
  const GameScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(child: body),
    );
  }
}

/// Плейсхолдер «в разработке» для незаконченных игр.
class ComingSoonBody extends StatelessWidget {
  const ComingSoonBody({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 96, color: color),
          const SizedBox(height: 24),
          Text('В разработке', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Логика игры появится в следующих итерациях',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
