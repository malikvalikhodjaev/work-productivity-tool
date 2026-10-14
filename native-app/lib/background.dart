import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'domain.dart';
import 'repository.dart';

class BackgroundRuntime {
  static const channel = MethodChannel('iw/background');
  final DashboardRepository repo;
  final AudioPlayer audio = AudioPlayer();
  final AudioPlayer alarm = AudioPlayer();
  tray.TrayIcon? trayIcon;
  tray.Menu? menu;
  String? previous;
  BackgroundRuntime(this.repo);
  Future<void> initialize({
    required Future<void> Function() show,
    required Future<void> Function() exit,
    required Future<void> Function(String) open,
  }) async {
    if (Platform.isAndroid) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'open' && call.arguments is String) {
          await open(call.arguments as String);
        }
      });
      final launch = await channel.invokeMethod<String>('launchScreen');
      if (launch != null) await open(launch);
    }
    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      await windowManager.setMinimumSize(const Size(380, 540));
      await windowManager.setTitle('Indicators & Work Dashboard');
      trayIcon = tray.TrayIcon.create();
      if (trayIcon == null) {
        throw StateError(
          'Не удалось создать иконку трея; окно останется доступным.',
        );
      }
      trayIcon!.icon = tray.ImageAsset.fromAsset('assets/iw.png');
      trayIcon!.setTooltip('Indicators & Work Dashboard');
      trayIcon!.addListener((event) {
        if (event is tray.TrayIconClickedEvent ||
            event is tray.TrayIconDoubleClickedEvent) {
          show();
        }
      });
      menu = tray.Menu.create();
      if (menu == null) throw StateError('Не удалось создать меню трея.');
      final open = tray.MenuItem.createWithLabelAndType(
        'Открыть дашборд',
        tray.MenuItemType.normal,
      )!;
      open.addListener((event) {
        if (event is tray.MenuItemClickedEvent) show();
      });
      final quit = tray.MenuItem.createWithLabelAndType(
        'Завершить приложение',
        tray.MenuItemType.normal,
      )!;
      quit.addListener((event) {
        if (event is tray.MenuItemClickedEvent) exit();
      });
      menu!.addItem(open);
      menu!.addSeparator();
      menu!.addItem(quit);
      trayIcon!.setContextMenu(menu!);
      trayIcon!.setVisible(true);
      await windowManager.setPreventClose(true);
      await audio.setReleaseMode(ReleaseMode.loop);
    }
    await update();
  }

  Future<void> update() async {
    final s = repo.active;
    final sound = (repo.local.get('sound') ?? 'brown').toString();
    final enabled = repo.local.get('soundEnabled') == true;
    final volume = (repo.local.get('volume') as num? ?? .2).toDouble();
    final payload = {
      'active': s,
      'local': repo.isLocal,
      'timerRevision': repo.cache('timer')['revision'] ?? 0,
      'serverUrl': repo.base,
      'serverOffset': repo.local.get('serverOffset') ?? 0,
      'sound': enabled ? sound : null,
      'volume': volume,
      'norms': repo.dailyNorms,
      'pomodoroTargets': repo.pomodoroRows,
      'pomodoroCounts': repo.pomodoroTargetsForDate(),
      'planningReady': repo.cache('dailyNorms').isNotEmpty,
      'pomodoroHiddenUntil': repo.local.get('pomodoroReminder:${today()}') ?? 0,
      'checks': repo.dailyChecks,
      'today': today(),
      'hidden': repo.local.get('reminderHidden') ?? {},
      'repeatMinutes': 60,
    };
    final next = jsonEncode(payload);
    if (next == previous) return;
    previous = next;
    if (Platform.isAndroid) {
      await channel.invokeMethod('update', payload);
    } else if (Platform.isWindows) {
      if (enabled) {
        await audio.setVolume(volume);
        if (repo.local.get('playingSound') != sound ||
            audio.state != PlayerState.playing) {
          await audio.play(AssetSource('audio/$sound.wav'));
          repo.local.set('playingSound', sound);
        }
      } else {
        await audio.stop();
      }
    }
  }

  Future<void> notifyTimer() async {
    if (Platform.isWindows) await alarm.play(AssetSource('audio/alarm.wav'));
  }

  Future<bool> exactAlarmAllowed() async => Platform.isAndroid
      ? (await channel.invokeMethod<bool>('exactAlarmAllowed') ?? false)
      : true;
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) await channel.invokeMethod('permissions');
  }

  Future<void> shareExport(String path) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod('shareExport', {'path': path});
    }
  }

  Future<void> show() async {
    if (Platform.isWindows) {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    }
  }

  Future<void> focusMode(bool value) async {
    if (Platform.isWindows) {
      await windowManager.setSize(
        value ? const Size(460, 720) : const Size(1200, 850),
      );
      await windowManager.setAlwaysOnTop(
        value && repo.local.get('pinFocus') == true,
      );
    }
  }

  Future<void> close() async {
    if (Platform.isAndroid) channel.setMethodCallHandler(null);
    await audio.dispose();
    await alarm.dispose();
    trayIcon?.setVisible(false);
  }
}
