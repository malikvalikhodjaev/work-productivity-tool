import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/focus_gallery_settings.dart';
import 'package:indicators_work/focus_rotation.dart';
import 'package:indicators_work/focus_theme.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';

void main() {
  test('five distinct artworks per artist and compatible saved IDs', () {
    expect(focusArtworks.length, 35);
    expect(focusArtworks.map((a) => a.id).toSet().length, 35);
    expect(focusArtworks.map((a) => a.file).toSet().length, 35);
    for (final artist in focusArtists.keys) {
      expect(focusArtworks.where((a) => a.artist == artist).length, 5);
      expect(focusArt.containsKey(artist), isTrue);
    }
  });
  test('rotation uses wall-clock boundaries including sleep and restart', () {
    final settings = {
      'enabled': true,
      'minutes': 10,
      'anchorMs': 1000,
      'pool': ['monet', 'monet-2', 'monet-3', 'monet-4', 'monet-5'],
    };
    expect(focusThemeAt('monet', settings, 600999), 'monet');
    expect(focusThemeAt('monet', settings, 601000), 'monet-2');
    // Reconstituting saved JSON produces the same selection after 43 minutes.
    final restored = jsonDecode(jsonEncode(settings)) as Map<String, dynamic>;
    expect(focusThemeAt('monet', restored, 43 * 60000 + 1000), 'monet-5');
    expect(focusThemeAt('monet', restored, 50 * 60000 + 1000), 'monet');
    final fourHours = {...settings, 'minutes': 240};
    expect(focusThemeAt('monet', fourHours, 240 * 60000 + 999), 'monet');
    expect(focusThemeAt('monet', fourHours, 240 * 60000 + 1000), 'monet-2');
    expect(focusThemeAt('monet', settings, 0), 'monet');
  });
  test(
    'manual choice resets schedule; disabled or empty pool preserves theme',
    () {
      final settings = {
        'enabled': true,
        'minutes': 10,
        'anchorMs': 0,
        'pool': ['monet', 'monet-2'],
      };
      final restarted = restartRotation(settings, nowMs: 900000);
      expect(focusThemeAt('monet-2', restarted, 900000), 'monet-2');
      expect(focusThemeAt('monet-2', restarted, 1500000), 'monet');
      expect(
        focusThemeAt('green', {...settings, 'enabled': false}, 9999999),
        'green',
      );
      expect(
        focusThemeAt('custom', {
          ...settings,
          'pool': ['missing'],
        }, 9999999),
        'custom',
      );
      expect(rotationMinutes({'minutes': -1}), 10);
      expect(
        rotationPool({
          'pool': ['monet', 'missing', 'monet'],
        }),
        ['monet'],
      );
    },
  );
  testWidgets(
    'gallery config is local and never changes timer, drafts or outbox',
    (tester) async {
      final db = LocalDatabase(':memory:');
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      db.capture('timer', {
        'active': {'id': 'unchanged', 'status': 'paused'},
      });
      db.keepDraft('essay:one', {'text': '  raw\nparagraph  '});
      final beforeTimer = jsonEncode(repo.cache('timer'));
      final beforeDrafts = jsonEncode(db.drafts);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FocusGallerySettings(repo: repo),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(db.get('focusRotation')['enabled'], isTrue);
      expect(db.get('focusRotation')['pool'].length, 35);
      await tester.tap(find.text('4 часа'));
      await tester.pumpAndSettle();
      expect(db.get('focusRotation')['minutes'], 240);
      await tester.enterText(
        find.byKey(const ValueKey('focus-rotation-minutes')),
        '17',
      );
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(db.get('focusRotation')['minutes'], 17);
      await tester.tap(find.text('Библиотека картин · 35'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(5));
      await tester.tap(find.text('Выбрать').first);
      await tester.pumpAndSettle();
      expect(db.get('theme'), 'monet-2');
      await tester.tap(find.byTooltip('Закрыть библиотеку картин'));
      await tester.pumpAndSettle();
      expect(jsonEncode(repo.cache('timer')), beforeTimer);
      expect(jsonEncode(db.drafts), beforeDrafts);
      expect(db.queue, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
