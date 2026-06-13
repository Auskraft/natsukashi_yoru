/// Режим игры. Одно ядро симуляции обслуживает все три — различаются лишь
/// поставщик врагов, условие победы и что персистится.
enum GameMode { campaign, survival, daily }

/// Параметры забега, общие для ядра симуляции.
class RunConfig {
  const RunConfig({
    required this.mode,
    this.startLives = 3,
    this.feedsStreak = false,
  });

  final GameMode mode;
  final int startLives;

  /// Засчитывать игровой день в общий дневной стрик (режим «Дейли»).
  final bool feedsStreak;

  static const RunConfig campaign = RunConfig(mode: GameMode.campaign);
  static const RunConfig survival = RunConfig(mode: GameMode.survival);
  static const RunConfig daily =
      RunConfig(mode: GameMode.daily, feedsStreak: true);
}
