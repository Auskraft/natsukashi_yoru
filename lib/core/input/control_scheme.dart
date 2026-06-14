/// Способы управления игрой и направления экранных контролов.
///
/// Пользователь выбирает схему отдельно для каждой игры в разделе «Управление»
/// (лобби → Управление). Значение хранится в `GameStorage` по ключу
/// `ctrl_<gameId>`. По умолчанию — [ControlScheme.gestures] (как было изначально).
library;

/// Способ управления игрой.
enum ControlScheme {
  /// Свайпы/жесты по экрану — поведение по умолчанию.
  gestures,

  /// Экранная крестовина (D-pad).
  dpad,

  /// Плавающий джойстик.
  joystick;

  String get id => name;

  /// Разбор сохранённого значения; неизвестное/`null` → [gestures].
  static ControlScheme fromId(String? id) => ControlScheme.values.firstWhere(
        (s) => s.id == id,
        orElse: () => ControlScheme.gestures,
      );

  /// Короткое название для чипа.
  String get label => switch (this) {
        ControlScheme.gestures => 'Жесты',
        ControlScheme.dpad => 'D-pad',
        ControlScheme.joystick => 'Джойстик',
      };

  /// Эмодзи-иконка для чипа/строки списка.
  String get emoji => switch (this) {
        ControlScheme.gestures => '👆',
        ControlScheme.dpad => '🎮',
        ControlScheme.joystick => '🕹️',
      };

  /// Пояснение под превью в пикере.
  String get description => switch (this) {
        ControlScheme.gestures =>
          'Свайпы по экрану — проводи пальцем в нужную сторону. '
              'Ничего не загораживает поле.',
        ControlScheme.dpad =>
          'Экранная крестовина внизу. Чёткие нажатия по направлениям — '
              'удобно одной рукой.',
        ControlScheme.joystick =>
          'Плавающий джойстик: зажми и веди в сторону. '
              'Палец сам тянется к центру.',
      };
}

/// Направление, выдаваемое экранными контролами (независимо от конкретной игры).
/// Каждая игра сама сопоставляет [PadDir] со своим типом направления.
enum PadDir { up, down, left, right }
