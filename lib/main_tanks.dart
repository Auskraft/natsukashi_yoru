import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

import 'core/legal/legal_screens.dart';
import 'core/storage/game_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/tanks/app/tanks_game_screen.dart';

/// Точка входа **отдельного приложения «Танчики»** (флейвор `tanks`).
///
/// Запуск в разработке: `flutter run -t lib/main_tanks.dart`.
/// На фазе 2 бутит сразу в бой (демо-уровень); домашняя витрина с режимами
/// (Кампания/Выживание/Дейли) появится в фазе 5.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const _SplashApp());
  await Future.wait([
    GameStorage.init(),
    _enableHighRefreshRate(),
    Future<void>.delayed(const Duration(milliseconds: 1200)),
  ]);

  runApp(const TanksApp());
}

Future<void> _enableHighRefreshRate() async {
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (_) {
    // Платформа не поддерживает — остаёмся на 60 Гц.
  }
}

/// Полноэкранный сплэш на время загрузки (та же картинка, что и нативный сплэш).
class _SplashApp extends StatelessWidget {
  const _SplashApp();

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

/// Корень приложения «Танчики». При первом запуске — экран согласия с
/// документами (общий флаг `consent_accepted_v1`), далее — игра.
class TanksApp extends StatefulWidget {
  const TanksApp({super.key});

  @override
  State<TanksApp> createState() => _TanksAppState();
}

class _TanksAppState extends State<TanksApp> {
  late bool _consent = GameStorage.instance.consentAccepted;

  void _acceptConsent() {
    unawaited(GameStorage.instance.acceptConsent());
    setState(() => _consent = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Танчики',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.night,
      home: _consent
          ? const TanksGameScreen()
          : ConsentScreen(onAccept: _acceptConsent),
    );
  }
}
