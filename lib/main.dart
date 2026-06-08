import 'package:flutter/material.dart';

import 'core/storage/game_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/menu/menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Сразу показываем сплэш, параллельно грузим хранилище.
  runApp(const SplashApp());
  await Future.wait([
    GameStorage.init(),
    Future<void>.delayed(const Duration(milliseconds: 1500)),
  ]);

  runApp(const NatsukashiYoruApp());
}

/// Полноэкранный сплэш на время загрузки. Та же картинка, что и в нативном
/// сплэше, — переход бесшовный. `BoxFit.cover` растягивает на весь экран.
class SplashApp extends StatelessWidget {
  const SplashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF000107),
        body: SizedBox.expand(
          child: Image(
            image: AssetImage('assets/icon/splash.png'),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

/// Корень приложения. Тема собирается из палитры (см. [AppTheme]),
/// стартовый экран — главное меню выбора игры.
class NatsukashiYoruApp extends StatelessWidget {
  const NatsukashiYoruApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Natsukashi Yoru',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.night,
      home: const MenuScreen(),
    );
  }
}
