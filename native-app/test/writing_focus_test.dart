import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/repository.dart';

void main() {
  testWidgets(
    'essay keeps keyboard, caret and draft across timer ticks and repository refresh',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      db.set('serverId', 'owner-server');
      final repo = DashboardRepository(
        db,
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      await tester.pumpWidget(
        DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Письмо').first);
      await tester.pump();
      await tester.tap(find.text('Новая запись'));
      await tester.pump();
      final editor = tester.widget<q.QuillEditor>(find.byType(q.QuillEditor));
      editor.focusNode.requestFocus();
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Моя мысль · 思考\n',
          selection: TextSelection.collapsed(offset: 14),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final selection = editor.controller.selection;
      expect(editor.focusNode.hasFocus, isTrue);
      for (var tick = 0; tick < 3; tick++) {
        await tester.pump(const Duration(seconds: 1));
        final updated = tester.widget<q.QuillEditor>(
          find.byType(q.QuillEditor),
        );
        expect(updated.focusNode, same(editor.focusNode));
        expect(updated.scrollController, same(editor.scrollController));
        expect(updated.focusNode.hasFocus, isTrue);
        expect(updated.controller.selection, selection);
        expect(tester.testTextInput.isVisible, isTrue);
      }
      repo.setAndroidOverlayEnabled(false);
      await tester.pump();
      expect(
        tester
            .widget<q.QuillEditor>(find.byType(q.QuillEditor))
            .focusNode
            .hasFocus,
        isTrue,
      );
      const continued = 'Моя мысль · 思考 — продолжаю без клика';
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '$continued\n',
          selection: TextSelection.collapsed(offset: continued.length),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        editor.controller.document.toPlainText(),
        'Моя мысль · 思考 — продолжаю без клика\n',
      );
      final saved = object(
        db.drafts.singleWhere(
          (d) => d['entity'].toString().startsWith('composer:'),
        )['body'],
      );
      expect(
        rows(object(saved['document'])['ops']).first['insert'],
        'Моя мысль · 思考 — продолжаю без клика\n',
      );
      expect(tester.takeException(), isNull);
      final beforeSwitch = editor.controller.selection;
      await tester.tap(find.widgetWithText(FilledButton, 'Работа').first);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Письмо').first);
      await tester.pump();
      final afterSwitch = tester.widget<q.QuillEditor>(
        find.byType(q.QuillEditor),
      );
      expect(afterSwitch.controller, same(editor.controller));
      expect(afterSwitch.controller.selection, beforeSwitch);
      tester.view.physicalSize = const Size(700, 1200);
      await tester.pump();
      expect(
        tester.widget<q.QuillEditor>(find.byType(q.QuillEditor)).controller,
        same(editor.controller),
      );
      tester.view.physicalSize = const Size(1400, 1200);
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('writing-clean-sheet')),
      );
      await tester.tap(find.byKey(const ValueKey('writing-clean-sheet')));
      await tester.pumpAndSettle();
      expect(find.text('Чистый лист'), findsOneWidget);
      expect(find.text('Архив записей').hitTestable(), findsNothing);
      final cleanEditor = tester.widget<q.QuillEditor>(
        find.byType(q.QuillEditor).last,
      );
      cleanEditor.controller.replaceText(0, 0, 'Из чистого листа · ', null);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Вернуться к записям'));
      await tester.pumpAndSettle();
      final returnedEditor = tester.widget<q.QuillEditor>(
        find.byType(q.QuillEditor),
      );
      expect(
        returnedEditor.controller.document.toPlainText(),
        'Из чистого листа · Моя мысль · 思考 — продолжаю без клика\n',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
}
