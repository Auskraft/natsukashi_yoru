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

/// Сложность игры (для бейджа в лобби). Цвета — из дизайн-хэндоффа.
enum Difficulty {
  easy('Easy', Color(0xFF34D399)),
  medium('Medium', Color(0xFFFBBF24)),
  hard('Hard', Color(0xFFF87171));

  const Difficulty(this.label, this.color);
  final String label;
  final Color color;
}

/// По какому показателю у игры «рекорд» (как форматировать в лобби).
enum GameMetric {
  /// Очки (больше — лучше): `GameStorage.highScore`.
  score,

  /// Время победы в секундах (меньше — лучше): `GameStorage.bestTime`.
  time,

  /// Число ходов (меньше — лучше): `GameStorage.bestTime`.
  moves,
}

/// Описание одной игры для лобби.
class GameEntry {
  const GameEntry({
    required this.id,
    required this.title,
    required this.nameJp,
    required this.icon,
    required this.accent,
    required this.difficulty,
    required this.builder,
    this.metric = GameMetric.score,
  });

  /// Стабильный ключ для хранилища рекордов (`GameStorage`) и имени папки.
  final String id;
  final String title;

  /// Японское название (для подписи в карточке).
  final String nameJp;
  final IconData icon;

  /// Акцентный цвет игры (иконка, свечение карточки, значение рекорда).
  final Color accent;
  final Difficulty difficulty;
  final GameMetric metric;

  /// Конструктор экрана-входа фичи.
  final WidgetBuilder builder;
}

/// Реестр всех игр. Единственный источник правды для лобби — добавление новой
/// игры сводится к одной записи здесь.
const List<GameEntry> kGameCatalog = [
  GameEntry(
    id: 'snake',
    title: 'Snake',
    nameJp: 'スネーク',
    icon: Icons.gesture,
    accent: Color(0xFF34D399),
    difficulty: Difficulty.medium,
    builder: _snake,
  ),
  GameEntry(
    id: 'tetris',
    title: 'Lines',
    nameJp: 'ライン',
    icon: Icons.view_module,
    accent: Color(0xFF818CF8),
    difficulty: Difficulty.hard,
    builder: _tetris,
  ),
  GameEntry(
    id: 'match3',
    title: 'Match3',
    nameJp: 'マッチ3',
    icon: Icons.grid_view,
    accent: Color(0xFFF472B6),
    difficulty: Difficulty.easy,
    builder: _match3,
  ),
  GameEntry(
    id: 'bejeweled',
    title: 'Gems',
    nameJp: 'ジュエル',
    icon: Icons.diamond,
    accent: Color(0xFF22D3EE),
    difficulty: Difficulty.hard,
    builder: _bejeweled,
  ),
  GameEntry(
    id: 'puyo_puyo',
    title: 'Drops',
    nameJp: 'ドロップ',
    icon: Icons.bubble_chart,
    accent: Color(0xFFFBBF24),
    difficulty: Difficulty.medium,
    builder: _puyo,
  ),
  GameEntry(
    id: 'minesweeper',
    title: 'Minesweeper',
    nameJp: '地雷',
    icon: Icons.flag,
    accent: Color(0xFFF87171),
    difficulty: Difficulty.medium,
    metric: GameMetric.time,
    builder: _mines,
  ),
  GameEntry(
    id: 'game2048',
    title: '2048',
    nameJp: '数字',
    icon: Icons.grid_4x4,
    accent: Color(0xFFFFD54F),
    difficulty: Difficulty.medium,
    builder: _game2048,
  ),
  GameEntry(
    id: 'block_puzzle',
    title: '1010!',
    nameJp: 'ブロック',
    icon: Icons.dashboard,
    accent: Color(0xFF38BDF8),
    difficulty: Difficulty.easy,
    builder: _blockPuzzle,
  ),
  GameEntry(
    id: 'bubble_shooter',
    title: 'Bubble Shooter',
    nameJp: 'バブル',
    icon: Icons.scatter_plot,
    accent: Color(0xFFFB7185),
    difficulty: Difficulty.medium,
    builder: _bubbleShooter,
  ),
  GameEntry(
    id: 'stack_tower',
    title: 'Stack',
    nameJp: 'タワー',
    icon: Icons.layers,
    accent: Color(0xFF4ADE80),
    difficulty: Difficulty.easy,
    builder: _stackTower,
  ),
  GameEntry(
    id: 'whack_a_mole',
    title: 'Whack-a-Mole',
    nameJp: 'モグラ',
    icon: Icons.sports_mma,
    accent: Color(0xFFFB923C),
    difficulty: Difficulty.easy,
    builder: _whackAMole,
  ),
  GameEntry(
    id: 'lights_out',
    title: 'Lights Out',
    nameJp: 'ライト',
    icon: Icons.lightbulb,
    accent: Color(0xFFA78BFA),
    difficulty: Difficulty.medium,
    metric: GameMetric.moves,
    builder: _lightsOut,
  ),
  GameEntry(
    id: 'breakout',
    title: 'Bricks',
    nameJp: 'レンガ',
    icon: Icons.sports_tennis,
    accent: Color(0xFF60A5FA),
    difficulty: Difficulty.medium,
    builder: _breakout,
  ),
  GameEntry(
    id: 'sokoban',
    title: 'Sokoban',
    nameJp: '倉庫番',
    icon: Icons.warehouse,
    accent: Color(0xFF2DD4BF),
    difficulty: Difficulty.hard,
    metric: GameMetric.moves,
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
