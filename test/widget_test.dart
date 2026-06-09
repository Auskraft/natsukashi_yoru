// Дымовой тест каркаса: меню рисует карточки всех игр из реестра.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natsukashi_yoru/main.dart';
import 'package:natsukashi_yoru/core/storage/game_storage.dart';
import 'package:natsukashi_yoru/features/menu/game_catalog.dart';

void main() {
  setUp(() async {
    // Согласие уже принято — пропускаем стартовый экран согласия, сразу лобби.
    SharedPreferences.setMockInitialValues({'consent_accepted_v1': true});
    await GameStorage.init();
  });

  testWidgets('Меню показывает все игры из каталога', (tester) async {
    await tester.pumpWidget(const NatsukashiYoruApp());

    expect(find.text('Выбери игру'), findsOneWidget);
    expect(kGameCatalog.length, 14);

    // GridView ленивый — скроллим до каждой карточки (нижние за вьюпортом).
    for (final entry in kGameCatalog) {
      await tester.scrollUntilVisible(
        find.text(entry.title),
        120,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text(entry.title), findsOneWidget);
    }
  });
}
