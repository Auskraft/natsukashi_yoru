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

  /// Экранная крестовина по центру (D-pad).
  dpad,

  /// Раздельно: вверх/вниз слева, влево/вправо справа.
  dpadSplitLeft,

  /// Раздельно: вверх/вниз справа, влево/вправо слева.
  dpadSplitRight,

  /// Плавающий джойстик.
  joystick,

  /// Поворот относительно курса (2 кнопки).
  turnButtons,

  /// Наклон телефона (гироскоп/акселерометр).
  gyro,

  /// Кнопки для падающих фигур: ◄ ► + поворот + сброс (Tetris/Puyo).
  tetrisButtons,

  /// Кнопки ракетки: ◄ ► (удержание) + запуск мяча (Breakout).
  paddleButtons;

  String get id => name;

  /// Разбор сохранённого значения; неизвестное/`null` → [gestures].
  static ControlScheme fromId(String? id) => ControlScheme.values.firstWhere(
        (s) => s.id == id,
        orElse: () => ControlScheme.gestures,
      );

  /// Короткое название для чипа.
  String get label => switch (this) {
        ControlScheme.gestures => 'Жесты',
        ControlScheme.dpad => 'Крестовина',
        ControlScheme.dpadSplitLeft => '↕ слева',
        ControlScheme.dpadSplitRight => '↕ справа',
        ControlScheme.joystick => 'Джойстик',
        ControlScheme.turnButtons => 'Поворот',
        ControlScheme.gyro => 'Наклон',
        ControlScheme.tetrisButtons => 'Кнопки',
        ControlScheme.paddleButtons => 'Кнопки',
      };

  /// Эмодзи-иконка для чипа/строки списка.
  String get emoji => switch (this) {
        ControlScheme.gestures => '👆',
        ControlScheme.dpad => '🎮',
        ControlScheme.dpadSplitLeft => '🎮',
        ControlScheme.dpadSplitRight => '🎮',
        ControlScheme.joystick => '🕹️',
        ControlScheme.turnButtons => '🔄',
        ControlScheme.gyro => '📱',
        ControlScheme.tetrisButtons => '🎮',
        ControlScheme.paddleButtons => '🎮',
      };

  /// Пояснение под превью в пикере.
  String get description => switch (this) {
        ControlScheme.gestures =>
          'Свайпы по экрану — проводи пальцем в нужную сторону. '
              'Ничего не загораживает поле.',
        ControlScheme.dpad =>
          'Крестовина по центру внизу. Чёткие нажатия по направлениям — '
              'удобно одной рукой.',
        ControlScheme.dpadSplitLeft =>
          'Раздельно под две руки: вверх/вниз — слева, влево/вправо — справа.',
        ControlScheme.dpadSplitRight =>
          'Раздельно под две руки: вверх/вниз — справа, влево/вправо — слева.',
        ControlScheme.joystick =>
          'Плавающий джойстик: зажми и веди в сторону. '
              'Палец сам тянется к центру.',
        ControlScheme.turnButtons =>
          'Две кнопки: поворот влево/вправо относительно курса. '
              'Как в классических аркадных змейках.',
        ControlScheme.gyro =>
          'Наклоняй телефон — змейка едет туда. '
              'Чувствительность можно подкрутить.',
        ControlScheme.tetrisButtons =>
          'Кнопки ◄ ► + поворот + сброс. Удобно управлять падающими фигурами.',
        ControlScheme.paddleButtons =>
          'Кнопки ◄ ► (удержание) двигают ракетку, отдельная кнопка запускает мяч.',
      };
}

/// Направление, выдаваемое экранными контролами (независимо от конкретной игры).
/// Каждая игра сама сопоставляет [PadDir] со своим типом направления.
enum PadDir { up, down, left, right }
