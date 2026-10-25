import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'domain.dart';
import 'repository.dart';
import 'desktop_timer_window.dart';
import 'timer_ringtones.dart';

class BackgroundRuntime {
  static const channel = MethodChannel('iw/background');
  final DashboardRepository repo;
  final String appTitle;
  final bool timerOnly;
  final AudioPlayer audio = AudioPlayer();
  final AudioPlayer alarm = AudioPlayer();
  final AudioPlayer preview = AudioPlayer();
  tray.TrayIcon? trayIcon;
  tray.Menu? menu;
  String? previous;
  DesktopTimerWindow? desktop;
  BackgroundRuntime(
    this.repo, {
    this.appTitle = 'Indicators & Work Dashboard',
    this.timerOnly = false,
  });
  Future<void> initialize({
    required Future<void> Function() show,
    required Future<void> Function() exit,
    required Future<void> Function(String) open,
    required void Function() windowChanged,
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
      desktop = DesktopTimerWindow(
        NativeDesktopWindow(),
        changed: windowChanged,
      );
      await windowManager.setMinimumSize(const Size(380, 540));
      await windowManager.setTitle(appTitle);
      if (!timerOnly) await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      trayIcon = tray.TrayIcon.create();
      if (trayIcon == null) {
        throw StateError(
          'Не удалось создать иконку трея; окно останется доступным.',
        );
      }
      trayIcon!.icon = tray.ImageAsset.fromAsset('assets/iw.png');
      trayIcon!.setTooltip(appTitle);
      trayIcon!.addListener((event) {
        if (event is tray.TrayIconClickedEvent ||
            event is tray.TrayIconDoubleClickedEvent) {
          show();
        }
      });
      menu = tray.Menu.create();
      if (menu == null) throw StateError('Не удалось создать меню трея.');
      final open = tray.MenuItem.createWithLabelAndType(
        timerOnly ? 'Открыть таймер' : 'Открыть дашборд',
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
      final hide = tray.MenuItem.createWithLabelAndType(
        'Скрыть таймер в трей',
        tray.MenuItemType.normal,
      )!;
      hide.addListener((event) {
        if (event is tray.MenuItemClickedEvent) desktop?.hide();
      });
      menu!.addItem(hide);
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
      'timerOnly': timerOnly,
      'active': s,
      'timerRingtone': validRingtone(repo.local.get('timerRingtone')),
      'dailyProblem': {
        'date': today(),
        'loaded': repo.todayProblemLoaded,
        'text': repo.todayProblem['text'],
      },
      'problemLocalChanges': repo.local.draft('problem:${today()}') != null,
      'local': repo.isLocal,
      'timerLocalChanges': repo.timerPending,
      'automaticSync': repo.automaticSync,
      'timerRevision': repo.cache('timer')['revision'] ?? 0,
      'serverUrl': repo.base,
      'serverAuthorization': repo.serverAuthorization,
      'serverOffset': repo.local.get('serverOffset') ?? 0,
      'sound': enabled ? sound : null,
      'volume': volume,
      'norms': repo.dailyNorms,
      'pomodoroTargets': repo.pomodoroRows,
      'pomodoroCapacities': repo.pomodoroCapacityRows,
      'pomodoroCounts': repo.pomodoroTargetsForDate(),
      'pomodoroDay': today(),
      'overlayEnabled': repo.local.get('androidOverlayEnabled') != false,
      'planOnline': timerOnly || repo.online,
      'planLocalChanges':
          repo.pomodoroFacts.any(
            (f) => f['date'] == today() && f['pending'] == true,
          ) ||
          repo.local.drafts.any(
            (d) =>
                d['entity'].toString().startsWith('pomodoro:') ||
                d['entity'].toString().startsWith('capacity:'),
          ) ||
          repo.pending.any(
            (q) => [
              'pomodoroTarget',
              'pomodoroCapacity',
            ].contains(object(q['body'])['module']),
          ),
      'planningReady': repo.cache('dailyNorms').isNotEmpty,
      'pomodoroHiddenUntil': repo.local.get('pomodoroReminder:${today()}') ?? 0,
      'checks': repo.dailyChecks,
      'today': today(),
      'hidden': repo.local.get('reminderHidden') ?? {},
      'repeatMinutes': 60,
    };
    final next = jsonEncode(payload);
    if (next == previous) return;
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
    previous = next;
  }

  Future<void> notifyTimer({bool foreground = true}) async {
    if (Platform.isAndroid && foreground) {
      final session = repo.active;
      if (session == null) return;
      final resting = inLeisure(session);
      final fresh = await channel.invokeMethod<bool>('claimTimerSound', {
        'kind': resting ? 'leisure' : 'timer',
        'key': resting
            ? leisureKey(session)
            : '${session['id']}:${session['plannedMs']}',
      });
      if (fresh != true) return;
    }
    if (Platform.isWindows || (Platform.isAndroid && foreground)) {
      await alarm.stop();
      await alarm.setVolume(
        validRingtoneVolume(repo.local.get('timerRingtoneVolume')),
      );
      await alarm.play(
        AssetSource(ringtoneAsset(repo.local.get('timerRingtone'))),
      );
    }
  }

  Future<void> previewRingtone(String id, double volume) async {
    await preview.stop();
    await preview.setVolume(validRingtoneVolume(volume));
    await preview.play(AssetSource(ringtoneAsset(id)));
  }

  Future<void> stopRingtonePreview() => preview.stop();
  Future<void> ringtoneSystemSettings() => channel.invokeMethod(
    'ringtoneSettings',
    validRingtone(repo.local.get('timerRingtone')),
  );

  Future<bool> exactAlarmAllowed() async => Platform.isAndroid
      ? (await channel.invokeMethod<bool>('exactAlarmAllowed') ?? false)
      : true;
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) await channel.invokeMethod('permissions');
  }

  Future<bool> overlayAllowed() async => Platform.isAndroid
      ? (await channel.invokeMethod<bool>('overlayAllowed') ?? false)
      : false;

  Future<void> requestOverlayPermission() async {
    if (Platform.isAndroid) await channel.invokeMethod('overlayPermission');
  }

  Future<void> shareExport(String path) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod('shareExport', {'path': path});
    }
  }

  Future<void> show() async {
    if (Platform.isWindows) {
      await desktop?.showDashboard();
    }
  }

  Future<bool> showCompactTimer() async {
    if (!Platform.isWindows ||
        desktop == null ||
        repo.active == null ||
        repo.local.get('timerOnMinimize') == false) {
      return false;
    }
    await desktop!.minimize(active: true, enabled: true);
    return desktop!.compact;
  }

  Future<void> focusMode(bool value) async {
    if (Platform.isWindows) {
      if (value) {
        await desktop?.showPlayer(pinned: repo.local.get('pinFocus') == true);
      } else {
        await desktop?.showDashboard();
      }
    }
  }

  Future<void> close() async {
    if (Platform.isAndroid) channel.setMethodCallHandler(null);
    await audio.dispose();
    await alarm.dispose();
    await preview.dispose();
    trayIcon?.setVisible(false);
  }
}
