import 'package:flutter/material.dart';

import '../../core/storage/game_storage.dart';
import '../menu/game_catalog.dart';
import 'control_picker_screen.dart';

/// Игры с выбором схемы управления (направленный ввод). Пилот: пока Snake.
/// По мере раскатки добавляй id: например 'tetris', 'puyo_puyo', 'game2048',
/// 'sokoban' (и заодно подключай [ControlOverlay] в их экранах-хостах).
const Set<String> kControllableGames = {'snake'};

/// Хаб «Управление»: список игр, для которых можно выбрать схему. Тап по игре
/// открывает пикер с живым превью.
class ControlSettingsScreen extends StatefulWidget {
  const ControlSettingsScreen({super.key});

  @override
  State<ControlSettingsScreen> createState() => _ControlSettingsScreenState();
}

class _ControlSettingsScreenState extends State<ControlSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final games =
        kGameCatalog.where((e) => kControllableGames.contains(e.id)).toList();
    final storage = GameStorage.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Управление')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: games.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                'Выбери, как управлять каждой игрой. «Жесты» — как раньше; '
                'можно включить экранную крестовину или джойстик.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            );
          }
          final e = games[i - 1];
          final scheme = storage.controlScheme(e.id);
          return _GameRow(
            entry: e,
            schemeLabel: scheme.label,
            schemeEmoji: scheme.emoji,
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ControlPickerScreen(
                    gameId: e.id,
                    title: e.title,
                    accent: e.accent,
                  ),
                ),
              );
              if (mounted) setState(() {}); // обновить подпись текущей схемы
            },
          );
        },
      ),
    );
  }
}

/// Строка игры в хабе: иконка, название, текущая схема и шеврон.
class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.entry,
    required this.schemeLabel,
    required this.schemeEmoji,
    required this.onTap,
  });

  final GameEntry entry;
  final String schemeLabel;
  final String schemeEmoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x08FFFFFF),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(entry.icon, color: entry.accent, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$schemeEmoji $schemeLabel',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: Colors.white.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
