import 'package:flutter/material.dart';

import 'core/storage/game_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/menu/menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GameStorage.init();
  runApp(const NatsukashiYoruApp());
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
