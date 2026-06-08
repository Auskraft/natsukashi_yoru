import 'package:flutter/material.dart';

import '../bejeweled/bejeweled_game.dart';
import '../match3/match3_game.dart';
import '../minesweeper/minesweeper_game.dart';
import '../puyo_puyo/puyo_puyo_game.dart';
import '../snake/snake_game.dart';
import '../tetris/tetris_game.dart';

/// Описание одной игры для главного меню.
class GameEntry {
  const GameEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.builder,
  });

  /// Стабильный ключ для хранилища рекордов (`GameStorage`).
  final String id;
  final String title;
  final IconData icon;
  final Color color;

  /// Конструктор экрана-входа фичи.
  final WidgetBuilder builder;
}

/// Реестр всех игр. Единственный источник правды для меню — добавление новой
/// игры сводится к одной записи здесь.
const List<GameEntry> kGameCatalog = [
  GameEntry(
    id: 'snake',
    title: 'Snake',
    icon: Icons.gesture,
    color: Color(0xFF4ECDC4),
    builder: _snake,
  ),
  GameEntry(
    id: 'tetris',
    title: 'Tetris',
    icon: Icons.view_module,
    color: Color(0xFF7C5CFF),
    builder: _tetris,
  ),
  GameEntry(
    id: 'match3',
    title: 'Match3',
    icon: Icons.grid_view,
    color: Color(0xFFFF6FAE),
    builder: _match3,
  ),
  GameEntry(
    id: 'bejeweled',
    title: 'Bejeweled',
    icon: Icons.diamond,
    color: Color(0xFF4ECDC4),
    builder: _bejeweled,
  ),
  GameEntry(
    id: 'puyo_puyo',
    title: 'Puyo Puyo',
    icon: Icons.bubble_chart,
    color: Color(0xFFFF6FAE),
    builder: _puyo,
  ),
  GameEntry(
    id: 'minesweeper',
    title: 'Minesweeper',
    icon: Icons.flag,
    color: Color(0xFF7C5CFF),
    builder: _mines,
  ),
];

// Тонкие builder-функции (нужны top-level, чтобы каталог оставался `const`).
Widget _snake(BuildContext _) => const SnakeScreen();
Widget _tetris(BuildContext _) => const TetrisScreen();
Widget _match3(BuildContext _) => const Match3Screen();
Widget _bejeweled(BuildContext _) => const BejeweledScreen();
Widget _puyo(BuildContext _) => const PuyoPuyoScreen();
Widget _mines(BuildContext _) => const MinesweeperScreen();
