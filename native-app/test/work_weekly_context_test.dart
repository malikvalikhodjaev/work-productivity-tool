import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/section_analytics.dart';

void main() {
  testWidgets(
    'week problem follows day problem in all rows and switches with historical week',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final week = weekStart(),
          previous = DateTime.parse(weekStart())
              .subtract(const Duration(days: 7))
              .toIso8601String()
              .substring(0, 10);
      final db = LocalDatabase(':memory:')
        ..set('serverId', 'owner')
        ..set('automaticSync', false);
      db.capture('weeklyProblems', {
        'entries': [
          {'week': week, 'text': 'Исходная текущая неделя'},
          {'week': previous, 'text': '  Прошлая\nпроблема  '},
        ],
      });
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      repo.saveWeeklyProblem(week, '  Текущая\nпроблема без потери текста  ');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: WorkAnalytics(repo: repo)),
          ),
        ),
      );
      DataTable table() => tester.widget<DataTable>(
        find.byWidgetPredicate(
          (w) =>
              w is DataTable &&
              w.columns.any(
                (c) =>
                    c.label is Text && (c.label as Text).data == 'Проблема дня',
              ),
        ),
      );
      expect(
        table().columns.map((c) => (c.label as Text).data).toList().sublist(5),
        ['Проблема дня', 'Проблема недели'],
      );
      expect(table().rows.length, 7);
      String text(DataRow row) =>
          ((row.cells.last.child as SizedBox).child as SelectableText).data!;
      expect(table().rows.map(text).toSet(), {
        '  Текущая\nпроблема без потери текста  ',
      });
      expect(find.text('Главная проблема выбранной недели'), findsNothing);
      await tester.tap(find.byTooltip('Предыдущая неделя'));
      await tester.pump();
      expect(table().rows.map(text).toSet(), {'  Прошлая\nпроблема  '});
      await tester.tap(find.byTooltip('Предыдущая неделя'));
      await tester.pump();
      expect(table().rows.map(text).toSet(), {'No Data · не записана'});
      expect(repo.pending.length, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
