import 'package:flutter/material.dart';

import '../../core/storage/game_storage.dart';
import 'game_catalog.dart';

/// Главное меню: баннер дневного стрика + сетка карточек по [kGameCatalog].
/// Обновляется при возврате из игры (новые рекорды/стрик).
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Future<void> _open(GameEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: entry.builder),
    );
    if (mounted) setState(() {}); // подтянуть свежие рекорды/стрик
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storage = GameStorage.instance;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Natsukashi Yoru',
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'なつかしい夜 — выбери игру',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (storage.streak > 0) _StreakBadge(days: storage.streak),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1,
                  ),
                  itemCount: kGameCatalog.length,
                  itemBuilder: (context, i) {
                    final entry = kGameCatalog[i];
                    return _GameCard(
                      entry: entry,
                      best: storage.highScore(entry.id),
                      onTap: () => _open(entry),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6FAE), Color(0xFFFFD54F)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '🔥 $days',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.entry,
    required this.best,
    required this.onTap,
  });

  final GameEntry entry;
  final int best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(entry.icon, size: 56, color: entry.color),
                  const SizedBox(height: 16),
                  Text(
                    entry.title,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            if (best > 0)
              Positioned(
                top: 10,
                right: 12,
                child: Text(
                  '★ $best',
                  style: const TextStyle(
                    color: Color(0xFFFFD54F),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
