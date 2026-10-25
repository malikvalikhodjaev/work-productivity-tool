import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/compact_timer.dart';
import 'package:indicators_work/desktop_timer_window.dart';
import 'package:indicators_work/domain.dart';

class FakeWindow implements DesktopWindowPort {
  Rect rectangle = const Rect.fromLTWH(120, 80, 1200, 850);
  bool isMaximized = false, isPinned = false, visible = true, minimized = true;
  final events = <String>[];
  @override
  Future<Rect> bounds() async =>
      minimized ? const Rect.fromLTWH(-32000, -32000, 160, 28) : rectangle;
  @override
  Future<bool> maximized() async => isMaximized;
  @override
  Future<bool> pinned() async => isPinned;
  @override
  Future<void> restore() async {
    minimized = false;
    events.add('restore');
  }

  @override
  Future<void> unmaximize() async {
    isMaximized = false;
  }

  @override
  Future<void> maximize() async {
    isMaximized = true;
  }

  @override
  Future<void> minimum(Size size) async {
    events.add('minimum:$size');
  }

  @override
  Future<void> resize(Rect bounds) async {
    rectangle = bounds;
  }

  @override
  Future<void> pin(bool value) async {
    isPinned = value;
  }

  @override
  Future<void> show({bool inactive = false}) async {
    visible = true;
    events.add(inactive ? 'show-inactive' : 'show');
  }

  @override
  Future<void> focus() async {
    events.add('focus');
  }

  @override
  Future<void> hide() async {
    visible = false;
    events.add('hide');
  }
}

void main() {
  test(
    'double-click toggle preserves timer mode and restored geometry',
    () async {
      final window = FakeWindow();
      final controller = DesktopTimerWindow(window, changed: () {});
      await controller.showPlayer(pinned: true);
      final bounds = window.rectangle;
      await controller.toggleMaximized();
      expect(window.isMaximized, true);
      expect(controller.player, true);
      await controller.toggleMaximized();
      expect(window.isMaximized, false);
      expect(controller.player, true);
      expect(window.rectangle, bounds);
      expect(window.isPinned, true);
    },
  );
  test(
    'player and compact window return to original dashboard geometry',
    () async {
      final window = FakeWindow()..isMaximized = true;
      final original = window.rectangle;
      final controller = DesktopTimerWindow(window, changed: () {});
      await controller.showPlayer(pinned: true);
      expect(controller.player, true);
      expect(controller.compact, false);
      expect(window.rectangle.size, const Size(460, 720));
      await controller.showPlayer(pinned: true);
      await controller.minimize(active: true, enabled: true);
      expect(controller.compact, true);
      expect(controller.player, false);
      await controller.showPlayer(pinned: false);
      await controller.showDashboard();
      expect(controller.compact, false);
      expect(controller.player, false);
      expect(window.rectangle, original);
      expect(window.isMaximized, true);
      expect(window.isPinned, false);
    },
  );

  test(
    'opening from tray during shrinking waits and restores dashboard',
    () async {
      final window = FakeWindow();
      final original = window.rectangle;
      final controller = DesktopTimerWindow(window, changed: () {});
      await Future.wait([
        controller.minimize(active: true, enabled: true),
        controller.showDashboard(),
      ]);
      expect(controller.compact, false);
      expect(window.rectangle, original);
      expect(window.visible, true);
    },
  );
  test('minimize leaves a visible timer; repeated minimize preserves dashboard bounds', () async {
    final window = FakeWindow();
    final original = window.rectangle;
    final controller = DesktopTimerWindow(window, changed: () {});
    await controller.minimize(active: true, enabled: true);
    expect(controller.compact, true);
    expect(window.visible, true);
    expect(window.rectangle.topLeft, original.topLeft);
    expect(window.rectangle.size, const Size(430, 430));
    expect(window.isPinned, true);
    expect(window.events, contains('show-inactive'));
    expect(window.events, isNot(contains('focus')));
    await controller.minimize(active: true, enabled: true);
    await controller.showDashboard();
    expect(controller.compact, false);
    expect(window.rectangle, original);
    expect(window.isPinned, false);
  });

  test('explicit tray hiding and reopening preserve maximization and pin preference', () async {
    final window = FakeWindow()
      ..isMaximized = true
      ..isPinned = true;
    final controller = DesktopTimerWindow(window, changed: () {});
    await controller.minimize(active: true, enabled: true);
    await controller.hide();
    expect(window.visible, false);
    expect(controller.compact, true);
    await controller.showDashboard();
    expect(window.visible, true);
    expect(window.isMaximized, true);
    expect(window.isPinned, true);
    expect(controller.compact, false);
  });

  test('idle or explicitly disabled window stays minimized', () async {
    final window = FakeWindow();
    final controller = DesktopTimerWindow(window, changed: () {});
    await controller.minimize(active: false, enabled: true);
    await controller.minimize(active: true, enabled: false);
    expect(controller.compact, false);
    expect(window.events, isEmpty);
    expect(window.minimized, true);
  });

  testWidgets(
    'compact timer shows the same running and paused session with controls',
    (tester) async {
      tester.view.physicalSize = const Size(340, 330);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.utc(2026, 10, 15).millisecondsSinceEpoch;
      final s = newLocalSession(
        title: 'Разобрать проблему',
        workRef: 'case:one',
        now: now,
      );
      var pauses = 0;
      Widget screen(Json session) => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              CompactTimer(
                session: session,
                now: now + 60000,
                theme: 'green',
                pause: () => pauses++,
                finish: () {},
                checklist: const Text('Чтение — 0/1'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(screen(s));
      expect(find.text('24:00'), findsOneWidget);
      expect(find.text('Разобрать проблему'), findsOneWidget);
      expect(find.text('1.0 мин'), findsOneWidget);
      await tester.tap(find.text('Пауза'));
      expect(pauses, 1);
      final paused = changeLocalSession(s, 'pause', now + 60000);
      await tester.pumpWidget(screen(paused));
      expect(find.text('Продолжить'), findsOneWidget);
      expect(find.text('24:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
