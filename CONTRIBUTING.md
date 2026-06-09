# Контрибьютинг · Natsukashi Yoru

Спасибо за интерес! Этот гайд — про то, как развивать проект единообразно.

## Окружение

- Flutter **3.41.x** (stable), Android SDK.
- Перед началом: `flutter pub get`.

## Перед каждым PR / коммитом

```bash
flutter analyze   # должно быть «No issues found!»
flutter test      # все тесты зелёные
```

Код подчиняется `flutter_lints` (см. `analysis_options.yaml`). Без неиспользуемых
импортов/переменных, с корректными `@override`. Используйте `.withValues(alpha:)`
вместо устаревшего `withOpacity`.

## Стиль

- **Чистая логика отделена от рендера.** Правила игры — в `components/<game>_logic.dart`,
  без `package:flutter`/`package:flame` (только `dart:math`), со всей случайностью
  через инъектированный `Random` (детерминизм для тестов).
- **Каждая логика покрыта тестом** `test/<game>_logic_test.dart`.
- **Переиспользуйте `core/`**: оверлеи — из `overlay_kit`, отдача — из `Haptics`,
  рекорды/стрик — из `GameStorage`.
- Комментарии и UI-тексты — на русском; идентификаторы — на английском.

Полное описание слоёв и конвенций — в [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Как добавить игру

1. Папка `lib/features/<game>/` с четырьмя слоями (logic / game / ui / screen).
2. Чистая логика + тест.
3. Flame-слой со «соком», оверлеи, экран-хост (пауза, рекорд/стрик, «ещё разок»).
4. Одна запись `GameEntry` в `lib/features/menu/game_catalog.dart`.
5. `flutter analyze` + `flutter test`.

## Коммиты

- Понятные сообщения, желательно с префиксом-областью: `feat(snake): …`,
  `fix(tetris): …`, `docs: …`, `refactor(core): …`.
- Коммитьте логически связанные изменения вместе.

## Платформа

Проект — **Android only**. Сборку/запуск делайте в Android Studio
(`flutter run`, `flutter build apk`).
