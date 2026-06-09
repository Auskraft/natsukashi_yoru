# 🌙 Natsukashi Yoru · なつかしい夜

> «Ностальгическая ночь» — коллекция из 14 классических мини-игр на Flutter + Flame,
> с единой архитектурой, общей ночной темой и упором на «сок» (juice) и удержание.

![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Flame](https://img.shields.io/badge/Flame-1.18-FF6E40)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Tests](https://img.shields.io/badge/tests-220%20passing-34D399)

---

## ✨ Особенности

- **14 игр** в одном приложении — от Snake до Sokoban.
- **«Сочный» геймплей**: частицы, тряска экрана, вспышки, всплывающие очки,
  комбо с особой тактильной вибрацией.
- **Удержание**: рекорды и дневной стрик 🔥 у каждой игры, мгновенный «ещё разок».
- **Пауза** во всех играх, единый стиль оверлеев.
- **Высокая герцовка** (90/120/144 Гц) через `flutter_displaymode`.
- **Кастомная иконка и полноэкранный сплэш**.
- **Чистая, тестируемая логика** каждой игры (220 юнит-тестов).

## 🎮 Игры

| Игра | 日本語 | Режим / крючок удержания |
|------|--------|--------------------------|
| Snake | スネーク | endless · рекорд |
| Tetris | テトリス | уровни · рекорд |
| Match3 | マッチ3 | блиц 60 сек · рекорд |
| Bejeweled | ジュエル | 25 ходов · спец-камни |
| Puyo Puyo | ぷよぷよ | цепочки · рекорд |
| Minesweeper | 地雷 | на время (лучшее = быстрее) |
| 2048 | 数字 | свайп-слияния · рекорд |
| 1010! | ブロック | drag-полимино · рекорд |
| Bubble Shooter | バブル | соты, кластеры 3+ · рекорд |
| Stack | タワー | точность башни · рекорд |
| Whack-a-Mole | モグラ | блиц 30 сек · рекорд |
| Lights Out | ライト | головоломка (меньше ходов) |
| Breakout | ブロック崩し | жизни + уровни · рекорд |
| Sokoban | 倉庫番 | 6 уровней (меньше ходов) |

## 🏗️ Архитектура

**Feature-Based + Component-Oriented.** Каждая игра — изолированная фича из четырёх
слоёв: чистая логика, Flame-рендер со «соком», UI-оверлеи и экран-хост. Общие
системы (тема, хранилище, тактильная отдача, оверлеи) лежат в `core/`.

Подробно — в [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

```
lib/
├── core/                  # общие системы
│   ├── theme/             # палитра + тема (задел под реколор)
│   ├── components/        # overlay_kit (ready/pause/game-over/HUD), GameScaffold
│   ├── feedback/          # хаптика (включая комбо-паттерн)
│   ├── storage/           # рекорды, лучшее время, дневной стрик
│   ├── audio/             # фасад над flame_audio
│   └── achievements/      # 🔒 заглушка (план)
├── features/
│   ├── menu/              # лобби + реестр игр (game_catalog.dart)
│   └── <game>/            # snake, tetris, ... (×14)
│       ├── components/    # чистая логика (+ тесты)
│       ├── game/          # Flame-игра + «сок»
│       ├── ui/            # HUD/оверлеи
│       └── <game>_game.dart   # экран-хост
└── main.dart
```

## 🚀 Запуск

**Требования:** Flutter **3.41.x** (stable), Android SDK, устройство/эмулятор.

```bash
git clone https://github.com/Auskraft/natsukashi_yoru.git
cd natsukashi_yoru
flutter pub get
flutter run                 # отладочный запуск
```

**Сборка APK:**
```bash
flutter build apk --release
```

> При смене иконки/сплэша перегенерируй ресурсы:
> ```bash
> dart run flutter_launcher_icons
> dart run flutter_native_splash:create
> ```

## 🧪 Тесты

Логика каждой игры покрыта детерминированными юнит-тестами (инъекция `Random`).

```bash
flutter analyze     # статический анализ (flutter_lints)
flutter test        # 220 тестов
```

## 🛠️ Стек

| Технология | Назначение |
|------------|-----------|
| [Flutter](https://flutter.dev) | UI-фреймворк |
| [Flame](https://flame-engine.org) | игровой движок (рендер, game loop) |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | рекорды/стрик |
| [flame_audio](https://pub.dev/packages/flame_audio) | звук |
| [google_fonts](https://pub.dev/packages/google_fonts) | Space Grotesk + Noto Sans JP |
| [flutter_displaymode](https://pub.dev/packages/flutter_displaymode) | высокая герцовка |

## 🗺️ Дорожная карта

- [ ] Система ачивок (сейчас архитектурная заглушка)
- [ ] Реколор/скины темы (заложено в `core/theme/`)
- [ ] Звуковое оформление и музыка
- [ ] Экраны «Профиль»/«Ачивки» (прогрессия XP/уровень/ранг)
- [ ] Локальный бандл шрифтов для оффлайна

## 🤝 Контрибьютинг

Гайд для разработчиков и шаги «как добавить игру» — в [`CONTRIBUTING.md`](CONTRIBUTING.md).

## 📄 Лицензия

Лицензия пока не выбрана. До её добавления все права принадлежат автору
(© Auskraft). Хотите использовать код — свяжитесь с автором.

---

<sub>Собрано совместно с Claude Code (Anthropic). Организация пакета: <code>com.auskraft</code>.</sub>
