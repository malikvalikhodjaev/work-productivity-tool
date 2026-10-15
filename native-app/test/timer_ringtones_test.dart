import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/timer_ringtones.dart';

void main() {
  test('only bundled sounds and finite volume are accepted', () {
    expect(validRingtone('../../file'), 'bip_bip');
    expect(validRingtone('glass'), 'glass');
    expect(validRingtoneVolume(double.nan), .65);
    expect(validRingtoneVolume(3), 1);
    expect(validRingtoneVolume(-1), 0);
    expect(ringtoneAsset('classic'), 'audio/alarm.wav');
  });
  testWidgets(
    'preview does not change selection or timer; selection persists in the local database',
    (tester) async {
      final db = LocalDatabase(':memory:');
      final repo = DashboardRepository(db);
      final played = <String>[];
      var stopped = 0, changed = 0;
      Widget library() => MaterialApp(
        home: Scaffold(
          body: TimerRingtoneLibrary(
            repo: repo,
            preview: (id, volume) async => played.add(id),
            stop: () async {
              stopped++;
            },
            changed: () => changed++,
          ),
        ),
      );
      await tester.pumpWidget(library());
      await tester.tap(find.byTooltip('Прослушать: Стекло'));
      await tester.pumpAndSettle();
      expect(played, ['glass']);
      expect(db.get('timerRingtone'), isNull);
      expect(repo.active, isNull);
      expect(repo.pending, isEmpty);
      await tester.tap(find.text('Сонар'));
      await tester.pumpAndSettle();
      expect(db.get('timerRingtone'), 'sonar');
      expect(changed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(stopped, greaterThan(0));
      await tester.pumpWidget(library());
      expect(find.text('Выбран: Сонар'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
}
