// Дымовой тест каркаса: меню рисует карточки всех игр из реестра.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:natsukashi_yoru/main.dart';
import 'package:natsukashi_yoru/features/menu/game_catalog.dart';

void main() {
  testWidgets('Меню показывает все 6 игр из каталога', (tester) async {
    await tester.pumpWidget(const NatsukashiYoruApp());

    expect(find.text('Natsukashi Yoru'), findsOneWidget);
    expect(kGameCatalog.length, 6);

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
