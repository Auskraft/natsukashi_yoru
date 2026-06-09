# Архитектура · Natsukashi Yoru

Документ описывает структуру проекта, конвенции и то, как добавить новую игру.

## Принципы

- **Feature-Based + Component-Oriented.** Игра — самодостаточная фича; общие
  механизмы вынесены в `core/`.
- **Чистая логика отделена от рендера.** Правила игры не зависят от Flutter/Flame
  и покрыты юнит-тестами. «Сок» и отрисовка живут отдельным слоем.
- **Единые UI-кирпичики.** Старт/пауза/гейм-овер/HUD-блоки переиспользуются из
  `core/components/overlay_kit.dart`.
- **Детерминизм.** Случайность инъектируется (`Random? random`), системные часы и
  глобальный рандом в логике не используются — это делает тесты воспроизводимыми.

## Слои игры

Каждая игра в `lib/features/<game>/` состоит из четырёх слоёв:

| Файл | Роль | Зависимости |
|------|------|-------------|
| `components/<game>_logic.dart` | **Чистая логика**: состояние, ходы, тип-исход | только `dart:math` |
| `game/<game>_flame_game.dart` | **Flame-игра**: game loop, ввод, рендер, «сок» | flame, flutter |
| `ui/<game>_overlays.dart` | **HUD/оверлеи** поверх игры | flutter, overlay_kit |
| `<game>_game.dart` | **Экран-хост**: жесты, оверлеи по фазе, хранилище | flutter, flame |

### 1. Логика (`components/`)

Чистый Dart-класс: `reset()`, методы-действия, публично читаемое состояние и
**тип-исход хода** (что изменилось — для частиц/попапов). Примеры исходов:
`StepOutcome` (Snake), `LockResult` (Tetris/Puyo), `SwapResult` (Match3/Bejeweled),
`RevealResult` (Minesweeper), `MoveResult` (2048), `SokoMoveResult` (Sokoban).

### 2. Flame-игра (`game/`)

`class XFlameGame extends FlameGame` с конвенциями:

- **Фазы:** `enum XPhase { ready, running, dead }` (+ `won`/`lost` где нужно).
- **Notifier'ы:** `score` (+ специфичные) `+ phase + fps + isPaused`.
  > ⚠️ Нотифаер паузы называется `isPaused`, а не `paused` — у `FlameGame`
  > уже есть собственный член `paused`.
- **Геттеры:** `_running => phase == running`, `_active => _running && !isPaused`.
- **Пауза:** `togglePause()` переключает `isPaused`; прогрессия (гравитация,
  таймеры, физика) и ввод гардятся через `_active`. Рендер остаётся (стоп-кадр).
- **`update(dt)`:** `super.update(dt)` → FPS → эффекты → `if (!_active) return;`
  → прогрессия.
- **«Сок»:** локальные `_Spark` (частицы), `_Popup` (всплывающие очки), `shake`,
  `flash`. Фон — `Color(0xFF0E0B1A)`.
- **Game over:** `phase = dead; Haptics.heavy(); onGameOver(score)`.

### 3. Оверлеи (`ui/`)

HUD-виджет на `StatBlock`/`ComboBadge` из `overlay_kit`; в верхний ряд встроена
`PauseButton(onTap: game.togglePause)`. FPS — только при `kDebugMode`. Экраны
старта/паузы/конца берутся из `overlay_kit` (`ReadyPanel`/`PausePanel`/`GameOverPanel`).

### 4. Экран-хост (`<game>_game.dart`)

`StatefulWidget`, который:
- хостит `GameWidget<XFlameGame>` и ловит жесты, вызывая методы игры;
- рисует оверлей через
  `AnimatedBuilder(animation: Listenable.merge([phase, isPaused]))`:
  `isPaused → PausePanel`, иначе `switch (phase)` → ready/HUD/game-over;
- пишет рекорд/стрик в `GameStorage` (`submitScore`/`submitTime` + `registerPlay`).

## Общие системы (`core/`)

- **`theme/`** — `AppColors` (палитра, с `copyWith` под будущий реколор) и
  `AppTheme` (сборка `ThemeData`). Сменить скин = подменить `AppColors`.
- **`storage/game_storage.dart`** — синглтон на `shared_preferences`:
  - `highScore` / `submitScore` (больше = лучше) — очковые игры;
  - `bestTime` / `submitTime` (меньше = лучше) — на время/ходы (Minesweeper,
    Lights Out, Sokoban);
  - `streak` / `registerPlay(DateTime)` — дневной стрик.
- **`feedback/haptics.dart`** — `light/medium/heavy/select` и `combo(level)`
  (нарастающий паттерн для комбо).
- **`components/overlay_kit.dart`** — `ReadyPanel`, `PausePanel`, `GameOverPanel`,
  `PauseButton`, `StatBlock`, `ComboBadge`, `GameScrim`, `PlayButton`.
- **`audio/audio_manager.dart`** — тонкий фасад над `flame_audio` (задел).
- **`achievements/`** — 🔒 заглушка под будущую систему ачивок.

## Лобби и реестр игр

`features/menu/game_catalog.dart` — единственный источник правды: `const`-список
`GameEntry` (id, название, 日本語, иконка, акцент, сложность, метрика, builder).
Лобби (`menu_screen.dart`) рендерит карточки по этому списку и тянет рекорд/стрик
из `GameStorage`. Метрика (`score`/`time`/`moves`) определяет формат рекорда.

## Как добавить новую игру

1. Создать `lib/features/<game>/` с четырьмя файлами по слоям выше.
2. Написать чистую логику + тест `test/<game>_logic_test.dart` (инъекция `Random`).
3. Реализовать Flame-слой со «соком», оверлеи (из `overlay_kit`) и экран-хост.
4. Добавить одну запись `GameEntry` в `kGameCatalog` + builder-функцию.
5. `flutter analyze` (чисто) и `flutter test` (зелено).

## Тестирование

- **Логика** покрыта юнит-тестами (детерминизм через seed).
- **Flame-слой** проверяется вручную (плейтест на устройстве) — рендер/«фил».
- Перед коммитом: `flutter analyze` + `flutter test`.

## Сборка и окружение

- Платформа — **Android only** (apk), организация `com.auskraft`.
- Иконка/сплэш генерируются `flutter_launcher_icons` и `flutter_native_splash`.
- Сборку и запуск выполняет разработчик в Android Studio; статика и тесты
  гоняются командами `flutter analyze` / `flutter test`.
