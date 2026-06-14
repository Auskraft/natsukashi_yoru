import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/core/input/control_scheme.dart';
import 'package:natsukashi_yoru/core/storage/game_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ControlScheme', () {
    test('fromId round-trips каждое значение', () {
      for (final s in ControlScheme.values) {
        expect(ControlScheme.fromId(s.id), s);
      }
    });

    test('неизвестный или null id → жесты (дефолт)', () {
      expect(ControlScheme.fromId(null), ControlScheme.gestures);
      expect(ControlScheme.fromId('???'), ControlScheme.gestures);
    });

    test('label и description непустые', () {
      for (final s in ControlScheme.values) {
        expect(s.label, isNotEmpty);
        expect(s.description, isNotEmpty);
      }
    });
  });

  group('GameStorage — схема управления', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('по умолчанию жесты; сохраняется и независима по играм', () async {
      final s = await GameStorage.init();
      expect(s.controlScheme('snake'), ControlScheme.gestures);

      await s.setControlScheme('snake', ControlScheme.dpad);
      expect(s.controlScheme('snake'), ControlScheme.dpad);

      // Другая игра не затронута.
      expect(s.controlScheme('tetris'), ControlScheme.gestures);
    });
  });
}
