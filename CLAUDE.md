# CLAUDE.md — Natsukashi Yoru · なつかしい夜

> **Документ для продолжения проекта в новой сессии.** Прочитай его первым.
> Подробности: [`README.md`](README.md) · [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) ·
> [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`docs/RUSTORE.md`](docs/RUSTORE.md).

## Что это
Сборник **14 классических мини-игр** на **Flutter + Flame**. Только **Android**
(apk/aab), организация `com.auskraft`, репозиторий
<https://github.com/Auskraft/natsukashi_yoru> (public). Акцент — «сок» (juice) и
удержание. Готовится к публикации в **RuStore**.

## ⚠️ Критично для агента (прочитай!)
- **Собрать APK/AAB и `flutter run` агент НЕ может** — песочница инструментов
  блокирует NIO-селектор (loopback), Gradle падает. Это **не машина пользователя**
  (он собирает в Android Studio нормально — AAB+APK уже собраны). Агент верифицирует
  только через `flutter analyze` + `flutter test` (они работают). Не пытаться
  собирать/запускать из агента. См. память `build-env-selector-loopback`.
- **Секреты:** `android/app/upload-keystore.jks` и `android/key.properties`
  в `.gitignore` (не коммитить). Пароль у пользователя (Bitwarden). Не запрашивать
  и не выводить пароль.
- **Коммитим по ходу** прямо в `main`, без напоминаний. В сообщениях коммитов —
  строка `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Главный приоритет** во всех играх — дофамин/«сок» + удержание.
- Нотифаер паузы в каждой игре называется **`isPaused`** (не `paused` — конфликт
  с `FlameGame.paused`).

## Статус — что готово
- ✅ **14 игр** играбельны (чистая логика + тесты, Flame-рендер со «соком»,
  оверлеи, пауза, рекорды + дневной стрик).
- ✅ **Лобби-редизайн** (тёмная тема `#07051A`, анимированное звёздное небо,
  карточки-строки с акцентом/японским/сложностью/рекордом) по дизайн-хэндоффу V2.
- ✅ **Иконка** (адаптивная) + **полноэкранный сплэш**.
- ✅ **Оффлайн-шрифты**: Space Grotesk забандлен (`assets/fonts/SpaceGrotesk.ttf`,
  вариативный, вес через `FontVariation`); `google_fonts` убран; японский текст —
  системным CJK-шрифтом. **Сети нет**, INTERNET только в debug/profile-манифесте.
- ✅ **Юр.документы** (соглашение / политика конфиденциальности / 152-ФЗ) +
  экран согласия при первом запуске (флаг `consent_accepted_v1`) + раздел
  «Документы · О приложении» внизу лобби. См. `lib/core/legal/`.
- ✅ **RuStore-подготовка**: `STORE_DESCRIPTION.md` (описание + рус. названия),
  `docs/RUSTORE.md` (чек-лист), `store/icon_512.png` (512², <1 МБ), подпись релиза
  настроена (`android/app/build.gradle.kts` ← `key.properties`). Пользователь
  собрал AAB+APK и заливает в RuStore (для RuStore проще **APK**; категории:
  Головоломки/Аркады; возраст 0+).
- ✅ **221 тест** зелёные, `flutter analyze` чисто. Всё в `main` на GitHub.

## Игры (14) и режимы удержания
| папка/id | игра | режим |
|----------|------|-------|
| snake | Змейка | endless + рекорд |
| tetris | Тетрис | уровни + рекорд |
| match3 | Три в ряд | блиц 60 сек |
| bejeweled | Самоцветы | 25 ходов + спецкамни |
| puyo_puyo | Пуё-Пуё | цепочки |
| minesweeper | Сапёр | на время (меньше=лучше) |
| game2048 | 2048 | свайп-слияния |
| block_puzzle | 1010! | drag-полимино |
| bubble_shooter | Bubble Shooter | соты + уровни |
| stack_tower | Stack | точность башни |
| whack_a_mole | Поймай крота | блиц 30 сек |
| lights_out | Lights Out | меньше ходов |
| breakout | Арканоид | жизни + уровни |
| sokoban | Сокобан | 6 уровней, меньше ходов |

Реестр игр — **`lib/features/menu/game_catalog.dart`** (одна `GameEntry` на игру:
id = ключ хранилища/папки, japanese name, accent, difficulty, metric, builder).

## Архитектура (кратко; детали — `docs/ARCHITECTURE.md`)
Feature-Based. Каждая игра в `lib/features/<game>/` из 4 слоёв:
- `components/<g>_logic.dart` — **чистая логика** (только `dart:math`, инъекция
  `Random`), тип-исход хода для «сока». Тест: `test/<g>_logic_test.dart`.
- `game/<g>_flame_game.dart` — `FlameGame`: фазы `ready/running/dead`, нотифаеры
  (`score`(+спец)+`phase`+`fps`+`isPaused`), `_active = running && !isPaused`,
  `togglePause()`, «сок» (частицы/попапы/shake/flash). Прогрессия и ввод — под `_active`.
- `ui/<g>_overlays.dart` — HUD из `core/components/overlay_kit.dart`
  (`StatBlock`/`ComboBadge`/`PauseButton`; старт/пауза/гейм-овер — `ReadyPanel`/
  `PausePanel`/`GameOverPanel`).
- `<g>_game.dart` — экран-хост: `GameWidget` + жесты + оверлей по фазе/`isPaused`,
  запись рекорда/стрика в `GameStorage`.

`core/`: `theme` (палитра, задел под реколор) · `storage/GameStorage`
(`highScore`/`submitScore`; `bestTime`/`submitTime` «меньше=лучше»; `streak`/
`registerPlay`; `consentAccepted`/`acceptConsent`) · `feedback/Haptics`
(+ `combo`-паттерн) · `components/overlay_kit` · `legal` (документы + экраны) ·
`audio` (фасад-заглушка) · `achievements` (заглушка).

## Запуск и проверка
```bash
flutter pub get
flutter analyze          # должно быть «No issues found!» — это делает агент
flutter test             # 221 тест зелёный — это делает агент
# Пользователь (агент НЕ может):
flutter run
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release  # build/app/outputs/bundle/release/app-release.aab
```
Перегенерация иконки/сплэша после правок: `dart run flutter_launcher_icons` /
`dart run flutter_native_splash:create`.

## Дорожная карта / что дальше
- Плейтест «фила» агентских игр (особенно **Bubble Shooter** и **Breakout** —
  самые сложные; уже фиксили зависание/прогрессию/физику).
- Звук и музыка (`flame_audio` — пока только фасад `core/audio`).
- Система ачивок (сейчас заглушка `core/achievements`).
- Экраны «Профиль»/«Ачивки», прогрессия XP/уровень/ранг (в лобби пока скрыто
  по решению владельца — показываем только реальные данные).
- Опц.: субсет Noto Sans JP под используемые символы (сейчас системный CJK).
- Скриншоты для RuStore (делает пользователь).

## Контакты / оператор
Шварев Дмитрий Андреевич (Auskraft) · auskraft@gmail.com · г. Волгоград.

---
<sub>Собрано совместно с Claude Code (Anthropic).</sub>
