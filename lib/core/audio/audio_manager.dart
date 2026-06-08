import 'package:flame_audio/flame_audio.dart';

/// Тонкая обёртка над [FlameAudio] для единой точки управления звуком.
///
/// Заготовка под следующие итерации: предзагрузка кэша, флаг mute,
/// громкость музыки/эффектов. Сейчас — минимальный фасад.
class AudioManager {
  AudioManager._();
  static final AudioManager instance = AudioManager._();

  bool muted = false;

  /// Предзагрузить эффекты в кэш. Список файлов появится вместе с ассетами.
  Future<void> preload(List<String> files) => FlameAudio.audioCache.loadAll(files);

  /// Короткий звуковой эффект.
  void sfx(String file) {
    if (muted) return;
    FlameAudio.play(file);
  }
}
