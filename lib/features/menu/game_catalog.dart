import 'package:flutter/material.dart';

import '../bejeweled/bejeweled_game.dart';
import '../block_puzzle/block_puzzle_game.dart';
import '../breakout/breakout_game.dart';
import '../bubble_shooter/bubble_shooter_game.dart';
import '../game2048/game2048_game.dart';
import '../lights_out/lights_out_game.dart';
import '../match3/match3_game.dart';
import '../minesweeper/minesweeper_game.dart';
import '../puyo_puyo/puyo_puyo_game.dart';
import '../snake/snake_game.dart';
import '../sokoban/sokoban_game.dart';
import '../stack_tower/stack_tower_game.dart';
import '../tetris/tetris_game.dart';
import '../whack_a_mole/whack_a_mole_game.dart';

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
  GameEntry(
    id: 'game2048',
    title: '2048',
    icon: Icons.grid_4x4,
    color: Color(0xFFFFD54F),
    builder: _game2048,
  ),
  GameEntry(
    id: 'block_puzzle',
    title: '1010!',
    icon: Icons.dashboard,
    color: Color(0xFF4ECDC4),
    builder: _blockPuzzle,
  ),
  GameEntry(
    id: 'bubble_shooter',
    title: 'Bubble Shooter',
    icon: Icons.scatter_plot,
    color: Color(0xFFFF6FAE),
    builder: _bubbleShooter,
  ),
  GameEntry(
    id: 'stack_tower',
    title: 'Stack',
    icon: Icons.layers,
    color: Color(0xFF5CE08A),
    builder: _stackTower,
  ),
  GameEntry(
    id: 'whack_a_mole',
    title: 'Whack-a-Mole',
    icon: Icons.sports_mma,
    color: Color(0xFFFF9F45),
    builder: _whackAMole,
  ),
  GameEntry(
    id: 'lights_out',
    title: 'Lights Out',
    icon: Icons.lightbulb,
    color: Color(0xFFA78BFA),
    builder: _lightsOut,
  ),
  GameEntry(
    id: 'breakout',
    title: 'Breakout',
    icon: Icons.sports_tennis,
    color: Color(0xFF5C8CFF),
    builder: _breakout,
  ),
  GameEntry(
    id: 'sokoban',
    title: 'Sokoban',
    icon: Icons.warehouse,
    color: Color(0xFF22D3EE),
    builder: _sokoban,
  ),
];

// Тонкие builder-функции (нужны top-level, чтобы каталог оставался `const`).
Widget _snake(BuildContext _) => const SnakeScreen();
Widget _tetris(BuildContext _) => const TetrisScreen();
Widget _match3(BuildContext _) => const Match3Screen();
Widget _bejeweled(BuildContext _) => const BejeweledScreen();
Widget _puyo(BuildContext _) => const PuyoPuyoScreen();
Widget _mines(BuildContext _) => const MinesweeperScreen();
Widget _game2048(BuildContext _) => const Game2048Screen();
Widget _blockPuzzle(BuildContext _) => const BlockPuzzleScreen();
Widget _bubbleShooter(BuildContext _) => const BubbleShooterScreen();
Widget _stackTower(BuildContext _) => const StackTowerScreen();
Widget _whackAMole(BuildContext _) => const WhackAMoleScreen();
Widget _lightsOut(BuildContext _) => const LightsOutScreen();
Widget _breakout(BuildContext _) => const BreakoutScreen();
Widget _sokoban(BuildContext _) => const SokobanScreen();
