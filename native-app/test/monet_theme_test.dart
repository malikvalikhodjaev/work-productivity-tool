import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/compact_timer.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/focus_theme.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/repository.dart';

void main() {
  testWidgets('Monet is bundled and changing theme preserves active work', (
    tester,
  ) async {
    final bytes = await rootBundle.load(
      'assets/art/monet-water-lilies-1906.jpg',
    );
    expect(bytes.lengthInBytes, greaterThan(100000));
    expect(bytes.buffer.asUint8List(bytes.offsetInBytes, 2), [255, 216]);
    final db = LocalDatabase(':memory:');
    final repo = DashboardRepository(
      db,
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    db.set('reminderSnoozeUntil', repo.now + 3600000);
    final session = newLocalSession(
      title: 'Моя работа',
      workRef: 'work:one',
      now: repo.now,
    );
    db.capture('timer', {'revision': 1, 'active': session});
    final before = jsonEncode(db.snapshot('timer'));
    await tester.pumpWidget(
      DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
    );
    await tester.tap(find.text('Работа').last);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Моне · Кувшинки'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Моне · Кувшинки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Моне · Кувшинки'));
    await tester.pumpAndSettle();
    expect(db.get('theme'), 'monet');
    expect(jsonEncode(db.snapshot('timer')), before);
    expect(db.queue, isEmpty);
    expect(find.byType(FocusSurface), findsOneWidget);
    expect(
      tester.widget<FocusSurface>(find.byType(FocusSurface)).theme,
      'monet',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: CompactTimer(
              session: repo.active,
              now: repo.now,
              theme: db.get('theme').toString(),
              pause: () {},
              finish: () {},
              checklist: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FocusSurface>(find.byType(FocusSurface)).theme,
      'monet',
    );
    expect(find.text('Пауза'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });
}
