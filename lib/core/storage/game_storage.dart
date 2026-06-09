import 'package:shared_preferences/shared_preferences.dart';

/// Единое хранилище прогресса на `shared_preferences`.
///
/// Держит рекорды по каждой игре и дневной стрик (ретеншн-механика).
/// Инициализируется один раз в `main()` до запуска приложения.
class GameStorage {
  GameStorage._(this._prefs);

  final SharedPreferences _prefs;
  static GameStorage? _instance;

  /// Доступ к синглтону. Бросит, если не вызвали [init].
  static GameStorage get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('GameStorage.init() не был вызван');
    }
    return i;
  }

  static Future<GameStorage> init() async {
    return _instance ??= GameStorage._(await SharedPreferences.getInstance());
  }

  // ── Рекорды ──────────────────────────────────────────────────────────────

  int highScore(String gameId) => _prefs.getInt('hs_$gameId') ?? 0;

  /// Сохраняет счёт, если он лучше прежнего. Возвращает `true` — новый рекорд.
  Future<bool> submitScore(String gameId, int score) async {
    if (score > highScore(gameId)) {
      await _prefs.setInt('hs_$gameId', score);
      return true;
    }
    return false;
  }

  // ── Согласие с документами (показ экрана согласия при первом запуске) ─────

  static const String _consentKey = 'consent_accepted_v1';

  /// Принял ли пользователь документы (соглашение/политику).
  bool get consentAccepted => _prefs.getBool(_consentKey) ?? false;

  /// Зафиксировать принятие документов.
  Future<void> acceptConsent() => _prefs.setBool(_consentKey, true);

  // ── Лучшее время (меньше — лучше; для игр на скорость, напр. сапёр) ───────

  /// Лучшее время в секундах или 0, если рекорда ещё нет.
  int bestTime(String gameId) => _prefs.getInt('bt_$gameId') ?? 0;

  /// Сохраняет время, если оно лучше прежнего (или первое). true — новый рекорд.
  Future<bool> submitTime(String gameId, int seconds) async {
    final prev = bestTime(gameId);
    if (prev == 0 || seconds < prev) {
      await _prefs.setInt('bt_$gameId', seconds);
      return true;
    }
    return false;
  }

  // ── Дневной стрик ────────────────────────────────────────────────────────

  int get streak => _prefs.getInt('streak') ?? 0;

  /// Засчитать игровой день. Вызывать при старте партии.
  /// Стрик растёт, если играли вчера; сбрасывается на 1 при пропуске;
  /// повторный вызов за тот же день ничего не меняет.
  Future<void> registerPlay(DateTime now) async {
    final today = _dateKey(now);
    final last = _prefs.getString('last_played');
    if (last == today) return;

    final yesterday = _dateKey(now.subtract(const Duration(days: 1)));
    final next = last == yesterday ? streak + 1 : 1;

    await _prefs.setInt('streak', next);
    await _prefs.setString('last_played', today);
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
