import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:file_selector_windows/file_selector_windows.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'background.dart';
import 'domain.dart';
import 'forms.dart';
import 'local_database.dart';
import 'app_appearance.dart';
import 'section_navigation.dart';
import 'reminders.dart';
import 'repository.dart';
import 'sync_panel.dart';
import 'pomodoro_widgets.dart';
import 'writing_screen.dart';
import 'data_table.dart';
import 'adaptive_focus_player.dart';
import 'work_stage_board.dart';
import 'focus_theme.dart';
import 'focus_gallery_settings.dart';
import 'timer_command_notice.dart';
import 'daily_problem_banner.dart';
import 'weekly_problem_card.dart';
import 'section_analytics.dart';
import 'modeling_workspace.dart';
import 'leisure.dart';
import 'timer_ringtones.dart';
import 'active_timer_conflict.dart';
import 'time_composition.dart';
import 'connection_bootstrap.dart';
import 'goal_progress.dart';
import 'goal_table.dart';
import 'goal_status.dart';
import 'model_link.dart';
import 'activity_status.dart';
import 'dashboard_timer_bar.dart';
import 'dashboard_window_header.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await loadPersonalFocusArt();
  } catch (_) {
    debugPrint(
      'Personal art catalogue unavailable; bundled collection retained.',
    );
  }
  final folder = await getApplicationSupportDirectory();
  await folder.create(recursive: true);
  final repo = DashboardRepository(
    LocalDatabase(p.join(folder.path, 'indicators-work.sqlite')),
  );
  final provisionFolder = Platform.isAndroid
      ? await getExternalStorageDirectory()
      : folder;
  if (provisionFolder != null) {
    try {
      await applyConnectionBootstrap(
        repo.local,
        File(p.join(provisionFolder.path, 'iw-connection.json')),
      );
    } catch (_) {
      debugPrint('Connection provisioning rejected; existing data retained.');
    }
  }
  runApp(DashboardApp(repo: repo, folder: folder.path));
}

class DashboardApp extends StatelessWidget {
  final DashboardRepository repo;
  final String folder;
  final bool backgroundEnabled;
  const DashboardApp({
    super.key,
    required this.repo,
    required this.folder,
    this.backgroundEnabled = true,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final style = repo.local.get('appAppearance')?.toString() ?? 'neutral';
      return MaterialApp(
        title: 'Indicators & Work Dashboard',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          q.FlutterQuillLocalizations.delegate,
        ],
        theme: dashboardTheme(
          style,
          font: repo.local.get('appFont')?.toString() ?? 'system',
        ),
        darkTheme: dashboardTheme(
          style,
          brightness: Brightness.dark,
          font: repo.local.get('appFont')?.toString() ?? 'system',
        ),
        themeMode: style == 'system'
            ? ThemeMode.system
            : style == 'dark'
            ? ThemeMode.dark
            : ThemeMode.light,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(
                media.textScaler.scale(1) * appearanceTextScale(repo),
              ),
            ),
            child: child!,
          );
        },
        home: DashboardHome(
          repo: repo,
          folder: folder,
          backgroundEnabled: backgroundEnabled,
        ),
      );
    },
  );
}

class DashboardHome extends StatefulWidget {
  final DashboardRepository repo;
  final String folder;
  final bool backgroundEnabled;
  const DashboardHome({
    super.key,
    required this.repo,
    required this.folder,
    this.backgroundEnabled = true,
  });
  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome>
    with WidgetsBindingObserver, WindowListener {
  DashboardRepository get repo => widget.repo;
  late BackgroundRuntime background;
  final overlayAllowed = ValueNotifier(false);
  late final List<ScrollController> pageScrolls;
  ScrollController get pageScroll => pageScrolls[section];
  final visitedSections = <int>{0};
  Timer? scrollSave;
  void savePagePositions() {
    for (var i = 0; i < pageScrolls.length; i++) {
      if (pageScrolls[i].hasClients) {
        repo.local.set('pageScroll:$i', pageScrolls[i].offset);
      }
    }
  }

  void selectSection(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    repo.local.set('selectedSection', value);
    setState(() => section = value);
  }

  Timer? ticker;
  final clockPulse = ValueNotifier<int>(0);
  int lastReminderCheck = 0;
  int section = 0;
  bool focusMode = false,
      board = true,
      foreground = true,
      dialogOpen = false,
      trayReady = false,
      exiting = false;
  String? reviewShown;
  String planningDate = today();
  bool planEntryPending = true;
  static const sections = [
    'Показатели',
    'Проекты и модели',
    'Работа',
    'Письмо',
    'Данные',
  ];
  static const icons = [
    Icons.insights_outlined,
    Icons.account_tree_outlined,
    Icons.view_kanban_outlined,
    Icons.edit_note_outlined,
    Icons.table_chart_outlined,
  ];
  static const stages = workStageLabels;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    section = (repo.local.get('selectedSection') as int? ?? 0).clamp(0, 4);
    pageScrolls = List.generate(
      5,
      (i) =>
          ScrollController(
            initialScrollOffset: (repo.local.get('pageScroll:$i') as num? ?? 0)
                .toDouble(),
          )..addListener(() {
            scrollSave?.cancel();
            scrollSave = Timer(
              const Duration(milliseconds: 300),
              savePagePositions,
            );
          }),
    );
    board = repo.local.get('workView') != 'list';
    // This release makes the owner's requested minimize behaviour the default.
    // Later explicit choices in Settings continue to take precedence.
    if (repo.local.get('minimizeTimerPolicy') != 1) {
      repo.local.set('timerOnMinimize', true);
      repo.local.set('minimizeTimerPolicy', 1);
    }
    if (repo.local.get('focusRotation') == null) {
      repo.local.set('focusRotation', {
        'enabled': focusArt.containsKey(repo.local.get('theme')),
        'minutes': 10,
        'anchorMs': DateTime.now().millisecondsSinceEpoch,
        'pool': focusArt.keys.toList(),
      });
    }
    background = BackgroundRuntime(repo);
    repo.addListener(changed);
    if (widget.backgroundEnabled && Platform.isWindows) {
      windowManager.addListener(this);
    }
    if (widget.backgroundEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => initialize());
    }
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> initialize() async {
    try {
      await background.initialize(
        show: show,
        exit: exitApp,
        open: openNotification,
        windowChanged: () {
          if (mounted) setState(() {});
        },
      );
      trayReady = Platform.isWindows;
      if (Platform.isAndroid) await refreshOverlayPermission();
      repo.local.set('backgroundRuntime', {
        'ready': true,
        'platform': Platform.operatingSystem,
        'clientVersion': '0.1.37',
        'tray': trayReady,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      repo.local.set('backgroundRuntime', {
        'ready': false,
        'platform': Platform.operatingSystem,
        'error': e.toString(),
        'at': DateTime.now().toUtc().toIso8601String(),
      });
      message(e.toString());
    }
    repo.startPolling();
  }

  void changed() {
    if (mounted) setState(() {});
    if (widget.backgroundEnabled) {
      unawaited(
        background.update().catchError((Object e) {
          repo.status = e.toString();
        }),
      );
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> show() async {
    await background.show();
    if (mounted) setState(() => focusMode = false);
    foreground = true;
    planEntryPending = true;
  }

  Future<void> openNotification(String screen) async {
    if (!mounted) return;
    await show();
    setState(() {
      section = 2;
      focusMode = screen == 'timer' || screen == 'leisure';
    });
    repo.requestAutoSync();
    if (!mounted || dialogOpen || Navigator.of(context).canPop()) return;
    if (screen == 'leisure' && inLeisure(repo.active)) {
      await offerLeisureReturn();
    } else if (screen == 'norms') {
      final due = dueNorms();
      if (planningDue(force: true)) {
        await showPlanningQuestion(force: true);
      } else if (due.isNotEmpty || repo.hasPomodoroPlan) {
        await showNorms(due);
      }
    } else if (screen == 'timer' && repo.active != null) {
      final s = repo.active!;
      if (s['mode'] == 'pomodoro' && elapsedMs(s, repo.now) >= s['plannedMs']) {
        await finishTimer();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      if (widget.backgroundEnabled && Platform.isAndroid) {
        unawaited(refreshOverlayPermission());
      }
      if (background.desktop?.transitioning != true) planEntryPending = true;
      repo.requestAutoSync();
    }
  }

  Future<void> refreshOverlayPermission() async {
    final allowed = await background.overlayAllowed();
    if (mounted) overlayAllowed.value = allowed;
  }

  @override
  void onWindowMinimize() {
    foreground = false;
    if (!exiting && !dialogOpen) {
      unawaited(keepTimerVisible());
    }
  }

  Future<void> keepTimerVisible() async {
    try {
      if (await background.showCompactTimer()) foreground = true;
    } catch (error) {
      message('Не удалось показать таймер: $error');
    }
  }

  @override
  void onWindowRestore() {
    foreground = true;
    if (background.desktop?.transitioning != true) planEntryPending = true;
  }

  @override
  void onWindowClose() async {
    if (exiting) return;
    if (!await showPlanningQuestion(force: true)) return;
    if (await background.showCompactTimer()) {
      foreground = true;
      return;
    }
    if (trayReady) {
      foreground = false;
      await windowManager.hide();
    } else {
      await windowManager.minimize();
    }
  }

  Future<void> exitApp() async {
    if (!await showPlanningQuestion(force: true)) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Завершить приложение?'),
        content: const Text(
          'Сеанс и локальные записи сохранены. После полного выхода звук и сигналы приложения прекратятся. Для работы в фоне достаточно закрыть окно в трей.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Оставить в фоне'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    exiting = true;
    await background.close();
    if (Platform.isWindows) {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  void tick() {
    if (!mounted) return;
    // Only timer widgets listen to seconds. Boards, editors and analytics
    // refresh on repository changes, not on every countdown tick.
    clockPulse.value++;
    final s = repo.active;
    if (leisureDue(s, repo.now) &&
        !dialogOpen &&
        !Navigator.of(context).canPop() &&
        (foreground || (widget.backgroundEnabled && Platform.isWindows)) &&
        repo.local.get('leisurePrompt') != leisureKey(s!)) {
      unawaited(offerLeisureReturn());
      return;
    }
    if (s != null &&
        s['mode'] == 'pomodoro' &&
        s['status'] == 'running' &&
        elapsedMs(s, repo.now) >= s['plannedMs']) {
      final key = '${s['id']}:${s['plannedMs']}';
      if (repo.local.get('alerted') != key) {
        repo.local.set('alerted', key);
        if (widget.backgroundEnabled) {
          unawaited(background.notifyTimer(foreground: foreground));
        }
        if (widget.backgroundEnabled && Platform.isWindows && !foreground) {
          unawaited(show());
        }
      }
      if (foreground &&
          !dialogOpen &&
          !Navigator.of(context).canPop() &&
          reviewShown != key) {
        reviewShown = key;
        unawaited(finishTimer());
        return;
      }
    }
    if (!dialogOpen && !Navigator.of(context).canPop()) {
      if (planningDate != today()) {
        planningDate = today();
        planEntryPending = true;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!planEntryPending && now - lastReminderCheck < 5000) return;
      lastReminderCheck = now;
      if ((foreground || (widget.backgroundEnabled && Platform.isWindows)) &&
          planningDue(force: planEntryPending)) {
        unawaited(showPlanningQuestion(force: planEntryPending));
        return;
      }
      planEntryPending = false;
      final due = dueNorms();
      if (due.isNotEmpty || pomodoroReminderDue()) unawaited(showNorms(due));
    }
  }

  Future<void> offerLeisureReturn() async {
    final s = repo.active;
    if (!inLeisure(s) || dialogOpen || Navigator.of(context).canPop()) return;
    dialogOpen = true;
    repo.local.set('leisurePrompt', leisureKey(s!));
    try {
      if (widget.backgroundEnabled && Platform.isWindows && !foreground) {
        await show();
      }
      if (widget.backgroundEnabled) {
        unawaited(background.notifyTimer(foreground: foreground));
      }
      if (mounted) await safe(() => askLeisureReturn(context, repo));
    } finally {
      dialogOpen = false;
    }
  }

  bool planningDue({bool force = false}) =>
      repo.cache('dailyNorms').isNotEmpty &&
      !repo.hasPomodoroPlan &&
      (force ||
          DateTime.now().millisecondsSinceEpoch >=
              (repo.local.get('pomodoroReminder:${today()}') as int? ?? 0));

  bool pomodoroReminderDue() =>
      repo.pomodoroTargetsForDate().any(
        (n) => n['actualPomodoros'] < n['target'],
      ) &&
      DateTime.now().millisecondsSinceEpoch >=
          (repo.local.get('pomodoroReminder:${today()}') as int? ?? 0);

  Future<bool> showPlanningQuestion({bool force = false}) async {
    if (!planningDue(force: force)) return true;
    if (dialogOpen || Navigator.of(context).canPop()) return false;
    dialogOpen = true;
    planEntryPending = false;
    bool wasHidden = false, previousPin = false;
    if (widget.backgroundEnabled && Platform.isWindows) {
      wasHidden =
          !await windowManager.isVisible() || await windowManager.isMinimized();
      previousPin = await windowManager.isAlwaysOnTop();
      await windowManager.setAlwaysOnTop(true);
      await background.show();
      foreground = true;
    }
    if (!mounted) return false;
    final setup = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Вы поставили нормативы на день?'),
        content: const Text(
          'На сегодня нет ни одного норматива помидорок. Укажи название, карточку работы и число помидорок. Вопрос исчезнет, когда сохранён хотя бы один норматив на сегодня.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Позже · через час'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Поставить норматив'),
          ),
        ],
      ),
    );
    repo.local.set(
      'pomodoroReminder:${today()}',
      DateTime.now().millisecondsSinceEpoch + 3600000,
    );
    dialogOpen = false;
    planEntryPending = false;
    if (widget.backgroundEnabled && Platform.isWindows) {
      await windowManager.setAlwaysOnTop(previousPin);
      if (wasHidden && setup != true) {
        foreground = false;
        await windowManager.hide();
      }
    }
    if (setup == true && mounted) await settings();
    if (widget.backgroundEnabled) await background.update();
    return setup != true;
  }

  List<Json> dueNorms() {
    final hidden = object(repo.local.get('reminderHidden'));
    return repo.dailyNorms
        .where(
          (norm) => shouldShow(
            norm,
            DateTime.now().millisecondsSinceEpoch,
            hiddenUntil: hidden['${today()}:${norm['workRef']}'] as int?,
            confirmed: repo.dailyChecks.any(
              (c) =>
                  c['date'] == today() &&
                  c['workRef'] == norm['workRef'] &&
                  c['confirmed'] == true,
            ),
            actualMinutes: (norm['actualMinutes'] as num? ?? 0).toDouble(),
          ),
        )
        .toList();
  }

  Future<void> showNorms(List<Json> due) async {
    dialogOpen = true;
    bool wasHidden = false;
    bool previousPin = false;
    bool choseFocus = false;
    if (widget.backgroundEnabled && Platform.isWindows) {
      wasHidden =
          !await windowManager.isVisible() || await windowManager.isMinimized();
      previousPin = await windowManager.isAlwaysOnTop();
      await windowManager.setAlwaysOnTop(true);
      await show();
    }
    if (!mounted) {
      dialogOpen = false;
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, refresh) => AlertDialog(
          title: const Text('Сделал это?'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Дневные нормативы · повтор каждый час'),
                  const SizedBox(height: 18),
                  ListenableBuilder(
                    listenable: repo,
                    builder: (c, _) => PomodoroChecklist(
                      repo: repo,
                      scrollChecks: false,
                      focus: (ref, title) async {
                        choseFocus = true;
                        Navigator.pop(c);
                        await startTimer(ref: ref, title: title);
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final norm in due)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            norm['title'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${norm['actualMinutes'] == null ? 'No Data' : (norm['actualMinutes'] as num).toStringAsFixed(1)} / ${norm['minutes']} мин',
                          ),
                          if ((norm['pendingMinutes'] as num? ?? 0) > 0)
                            const Text(
                              'Часть времени ещё ожидает отправки',
                              style: TextStyle(fontSize: 12),
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () {
                                  final previous = repo.dailyChecks
                                      .where(
                                        (x) =>
                                            x['date'] == today() &&
                                            x['workRef'] == norm['workRef'],
                                      )
                                      .firstOrNull;
                                  repo.nativeSave(
                                    'dailyCheck',
                                    'save',
                                    {
                                      'workRef': norm['workRef'],
                                      'date': today(),
                                      'confirmed': true,
                                    },
                                    'dailycheck:${today()}:${norm['workRef']}',
                                    expectedUpdatedAt: previous?['updatedAt'],
                                  );
                                  refresh(() => due.remove(norm));
                                  if (due.isEmpty) Navigator.pop(c);
                                },
                                child: const Text('✓ Сделано'),
                              ),
                              TextButton(
                                onPressed: () {
                                  choseFocus = true;
                                  Navigator.pop(c);
                                  unawaited(
                                    startTimer(
                                      title: norm['title'].toString(),
                                      ref: norm['workRef'].toString(),
                                    ),
                                  );
                                },
                                child: const Text('▶ Фокус'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Скрыть · до следующего часа'),
            ),
          ],
        ),
      ),
    );
    final hidden = object(repo.local.get('reminderHidden'));
    for (final norm in due) {
      hidden['${today()}:${norm['workRef']}'] = nextReminder(
        norm,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    repo.local.set('reminderHidden', hidden);
    repo.local.set(
      'pomodoroReminder:${today()}',
      DateTime.now().millisecondsSinceEpoch + 3600000,
    );
    dialogOpen = false;
    if (widget.backgroundEnabled && Platform.isWindows) {
      await windowManager.setAlwaysOnTop(previousPin);
      if (wasHidden && !choseFocus) {
        foreground = false;
        await windowManager.hide();
      }
    }
    if (widget.backgroundEnabled) await background.update();
  }

  Future<void> setDailyNorm(String ref, String title) async {
    final old =
        repo.local.draft('norm:$ref') ??
        rows(repo.cache('dailyNorms')['norms'])
            .where((n) => n['workRef'] == ref)
            .firstOrNull ??
        <String, dynamic>{};
    await editFields(
      context,
      title: 'Дневной норматив · $title',
      initial: {
        ...old,
        'workRef': ref,
        'time': old['time'] ?? '09:00',
        'days': (old['days'] as List? ?? [1, 2, 3, 4, 5, 6, 7]).join(','),
        'enabled': old['enabled'] == false ? 'false' : 'true',
      },
      fields: const [
        FieldSpec('minutes', 'Минут в день · пусто для снятия', numeric: true),
        FieldSpec('time', 'Первый показ · HH:MM'),
        FieldSpec('days', 'Дни недели · 1–7 через запятую'),
        FieldSpec(
          'enabled',
          'Напоминания',
          options: {'true': 'Включены · каждый час', 'false': 'Выключены'},
        ),
      ],
      save: (input) async {
        final parts = input['time'].toString().split(':');
        final days = input['days']
            .toString()
            .split(',')
            .map((d) => int.tryParse(d.trim()))
            .toList();
        if (parts.length != 2 ||
            !RegExp(r'^\d{2}:\d{2}$').hasMatch(input['time'].toString()) ||
            (int.tryParse(parts[0]) ?? 99) > 23 ||
            (int.tryParse(parts[1]) ?? 99) > 59) {
          throw ArgumentError('Время: HH:MM, например 09:00.');
        }
        if (days.isEmpty || days.any((d) => d == null || d < 1 || d > 7)) {
          throw ArgumentError('Дни недели: числа от 1 до 7.');
        }
        if (input['minutes'] != null &&
            ((input['minutes'] as num) <= 0 || input['minutes'] > 1440)) {
          throw ArgumentError('Норма: больше нуля, не больше 1440 минут.');
        }
        repo.nativeSave(
          'dailyNorm',
          'save',
          {...input, 'days': days, 'enabled': input['enabled'] == 'true'},
          'norm:$ref',
          expectedUpdatedAt: old['updatedAt'],
        );
      },
    );
  }

  Future<void> finishTimer({
    String? nextRef,
    String nextTitle = '',
    Json? nextItem,
  }) async {
    final s = repo.active;
    if (s == null || dialogOpen) return;
    if (s['phase'] != 'work') {
      await safe(() => repo.timerAction('finish'));
      return;
    }
    dialogOpen = true;
    var finished = false;
    try {
      await editFields(
        context,
        title: s['phase'] == 'work'
            ? 'Как прошла помидорка?'
            : 'Завершить перерыв',
        submitLabel: nextRef == null ? 'Учесть' : 'Учесть и запустить',
        initial: {
          'minutes': ((elapsedMs(s, repo.now) ~/ 1000) / 60).toStringAsFixed(2),
          'observation': '',
        },
        fields: const [
          FieldSpec(
            'minutes',
            'Сколько минут действительно работал',
            numeric: true,
          ),
          FieldSpec(
            'observation',
            'Что сделал за помидорку? Какую систему, какую её характеристику изменил?',
            lines: 6,
            labelAbove: true,
          ),
        ],
        save: (input) async {
          if (repo.active?['id'] != s['id']) {
            throw StateError('Активный сеанс изменился. Обнови состояние.');
          }
          await repo.timerAction(
            'finish',
            observation: input['observation'].toString(),
            workedSeconds: ((input['minutes'] as num) * 60).round(),
          );
          finished = true;
        },
      );
    } finally {
      dialogOpen = false;
    }
    if (finished && nextRef != null && mounted && repo.active == null) {
      await startTimer(ref: nextRef, title: nextTitle, item: nextItem);
    }
  }

  Future<void> startTimer({String title = '', String? ref, Json? item}) async {
    if (ref != null) {
      await safe(() async {
        try {
          await repo.focusWork(ref: ref, title: title, item: item);
        } on ExpiredTimerConflict catch (expired) {
          reviewShown = '${expired.sessionId}:${repo.active?['plannedMs']}';
          await revealMobilePlayer();
          if (mounted) {
            if (repo.active?['id'] != expired.sessionId) {
              throw StateError('Сеанс изменился. Нажми Play ещё раз.');
            }
            await finishTimer(nextRef: ref, nextTitle: title, nextItem: item);
          }
          return;
        }
        if (repo.active?['workRef'] == ref) await revealMobilePlayer();
      });
      return;
    }
    if (repo.active != null) {
      await showActiveTimerConflict(ActiveTimerConflict(repo.active!));
      return;
    }
    final initial = {
      ...repo.settings,
      'title': title,
      'metricId': item?['metricId'] ?? '',
      'allocation': item?['allocation'] ?? 'unclassified',
      'workType': item?['workType'] ?? '',
      'mode': repo.timerMode,
      'strategy': repo.timerStrategy,
    };
    final metricOptions = {
      '': 'Без часового норматива',
      for (final m in rows(
        repo.cache('dashboard')['metrics'],
      ).where((m) => m['unit'] == 'hours'))
        m['id'].toString(): m['title'].toString(),
    };
    String? startedId;
    await editFields(
      context,
      title: 'Начать фокус',
      submitLabel: '▶ Запустить',
      progressLabel: 'Запускаю…',
      initial: initial,
      fields: [
        const FieldSpec('title', 'Что делаю'),
        const FieldSpec(
          'strategy',
          'Учёт',
          options: {
            'shared': 'Общий таймер · сохранение на устройстве',
            'local': 'Таймер устройства · работает без связи',
          },
        ),
        const FieldSpec(
          'mode',
          'Режим',
          options: {'pomodoro': 'Помидорка', 'stopwatch': 'Секундомер'},
        ),
        FieldSpec('metricId', 'Часовой норматив', options: metricOptions),
        const FieldSpec(
          'allocation',
          'Если норматив не выбран',
          options: {
            'unclassified': 'Требует разбора',
            'outside': 'Вне нормативов',
            'assigned': 'По нормативу',
          },
        ),
        FieldSpec(
          'workType',
          'Типы времени',
          timeTypes: true,
          options: timeTypeOptions(initial['workType']),
        ),
        const FieldSpec('workMinutes', 'Помидорка · минут', integer: true),
        const FieldSpec('shortBreakMinutes', 'Перерыв · минут', integer: true),
        const FieldSpec(
          'longBreakMinutes',
          'Длинный перерыв · минут',
          integer: true,
        ),
        const FieldSpec(
          'longBreakEvery',
          'Длинный перерыв после помидорок',
          integer: true,
        ),
      ],
      save: (input) async {
        final settings = {
          for (final key in timerDefaults.keys) key: input[key],
        };
        validateSettings(settings);
        repo.setFocusPreferences(input);
        final start = {
          'title': input['title'],
          'workRef': ref,
          'metricId': input['metricId'] == '' ? null : input['metricId'],
          'allocation':
              input['allocation'] == 'assigned' && input['metricId'] == ''
              ? 'unclassified'
              : input['allocation'],
          'workType': input['workType'],
          'mode': input['mode'],
          'settings': settings,
        };
        if (input['strategy'] == 'shared') {
          await repo.sharedAction('start', start);
        } else {
          bool confirmed = false;
          if (repo.cache('timer')['active'] != null) {
            confirmed =
                await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Независимый учёт?'),
                    content: const Text(
                      'На сервере был активный сеанс. При отправке пересечения времени потребуют разбора.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Начать на устройстве'),
                      ),
                    ],
                  ),
                ) ??
                false;
            if (!confirmed) return;
          }
          repo.startLocal(start, independentConfirmed: confirmed);
        }
        startedId = repo.active?['id']?.toString();
      },
    );
    if (startedId != null && repo.active?['id'] == startedId) {
      await revealMobilePlayer();
    }
  }

  Future<void> startUnplannedTimer() => safe(() async {
    await repo.startUnplannedActivity();
    if (repo.active?['workRef'] == null && repo.active != null) {
      await revealMobilePlayer();
    }
  });

  List<Widget> idleTimerButtons() => [
    FilledButton.icon(
      key: const ValueKey('start-unplanned-timer'),
      onPressed: repo.focusStarting || repo.timerBusy
          ? null
          : startUnplannedTimer,
      icon: const Icon(Icons.play_arrow),
      label: const Text('Начать без норматива'),
    ),
    TextButton(
      onPressed: repo.focusStarting || repo.timerBusy
          ? null
          : () => startTimer(),
      child: const Text(
        'Новая активность',
        style: TextStyle(color: Colors.white),
      ),
    ),
  ];

  Future<void> revealMobilePlayer() async {
    if (!mounted) return;
    setState(() => section = 2);
    await changeFocus(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pageScroll.hasClients) pageScroll.jumpTo(0);
    });
  }

  Future<void> showActiveTimerConflict(ActiveTimerConflict conflict) async {
    if (!mounted) return;
    if (dialogOpen) {
      message(conflict.toString());
      return;
    }
    dialogOpen = true;
    bool open = false;
    try {
      open =
          await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Уже есть активный таймер'),
              content: Text(
                '«${conflict.title}»${conflict.paused ? ' — на паузе' : ' — идёт сейчас'}.\n\n'
                'Новая работа не запущена. Заверши и учти текущий сеанс или отмени его, затем запускай другую работу.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Оставить как есть'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Открыть текущий таймер'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      dialogOpen = false;
    }
    if (!open || !mounted) return;
    // Open the player without resuming, finishing, or replacing the session.
    await changeFocus(true);
    if (!mounted) return;
    setState(() => section = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pageScroll.hasClients) pageScroll.jumpTo(0);
    });
  }

  Future<void> changeFocus(bool value) async {
    if (!mounted) return;
    setState(() => focusMode = value);
    if (widget.backgroundEnabled) await background.focusMode(value);
  }

  Future<void> focusSettings() async {
    await editFields(
      context,
      title: 'Настройки таймера',
      initial: {
        ...repo.settings,
        'mode': repo.timerMode,
        'strategy': repo.timerStrategy,
      },
      fields: const [
        FieldSpec(
          'strategy',
          'Учёт',
          options: {
            'shared': 'Общий таймер · сохранение на устройстве',
            'local': 'Таймер устройства · работает без связи',
          },
        ),
        FieldSpec(
          'mode',
          'Режим',
          options: {'pomodoro': 'Помидорка', 'stopwatch': 'Секундомер'},
        ),
        FieldSpec('workMinutes', 'Помидорка · минут', integer: true),
        FieldSpec('shortBreakMinutes', 'Перерыв · минут', integer: true),
        FieldSpec('longBreakMinutes', 'Длинный перерыв · минут', integer: true),
        FieldSpec(
          'longBreakEvery',
          'Длинный перерыв после помидорок',
          integer: true,
        ),
      ],
      save: (input) async => repo.setFocusPreferences(input),
    );
  }

  Future<void> ringtoneSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => TimerRingtoneLibrary(
        repo: repo,
        preview: background.previewRingtone,
        stop: background.stopRingtonePreview,
        changed: () {
          if (mounted) setState(() {});
          if (widget.backgroundEnabled) unawaited(background.update());
        },
        systemSettings: Platform.isAndroid
            ? background.ringtoneSystemSettings
            : null,
      ),
    );
  }

  Future<void> startBreak() async {
    final count = !repo.online
        ? repo.local.get('localPomodoroCount') as int? ?? 0
        : repo.cache('timer')['cycleCount'] as int? ?? 0;
    final long =
        count > 0 && count % (repo.settings['longBreakEvery'] as int) == 0;
    final input = {
      'title': long ? 'Длинный перерыв' : 'Перерыв',
      'phase': long ? 'long_break' : 'short_break',
      'settings': repo.settings,
    };
    if ((repo.durableTimer || repo.online) && repo.localActive == null) {
      await repo.sharedAction('startBreak', input);
    } else {
      repo.startLocal({...input, 'mode': 'pomodoro'});
    }
    await revealMobilePlayer();
  }

  Future<void> cancelTimer() async {
    final id = repo.active?['id'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Отменить сеанс без учёта времени?'),
        content: const Text(
          'Исходный сеанс останется в истории со статусом отмены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Оставить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Отменить сеанс'),
          ),
        ],
      ),
    );
    if (confirmed == true && repo.active?['id'] == id) {
      await safe(() => repo.timerAction('cancel'));
    }
  }

  bool get scrollableFocus =>
      Theme.of(context).platform == TargetPlatform.android;

  Widget focusCard() => ListenableBuilder(
    listenable: focusMode || section != 2 ? repo : clockPulse,
    builder: (context, _) => buildFocusCard(),
  );

  Widget buildFocusCard() {
    final s = repo.active;
    final theme = (repo.local.get('theme') ?? 'green').toString();
    return FocusSurface(
      rotation: object(repo.local.get('focusRotation')),
      theme: theme,
      customImage: repo.local.get('customFocusImage') as String?,
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WeeklyProblemBanner(
                repo: repo,
                edit: () => editWeeklyProblem(weekStart()),
              ),
              DailyProblemBanner(repo: repo, edit: editProblem),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s == null
                          ? 'Пространство для важного'
                          : inLeisure(s)
                          ? 'Leisure · до ${leisureTime(s)}'
                          : pomodoroExpired(s, repo.now)
                          ? 'Помидорка завершена · ожидает учёта'
                          : s['status'] == 'paused'
                          ? 'Пауза · ${pauseClock(s, repo.now)}'
                          : s['phase'] != 'work'
                          ? 'Перерыв'
                          : s['mode'] == 'pomodoro'
                          ? ''
                          : 'Секундомер',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  if (!focusMode)
                    IconButton(
                      onPressed: () => changeFocus(!focusMode),
                      icon: Icon(
                        focusMode
                            ? Icons.dashboard_outlined
                            : Icons.open_in_full,
                        color: Colors.white,
                      ),
                      tooltip: focusMode ? 'Все разделы' : 'Крупный таймер',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (scrollableFocus)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  child: Text(
                    s == null ? '25:00' : clockOf(s, repo.now),
                    style: TextStyle(
                      fontSize: focusMode ? 88 : 68,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                )
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s == null ? '25:00' : clockOf(s, repo.now),
                    style: TextStyle(
                      fontSize: focusMode ? 88 : 68,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (s != null && inLeisure(s))
                LeisureInfo(session: s, now: repo.now),
              if (s == null)
                const Text(
                  'Запусти без норматива или выбери работу в карточке.',
                ),
              const SizedBox(height: 12),
              if (s != null)
                Text(
                  '${(elapsedMs(s, repo.now) / 60000).toStringAsFixed(1)} мин · ${repo.isLocal || repo.durableTimer ? 'сохранение на устройстве' : 'общий сеанс'}',
                  style: const TextStyle(color: Colors.white70),
                ),
              const SizedBox(height: 18),
              TimerCommandNotice(
                repo: repo,
                retry: () => safe(repo.checkPendingTimer),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (s == null) ...[
                    ...idleTimerButtons(),
                    TextButton(
                      onPressed: () => safe(startBreak),
                      child: const Text(
                        'Перерыв',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ] else ...[
                    FilledButton.tonal(
                      onPressed: repo.timerBusy || pomodoroExpired(s, repo.now)
                          ? null
                          : () => safe(
                              () => repo.timerAction(
                                s['status'] == 'paused' ? 'resume' : 'pause',
                              ),
                            ),
                      child: Text(
                        inLeisure(s)
                            ? 'Вернуться к работе'
                            : s['status'] == 'paused'
                            ? 'Продолжить'
                            : 'Пауза',
                      ),
                    ),
                    FilledButton(
                      onPressed: repo.timerBusy ? null : finishTimer,
                      child: const Text('Учесть'),
                    ),
                    if (s['phase'] == 'work')
                      TextButton.icon(
                        onPressed:
                            repo.timerBusy || pomodoroExpired(s, repo.now)
                            ? null
                            : () => safe(() => chooseLeisure(context, repo)),
                        icon: const Icon(
                          Icons.free_breakfast_outlined,
                          color: Colors.white70,
                        ),
                        label: Text(
                          inLeisure(s) ? 'Изменить перерыв' : 'Перерыв',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    TextButton(
                      onPressed: repo.timerBusy ? null : cancelTimer,
                      child: const Text(
                        'Отменить',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    if (s['mode'] == 'pomodoro')
                      TextButton(
                        onPressed: repo.timerBusy
                            ? null
                            : () => safe(() => repo.timerAction('extend')),
                        child: const Text(
                          '＋ 5 мин',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              PomodoroChecklist(
                repo: repo,
                compact: true,
                scrollChecks: !scrollableFocus,
                focus: (ref, title) => startTimer(ref: ref, title: title),
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                key: const ValueKey('timer-settings-button'),
                onPressed: openTimerOptions,
                icon: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white70,
                ),
                label: const Text(
                  'Настройки',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> chooseFocusPainting() async {
    final picked = await FileSelectorWindows().openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Картина',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
    );
    if (picked == null) return;
    if (await picked.length() > 8 * 1024 * 1024) {
      message('Выбери изображение до 8 МБ.');
      return;
    }
    final destination = p.join(
      widget.folder,
      'focus-custom-${uuid.v4()}${p.extension(picked.path)}',
    );
    await picked.saveTo(destination);
    repo.setUiPreferences({
      'customFocusImage': destination,
      'theme': 'custom',
      'focusRotation': {
        ...object(repo.local.get('focusRotation')),
        'enabled': false,
      },
    });
  }

  Future<void> openTimerOptions() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xff243b30),
    builder: (context) => ListenableBuilder(
      listenable: repo,
      builder: (context, _) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: Column(
            children: [
              ListTile(
                title: const Text(
                  'Настройки таймера',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                trailing: IconButton(
                  tooltip: 'Закрыть настройки таймера',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: focusOptions(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget focusOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Тема и звук',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton.icon(
          onPressed: focusSettings,
          icon: const Icon(Icons.tune, color: Colors.white70, size: 18),
          label: const Text(
            'Настройки таймера',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        TextButton.icon(
          onPressed: ringtoneSettings,
          icon: const Icon(
            Icons.music_note_outlined,
            color: Colors.white70,
            size: 18,
          ),
          label: Text(
            'Сигнал таймера · ${timerRingtones[validRingtone(repo.local.get('timerRingtone'))]!.$1}',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        FocusGallerySettings(repo: repo),
        if (Platform.isWindows)
          TextButton.icon(
            onPressed: () => safe(chooseFocusPainting),
            icon: const Icon(Icons.image_outlined),
            label: const Text('Своя картина · выбрать файл'),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: (repo.local.get('sound') ?? 'brown').toString(),
                decoration: const InputDecoration(
                  labelText: 'Фоновый звук',
                  isDense: true,
                ),
                items:
                    const {
                          'white': 'Белый шум',
                          'pink': 'Розовый шум',
                          'brown': 'Коричневый шум',
                          'rain': 'Дождь',
                          'wind': 'Ветер',
                          'lofi': 'Лофи',
                        }.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value, softWrap: true),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  repo.setUiPreference('sound', value);
                  unawaited(background.update());
                },
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: () {
                repo.setUiPreference(
                  'soundEnabled',
                  repo.local.get('soundEnabled') != true,
                );
                setState(() {});
                unawaited(background.update());
              },
              icon: Icon(
                repo.local.get('soundEnabled') == true
                    ? Icons.volume_off_outlined
                    : Icons.volume_up_outlined,
                color: Colors.white,
              ),
            ),
          ],
        ),
        Slider(
          value: (repo.local.get('volume') as num? ?? .2).toDouble(),
          onChanged: (value) {
            repo.setUiPreference('volume', value);
            setState(() {});
            unawaited(background.update());
          },
        ),
        if (Platform.isWindows && focusMode)
          SwitchListTile(
            title: const Text(
              'Поверх других окон',
              style: TextStyle(color: Colors.white),
            ),
            value: repo.local.get('pinFocus') == true,
            onChanged: (value) {
              repo.setUiPreference('pinFocus', value);
              setState(() {});
              windowManager.setAlwaysOnTop(value);
            },
          ),
      ],
    );
  }

  Widget focusPlayer() => ListenableBuilder(
    listenable: clockPulse,
    builder: (context, _) => buildFocusPlayer(),
  );

  Widget buildFocusPlayer() {
    if (scrollableFocus) {
      return SingleChildScrollView(
        key: const PageStorageKey('mobile-focus-scroll'),
        primary: false,
        padding: const EdgeInsets.all(12),
        child: buildFocusCard(),
      );
    }
    final s = repo.active;
    return AdaptiveFocusPlayer(
      paused: s?['status'] == 'paused' && !inLeisure(s),
      pauseClock: s == null ? '' : pauseClock(s, repo.now),
      takeBreak: s == null
          ? () => safe(startBreak)
          : s['phase'] == 'work' && !pomodoroExpired(s, repo.now)
          ? () => safe(() => chooseLeisure(context, repo))
          : null,
      changes: repo,
      weeklyProblem: repo.weeklyProblemText,
      dailyProblem: repo.todayProblemText,
      editWeeklyProblem: () => editWeeklyProblem(weekStart()),
      editDailyProblem: editProblem,
      clock: s == null ? '25:00' : clockOf(s, repo.now),
      mode: s == null
          ? 'Пространство для важного'
          : inLeisure(s)
          ? 'Leisure · до ${leisureTime(s)}'
          : pomodoroExpired(s, repo.now)
          ? 'Помидорка завершена · ожидает учёта'
          : s['status'] == 'paused'
          ? 'Пауза'
          : s['phase'] != 'work'
          ? 'Перерыв'
          : s['mode'] == 'pomodoro'
          ? ''
          : 'Секундомер',
      contextPanel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeeklyProblemBanner(
            repo: repo,
            edit: () => editWeeklyProblem(weekStart()),
          ),
          DailyProblemBanner(repo: repo, edit: editProblem),
        ],
      ),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s == null)
            const Text('Запусти без норматива или выбери работу в карточке.'),
          if (s != null) ...[
            const SizedBox(height: 8),
            Text(
              '${(elapsedMs(s, repo.now) / 60000).toStringAsFixed(1)} мин',
              style: const TextStyle(color: Colors.white70),
            ),
            if (inLeisure(s)) LeisureInfo(session: s, now: repo.now),
          ],
          TimerCommandNotice(
            repo: repo,
            retry: () => safe(repo.checkPendingTimer),
          ),
        ],
      ),
      actions: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          if (s == null)
            ...idleTimerButtons()
          else ...[
            FilledButton.tonal(
              onPressed: repo.timerBusy || pomodoroExpired(s, repo.now)
                  ? null
                  : () => safe(
                      () => repo.timerAction(
                        s['status'] == 'paused' ? 'resume' : 'pause',
                      ),
                    ),
              child: Text(
                inLeisure(s)
                    ? 'К работе'
                    : s['status'] == 'paused'
                    ? 'Продолжить'
                    : 'Пауза',
              ),
            ),
            FilledButton(
              onPressed: repo.timerBusy ? null : finishTimer,
              child: const Text('Учесть'),
            ),
          ],
        ],
      ),
      norms: PomodoroChecklist(
        repo: repo,
        compact: true,
        rowsFirst: true,
        focus: (ref, title) => startTimer(ref: ref, title: title),
      ),
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s == null)
            TextButton(
              onPressed: () => safe(startBreak),
              child: const Text('Начать перерыв'),
            ),
          if (s != null)
            Wrap(
              children: [
                if (s['phase'] == 'work')
                  TextButton(
                    onPressed: repo.timerBusy || pomodoroExpired(s, repo.now)
                        ? null
                        : () => safe(() => chooseLeisure(context, repo)),
                    child: const Text('Leisure'),
                  ),
                if (s['mode'] == 'pomodoro')
                  TextButton(
                    onPressed: repo.timerBusy
                        ? null
                        : () => safe(() => repo.timerAction('extend')),
                    child: const Text('＋ 5 мин'),
                  ),
                TextButton(
                  onPressed: repo.timerBusy ? null : cancelTimer,
                  child: const Text('Отменить сеанс'),
                ),
              ],
            ),
          focusOptions(),
        ],
      ),
    );
  }

  Future<void> safe(Future<void> Function() action) async {
    try {
      await action();
    } on ActiveTimerConflict catch (conflict) {
      await showActiveTimerConflict(conflict);
    } catch (e) {
      message(
        e is StateError
            ? e.message
            : e is ArgumentError
            ? e.message.toString()
            : e.toString(),
      );
    }
  }

  Future<void> editEntity(
    String title,
    String key,
    Json initial,
    List<FieldSpec> fields,
    void Function(Json) save,
  ) async {
    final draft = object(repo.local.get('form:$key'));
    await editFields(
      context,
      title: title,
      initial: draft.isEmpty ? initial : draft,
      fields: fields,
      draft: (input) => repo.local.set('form:$key', input),
      save: (input) async {
        save(input);
        repo.local.remove('form:$key');
      },
    );
  }

  Future<void> editCase([Json? previous]) async {
    if (previous?['pendingProblem'] == true) {
      message(
        'Кейс ещё связывается с проблемой. Дождись синхронизации; текст сохранён локально.',
      );
      return;
    }
    final id = previous?['id'] ?? uuid.v4(), key = 'case:$id';
    final original = repo.cache('workspace');
    final base = rows(original['cases'])
        .where((c) => c['id'] == id)
        .firstOrNull;
    await editEntity(
      'Кейс',
      key,
      {
        ...previous ?? {},
        'id': id,
        'title': previous?['title'] ?? '',
        'status': previous?['status'] ?? 'active',
      },
      [
        const FieldSpec('title', 'Название'),
        const FieldSpec('context', 'Ситуация и размышления', lines: 8),
        const FieldSpec(
          'status',
          'Состояние',
          options: {
            'new': 'Новый',
            'active': 'Активный',
            'watching': 'Наблюдаю',
            'closed': 'Закрыт',
          },
        ),
        const FieldSpec('nextStep', 'Следующий ход', lines: 3),
        const FieldSpec(
          'nextReview',
          'Дата возврата · YYYY-MM-DD',
          nullable: true,
        ),
        const FieldSpec(
          'resolution',
          'Результат / основание закрытия',
          lines: 3,
        ),
        FieldSpec(
          'projectId',
          'Проект',
          options: {
            '': 'Без проекта',
            for (final p in repo.entities('projects', 'project'))
              p['id'].toString(): p['name'].toString(),
          },
        ),
      ],
      (input) {
        repo.nativeSave(
          'workspace',
          'saveCase',
          {
            ...input,
            if (base == null) 'clientId': id,
            if (base == null) 'id': null,
          },
          key,
          expectedUpdatedAt: base?['updatedAt'],
        );
      },
    );
  }

  Future<void> editWork([
    Json? previous,
    Json? origin,
    String? initialStage,
  ]) async {
    final id = previous?['id'] ?? uuid.v4(), key = 'work:$id';
    final base = rows(repo.cache('workspace')['workItems'])
        .where((w) => w['id'] == id)
        .firstOrNull;
    await editEntity(
      'Карточка работы',
      key,
      {
        ...previous ?? {},
        'id': id,
        'title': previous?['title'] ?? '',
        'kind': previous?['kind'] ?? 'work',
        'stage': previous?['stage'] ?? initialStage ?? 'planned',
        'allocation': previous?['allocation'] ?? 'unclassified',
        'metricId': previous?['metricId'] ?? '',
      },
      [
        const FieldSpec('title', 'Название'),
        const FieldSpec(
          'kind',
          'Тип',
          options: {'work': 'Работа', 'issue': 'Issue'},
        ),
        const FieldSpec('description', 'Описание и размышления', lines: 8),
        FieldSpec('stage', 'Стадия', options: stages),
        const FieldSpec('nextStep', 'Следующий шаг', lines: 3),
        const FieldSpec('result', 'Результат / основание стадии', lines: 3),
        const FieldSpec(
          'reviewDate',
          'Дата возврата · YYYY-MM-DD',
          nullable: true,
        ),
        FieldSpec(
          'projectId',
          'Проект',
          options: {
            '': 'Без проекта',
            for (final p in repo.entities('projects', 'project'))
              p['id'].toString(): p['name'].toString(),
          },
        ),
        FieldSpec(
          'metricId',
          'Часовой норматив',
          options: {
            '': 'Без норматива',
            for (final m in rows(
              repo.cache('dashboard')['metrics'],
            ).where((m) => m['unit'] == 'hours'))
              m['id'].toString(): m['title'].toString(),
          },
        ),
        const FieldSpec(
          'allocation',
          'Назначение времени',
          options: {
            'unclassified': 'Требует разбора',
            'outside': 'Вне нормативов',
            'assigned': 'По нормативу',
          },
        ),
        FieldSpec(
          'workType',
          'Типы времени',
          timeTypes: true,
          options: timeTypeOptions(
            repo.local.draft(key)?['workType'] ??
                previous?['workType'] ??
                base?['workType'],
          ),
        ),
      ],
      (input) {
        repo.nativeSave('workspace', 'saveWorkItem', {
          ...input,
          'id': id,
          'create': base == null,
          'expectedRevision': base?['revision'] ?? 0,
          'requestId': uuid.v4(),
          'metricId': input['metricId'] == '' ? null : input['metricId'],
          'allocation':
              input['metricId'] == '' && input['allocation'] == 'assigned'
              ? 'unclassified'
              : input['allocation'],
          'origin': ?origin,
        }, key);
      },
    );
  }

  Widget characteristics(String ref) {
    final link = rows(repo.cache('workspace')['links'])
        .where((l) => l['ownerRef'] == ref)
        .firstOrNull;
    final system = repo
        .entities('systems', 'system')
        .where((s) => s['id'] == link?['systemId'])
        .firstOrNull;
    if (system == null) {
      return const Text(
        'Характеристики · No Data',
        style: TextStyle(fontSize: 11, color: Color(0xff727780)),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: rows(system['characteristics'])
          .map(
            (c) => Chip(
              label: Text(
                '${c['kind'] == 'limit' ? '≤ ' : ''}${c['name']} · ${c['current'] ?? 'No Data'} → ${c['target'] ?? 'No Data'}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> linkSystem(String ref) async {
    final old =
        rows(repo.cache('workspace')['links'])
            .where((l) => l['ownerRef'] == ref)
            .firstOrNull ??
        <String, dynamic>{};
    await editFields(
      context,
      title: 'Характеристики системы',
      initial: {'systemId': old['systemId'] ?? ''},
      fields: [
        FieldSpec(
          'systemId',
          'Связать с системой',
          options: {
            '': 'Снять связь',
            for (final s in repo.entities('systems', 'system'))
              s['id'].toString(): s['name'].toString(),
          },
        ),
      ],
      save: (input) async {
        repo.nativeSave(
          'workspace',
          'saveLink',
          {
            'ownerRef': ref,
            'systemId': input['systemId'],
            'notes': old['systemId'] == input['systemId']
                ? old['notes'] ?? {}
                : {},
          },
          'link:$ref',
          expectedUpdatedAt: old['updatedAt'],
        );
      },
    );
  }

  Widget workCard(Json item, String ref) {
    final isCase = ref.startsWith('case:'), isTask = ref.startsWith('task:');
    final title = item['title'].toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              isCase
                  ? 'Кейс · ${caseStatusText(item)}'
                  : isTask
                  ? 'Задача проекта · ${item['done'] == true ? 'Сделано' : 'Открыта'}'
                  : '${item['kind'] == 'issue' ? 'Issue' : 'Работа'} · ${stages[item['stage']] ?? item['stage']}',
              style: const TextStyle(fontSize: 12, color: Color(0xff727780)),
            ),
            if (repo.local.draft(ref) != null)
              const Text(
                'Сохранено локально · ожидает отправки',
                style: TextStyle(fontSize: 11, color: Color(0xff8c6e3c)),
              ),
            if ((item['nextStep'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(item['nextStep'].toString()),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      startTimer(title: title, ref: ref, item: item),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Фокус'),
                ),
                TextButton(
                  onPressed: () => isCase
                      ? editCase(item)
                      : isTask
                      ? editTaskNotes(item)
                      : editWork(item),
                  child: const Text('Открыть'),
                ),
                TextButton(
                  onPressed: () => setDailyNorm(ref, title),
                  child: const Text('Дневная норма'),
                ),
                IconButton(
                  onPressed: () => linkSystem(ref),
                  icon: const Icon(Icons.link, size: 18),
                  tooltip: 'Характеристики',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> editTaskNotes(Json task) async {
    final ref = 'task:${task['id']}';
    final previous =
        rows(repo.cache('workspace')['workNotes'])
            .where((n) => n['workRef'] == ref)
            .firstOrNull ??
        <String, dynamic>{};
    await editFields(
      context,
      title: task['title'].toString(),
      initial: {
        'text':
            repo.local.draft('note:$ref')?['text'] ?? previous['text'] ?? '',
      },
      fields: const [FieldSpec('text', 'Размышления', lines: 10)],
      save: (input) async {
        repo.nativeSave('workspace', 'saveWorkNote', {
          'workRef': ref,
          'text': input['text'],
          'expectedRevision': previous['revision'] ?? 0,
          'requestId': uuid.v4(),
        }, 'note:$ref');
      },
    );
  }

  Widget workPage() {
    final cases = repo.entities('cases', 'case'),
        works = repo.entities('workItems', 'work'),
        tasks = repo.entities('tasks', 'task');
    final all = [
      ...works.map(
        (w) => {'item': w, 'ref': 'work:${w['id']}', 'stage': w['stage']},
      ),
      ...cases.map(
        (c) => {'item': c, 'ref': 'case:${c['id']}', 'stage': caseStage(c)},
      ),
      ...tasks.map(
        (t) => {
          'item': t,
          'ref': 'task:${t['id']}',
          'stage': t['done'] == true ? 'ready' : 'planned',
        },
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        weeklyProblemCard(),
        problemCard(),
        sectionTitle(
          'Работы и кейсы',
          trailing: Wrap(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.view_kanban_outlined),
                    label: Text('Доска'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.view_list_outlined),
                    label: Text('Список'),
                  ),
                ],
                selected: {board},
                onSelectionChanged: (value) {
                  repo.setUiPreference(
                    'workView',
                    value.first ? 'board' : 'list',
                  );
                  setState(() => board = value.first);
                },
              ),
              TextButton(
                onPressed: () => editWork(),
                child: const Text('＋ Работа'),
              ),
              TextButton(
                onPressed: () => editCase(),
                child: const Text('＋ Кейс'),
              ),
            ],
          ),
        ),
        if (all.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No Data · создай работу или запиши проблему дня.'),
          )
        else if (board)
          WorkStageBoard(
            repo: repo,
            entries: all,
            card: workCard,
            create: (stage) => editWork(null, null, stage),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final stage in stages.entries)
                if (all.any((e) => e['stage'] == stage.key)) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '${stage.value} · ${all.where((e) => e['stage'] == stage.key).length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final entry in all.where((e) => e['stage'] == stage.key))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: workCard(
                        object(entry['item']),
                        entry['ref'].toString(),
                      ),
                    ),
                ],
            ],
          ),
        const SizedBox(height: 24),
        focusCard(),
        const SizedBox(height: 18),
        WorkAnalytics(repo: repo),
      ],
    );
  }

  Widget problemCard() {
    final problem = repo.todayProblem;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Главная проблема · ${today()}',
              style: const TextStyle(fontSize: 12, color: Color(0xff727780)),
            ),
            const SizedBox(height: 10),
            Text(
              repo.todayProblemText,
              style: const TextStyle(fontSize: 19, height: 1.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              children: [
                TextButton(
                  onPressed: editProblem,
                  child: const Text('Записать / уточнить'),
                ),
                if (problem['caseRef'] != null)
                  TextButton(
                    onPressed: () => startTimer(
                      title: problem['text'].toString().length > 300
                          ? problem['text'].toString().substring(0, 300)
                          : problem['text'].toString(),
                      ref: problem['caseRef'].toString(),
                    ),
                    child: const Text('▶ Фокус по проблеме'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget weeklyProblemCard() =>
      WeeklyProblemCard(repo: repo, edit: editWeeklyProblem);

  Future<void> editWeeklyProblem(String week) async {
    final key = 'weeklyProblemComposer:$week';
    final draft = object(repo.local.get(key));
    await editFields(
      context,
      title: 'Главная проблема недели · ${weekRange(week)}',
      initial: draft.isEmpty
          ? {'text': repo.weeklyProblem(week)['text'] ?? ''}
          : draft,
      fields: const [
        FieldSpec(
          'text',
          'The biggest problem of the week is…',
          lines: 6,
          labelAbove: true,
        ),
      ],
      draft: (input) => repo.local.set(key, input),
      save: (input) async {
        repo.saveWeeklyProblem(week, input['text'].toString());
        repo.local.remove(key);
      },
    );
  }

  Future<void> editProblem() async {
    final day = today();
    await editFields(
      context,
      title: 'What is the biggest problem today?',
      initial: {'text': repo.todayProblem['text'] ?? ''},
      fields: const [
        FieldSpec('text', 'Разрыв между желаемым и текущим', lines: 5),
      ],
      draft: (input) => repo.local.set('problemComposer:$day', input),
      save: (input) async {
        repo.saveProblem(day, input['text'].toString());
      },
    );
  }

  Future<void> editGoal([Json? previous, String? parentId]) async {
    final id = previous?['id'] ?? uuid.v4(), key = 'goal:$id';
    final base = rows(repo.cache('workspace')['goals'])
        .where((g) => g['id'] == id)
        .firstOrNull;
    await editEntity(
      'Цель и шкала',
      key,
      {
        ...previous ?? {},
        'id': id,
        'status': previous?['status'] ?? 'active',
        'direction': previous?['direction'] ?? 'up',
        'parentId': previous?['parentId'] ?? parentId ?? '',
      },
      [
        const FieldSpec('title', 'Цель'),
        FieldSpec(
          'parentId',
          'Родительская цель',
          options: {
            '': 'Верхний уровень',
            for (final g
                in repo.entities('goals', 'goal').where((g) => g['id'] != id))
              g['id'].toString(): g['title'].toString(),
          },
        ),
        FieldSpec('unit', 'Единица и период · например UZS / месяц'),
        FieldSpec(
          'target',
          'Предпочтительная мною шкала',
          numeric: true,
          labelAbove: true,
        ),
        FieldSpec(
          'direction',
          'Направление',
          options: {'up': 'Увеличить', 'down': 'Уменьшить'},
        ),
        FieldSpec(
          'dueDate',
          'Дедлайн цели · ГГГГ-ММ-ДД',
          nullable: true,
          hint: goalDeadlineHint,
        ),
        FieldSpec('status', 'Статус цели', options: goalStatusOptions),
      ],
      (input) => repo.nativeSave(
        'workspace',
        'saveGoal',
        {
          ...input,
          if (base == null) 'id': null,
          if (base == null) 'clientId': id,
        },
        key,
        expectedUpdatedAt: base?['updatedAt'],
      ),
    );
  }

  Future<void> measureGoal(Json goal) async {
    if ((goal['unit'] ?? '').toString().trim().isEmpty) {
      message(
        'Сначала укажи единицу шкалы. Для денег — валюту и период, например UZS / месяц.',
      );
      await editGoal(goal);
      return;
    }
    await editFields(
      context,
      title: 'Замер · ${goal['title']}',
      initial: {'value': goal['current']},
      fields: const [
        FieldSpec(
          'value',
          'Шкала/характеристика сейчас',
          numeric: true,
          labelAbove: true,
        ),
        FieldSpec('evidence', 'Что подтверждает замер', lines: 3),
      ],
      save: (input) async {
        if (input['value'] is! num || !(input['value'] as num).isFinite) {
          throw ArgumentError(
            'Укажи числовое значение замера. Ноль можно записать явно.',
          );
        }
        repo.recordGoalMeasurement(
          goal,
          input['value'] as num,
          evidence: (input['evidence'] ?? '').toString(),
        );
      },
    );
  }

  Widget indicatorsPage() {
    final allGoals = projectedGoals(repo);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle(
          'Цели',
          trailing: TextButton(
            onPressed: () => editGoal(),
            child: const Text('＋ Цель'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Укажи единицу, запиши характеристику сейчас и предпочтительную шкалу. Дата замера ставится при сохранении. Предыдущие значения доступны в истории; первый замер задаёт начало сравнения.',
          ),
        ),
        const ExpansionTile(
          title: Text('Как вводить и читать показатели'),
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Руководства: часы чтения и применения — отдельные нормы. В замере можно записывать, какую идею применяешь, что меняется в проекте, карьере или результате и чем это подтверждается.\n\n'
                'Выручка — платежи клиентов. Прибыль бизнеса — выручка минус расходы. Личный доход — полученное себе. Для каждого денежного показателя укажи валюту и период; в месячном замере записывай итог выбранного месяца.\n\n'
                'Сон: записывай часы за ночь на дату пробуждения. Минимум указан в карточке нормы.\n\n'
                'Изменение показывает разницу с началом и с прошлым замером. Полоса и процент показывают движение от исходного значения к предпочтительному. Без определённой шкалы процент не вычисляется. Все замеры и их даты сохраняются в истории.',
              ),
            ),
          ],
        ),
        GoalsTable(
          repo: repo,
          goals: allGoals,
          edit: (g) => editGoal(g),
          measure: measureGoal,
          child: (g) => editGoal(null, g['id'].toString()),
          history: (g) => showGoalHistory(context, g),
        ),
        sectionTitle('Нормативы'),
        const Text(
          'На неделю',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: rows(repo.cache('dashboard')['metrics'])
              .map(
                (m) => SizedBox(
                  width: 260,
                  child: metricCard(
                    m['title'].toString(),
                    m['recordCount'] == 0 ? null : m['actual'],
                    m['target'],
                    m['recordCount'] == 0 ? null : m['percent'],
                    unit: m['unit'] == 'hours' ? 'ч' : 'альф',
                    onTap: () => editFields(
                      context,
                      title: 'Недельный норматив',
                      initial: {'target': m['target']},
                      fields: const [
                        FieldSpec(
                          'target',
                          'Норма · пусто для снятия',
                          numeric: true,
                        ),
                      ],
                      save: (input) async {
                        repo.nativeSave(
                          'target',
                          'save',
                          {
                            'metricId': m['id'],
                            'week': repo.cache('dashboard')['week'],
                            'target': input['target'],
                          },
                          'target:${repo.cache('dashboard')['week']}:${m['id']}',
                          expectedTarget: m['target'],
                        );
                      },
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        sectionTitle(
          'На день',
          trailing: TextButton(
            onPressed: () => showNorms(List<Json>.from(repo.dailyNorms)),
            child: const Text('Открыть список'),
          ),
        ),
        PomodoroChecklist(
          repo: repo,
          focus: (ref, title) => startTimer(ref: ref, title: title),
        ),
        const SizedBox(height: 12),
        ...repo.dailyNorms.map(
          (n) => ListTile(
            title: Text(n['title'].toString()),
            subtitle: Text(
              '${n['actualMinutes'] == null ? 'No Data' : (n['actualMinutes'] as num).toStringAsFixed(1)} / ${n['minutes']} мин · с ${n['time']}, каждый час',
            ),
            trailing: IconButton(
              onPressed: () =>
                  setDailyNorm(n['workRef'].toString(), n['title'].toString()),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        ),
      ],
    );
  }

  Widget systemsPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      sectionTitle(
        'Системы · три приоритета и ограничитель',
        trailing: TextButton(
          onPressed: () => editSystem(),
          child: const Text('＋ Система'),
        ),
      ),
      ...repo
          .entities('systems', 'system')
          .map(
            (s) => Card(
              child: ListTile(
                title: Text(s['name'].toString()),
                subtitle: Text(
                  rows(s['characteristics'])
                      .map(
                        (c) =>
                            '${c['kind'] == 'limit' ? '≤ ' : ''}${c['name']} · ${c['current'] ?? 'No Data'} → ${c['target'] ?? 'No Data'}',
                      )
                      .join('\n'),
                ),
                onTap: () => editSystem(s),
              ),
            ),
          ),
    ],
  );

  Future<void> editSystem([Json? previous]) async {
    final id = previous?['id'] ?? uuid.v4(), key = 'system:$id';
    final base = rows(repo.cache('workspace')['systems'])
        .where((s) => s['id'] == id)
        .firstOrNull;
    final chars = rows(previous?['characteristics']);
    final input = {
      ...previous ?? {},
      'id': id,
      for (var i = 0; i < 4; i++) ...{
        'name$i': i < chars.length ? chars[i]['name'] : '',
        'unit$i': i < chars.length ? chars[i]['unit'] : '',
        'baseline$i': i < chars.length ? chars[i]['baseline'] : null,
        'target$i': i < chars.length ? chars[i]['target'] : null,
        'direction$i': i < chars.length ? chars[i]['direction'] : 'up',
      },
    };
    await editEntity(
      'Система и характеристики',
      key,
      input,
      [
        const FieldSpec('name', 'Система'),
        const FieldSpec('description', 'Описание', lines: 3),
        for (var i = 0; i < 4; i++) ...[
          FieldSpec('name$i', i < 3 ? 'Приоритет ${i + 1}' : 'Ограничитель'),
          FieldSpec('unit$i', 'Единица шкалы'),
          FieldSpec('baseline$i', 'Начальное значение', numeric: true),
          FieldSpec('target$i', i < 3 ? 'Цель' : 'Не выше', numeric: true),
          if (i < 3)
            FieldSpec(
              'direction$i',
              'Направление',
              options: const {'up': 'Увеличить', 'down': 'Уменьшить'},
            ),
        ],
      ],
      (value) {
        repo.nativeSave(
          'workspace',
          'saveSystem',
          {
            'id': base == null ? null : id,
            if (base == null) 'clientId': id,
            'name': value['name'],
            'description': value['description'],
            'characteristics': [
              for (var i = 0; i < 4; i++)
                {
                  'id': i < chars.length ? chars[i]['id'] : null,
                  'name': value['name$i'],
                  'unit': value['unit$i'],
                  'baseline': value['baseline$i'],
                  'target': value['target$i'],
                  'direction': i == 3 ? 'down' : value['direction$i'],
                },
              ...chars.skip(4),
            ],
          },
          key,
          expectedUpdatedAt: base?['updatedAt'],
        );
      },
    );
  }

  Future<void> editProject([Json? previous]) async {
    final id = previous?['id'] ?? uuid.v4(), key = 'project:$id';
    final base =
        rows(repo.cache('portfolio')['projects'])
            .where((p) => p['id'] == id)
            .firstOrNull ??
        (previous?['pendingCopy'] == true ? previous : null);
    await editEntity(
      'Проект',
      key,
      {
        ...previous ?? {},
        'id': id,
        'status': previous?['status'] ?? 'active',
        'phase': previous?['phase'] ?? 'pre_operation',
        'parentId': previous?['parentId'] ?? '',
        'zones': rows(previous?['zones']).isEmpty
            ? rows(repo.cache('portfolio')['defaultZones'])
            : rows(previous?['zones']),
        'zoneIds': rows(previous?['zones']).isEmpty
            ? ['customers', 'economics', 'operators']
            : rows(previous?['zones']).map((z) => z['id']).toList(),
      },
      [
        const FieldSpec('name', 'Название'),
        FieldSpec(
          'parentId',
          'Родительский проект',
          options: {
            '': 'Верхний уровень',
            for (final p
                in repo
                    .entities('projects', 'project')
                    .where((p) => p['id'] != id))
              p['id'].toString(): p['name'].toString(),
          },
        ),
        FieldSpec(
          'status',
          'Состояние',
          options: {
            'active': 'Активный',
            'paused': 'Приостановлен',
            'closed': 'Закрыт',
          },
        ),
        FieldSpec(
          'phase',
          'Этап',
          options: {
            'pre_operation': 'До эксплуатации',
            'operation': 'В эксплуатации',
          },
        ),
      ],
      (input) => repo.nativeSave(
        'portfolio',
        base == null ? 'createProject' : 'updateProject',
        {
          ...input,
          if (base == null) 'clientId': id,
          if (base != null) 'expectedRevision': base['revision'] ?? 0,
        },
        key,
        expectedUpdatedAt: base?['updatedAt'],
      ),
    );
  }

  Future<void> editAlpha(
    Json project, {
    Json? previous,
    Json? zone,
    Json? parent,
  }) async {
    final id = previous?['id'] ?? uuid.v4(), key = 'alpha:$id';
    final base =
        rows(repo.cache('portfolio')['alphas'])
            .where((a) => a['id'] == id)
            .firstOrNull ??
        (previous?['pendingCopy'] == true ? previous : null);
    final alphas = repo
        .entities('alphas', 'alpha')
        .where((a) => a['projectId'] == project['id'] && a['id'] != id);
    await editEntity(
      'Моделер альф',
      key,
      {
        ...previous ?? {},
        'id': id,
        'projectId': project['id'],
        'state': previous?['state'] ?? 'empty',
        'zoneId':
            previous?['zoneId'] ??
            zone?['id'] ??
            parent?['zoneId'] ??
            rows(project['zones']).firstOrNull?['id'],
        'parentId': previous?['parentId'] ?? parent?['id'] ?? '',
        'typeName': previous?['typeName'] ?? zone?['typeName'] ?? '',
      },
      [
        FieldSpec(
          'zoneId',
          'Зона',
          options: {
            for (final z in rows(project['zones']))
              z['id'].toString(): z['title'].toString(),
          },
        ),
        FieldSpec(
          'parentId',
          'Подальфа',
          options: {
            '': 'Корневой слот',
            for (final a in alphas)
              a['id'].toString(): (a['uniqueName'] ?? a['typeName']).toString(),
          },
        ),
        const FieldSpec('typeName', 'Типовое имя'),
        const FieldSpec('uniqueName', 'Проектное имя'),
        const FieldSpec(
          'state',
          'Состояние',
          options: {
            'empty': 'Пустой слот',
            'described': 'Описано',
            'working': 'В работе',
            'verified': 'Подтверждено',
            'ready': 'Готово к эксплуатации',
            'not_applicable': 'Не применяется',
          },
        ),
        const FieldSpec('stateLabel', 'Состояние по шаблону'),
        const FieldSpec('description', 'Описание и заметки', lines: 6),
        const FieldSpec(
          'modelUrl',
          'Ссылка на модель · HTTP / HTTPS',
          hint: 'Можно добавить ссылку на другую модель, схему или документ. Открывается отдельной кнопкой.',
        ),
        const FieldSpec('criteria', 'Критерий состояния', lines: 3),
        const FieldSpec('evidence', 'Свидетельства', lines: 4),
        const FieldSpec('nextStep', 'Следующий шаг', lines: 3),
        const FieldSpec(
          'filledDate',
          'Дата заполнения · YYYY-MM-DD',
          nullable: true,
        ),
        const FieldSpec(
          'reviewDate',
          'Дата возврата · YYYY-MM-DD',
          nullable: true,
        ),
        const FieldSpec('area', 'Интересующий предмет'),
        const FieldSpec('whyImportant', 'Почему важно / чей интерес', lines: 3),
        const FieldSpec('adaptedAlpha', 'Адаптированная альфа'),
        const FieldSpec('source', 'Источник / MetaU'),
        const FieldSpec('metaAdaptation', 'Адаптация MetaS → L0', lines: 3),
        const FieldSpec('systemTime', 'Время системы'),
        const FieldSpec('attention', 'Внимание'),
      ],
      (input) {
        final url = (input['modelUrl'] ?? '').toString();
        if (url.isNotEmpty && modelLinkUri(url) == null) {
          throw ArgumentError(
            'Укажи HTTP / HTTPS URL модели без логина и пароля.',
          );
        }
        repo.nativeSave(
          'portfolio',
          base == null ? 'createAlpha' : 'updateAlpha',
          {
            ...input,
            if (base == null) 'clientId': id,
            'expectedRevision': base?['revision'] ?? 0,
          },
          key,
          expectedUpdatedAt: base?['updatedAt'],
        );
      },
    );
  }

  Widget projectsPage() => ModelingWorkspace(
    repo: repo,
    createProject: () => editProject(),
    editProject: (project) => editProject(project),
    editAlpha: (project, alpha) => editAlpha(project, previous: alpha),
    createInZone: (project, zone) => editAlpha(project, zone: zone),
    createChild: (project, alpha) => editAlpha(project, parent: alpha),
    focusAlpha: (alpha) => startTimer(
      title: (alpha['uniqueName'] ?? '').toString().trim().isEmpty
          ? alpha['typeName'].toString()
          : alpha['uniqueName'].toString(),
      ref: 'alpha:${alpha['id']}',
    ),
    linkSystem: (project) => linkSystem('project:${project['id']}'),
    characteristics: (project) => characteristics('project:${project['id']}'),
    systemsPanel: systemsPanel(),
  );
  Widget dataPage() {
    final datasets = {
      'Нормативы': repo.cache('dashboard')['metrics'],
      'Записи времени': repo.cache('entries')['entries'],
      'Проекты': repo.entities('projects', 'project'),
      'Альфы': repo.entities('alphas', 'alpha'),
      'Кейсы': repo.entities('cases', 'case'),
      'Карточки работы': repo.entities('workItems', 'work'),
      'Сеансы таймера': repo.cache('timer')['sessions'],
      'Отклонённые команды таймера': object(
        repo.local.get('timerCommandHistory'),
      ).values.toList(),
      'Сеансы устройства': repo.local.get('localHistory'),
      'Локальная история таймера': repo.local.get('sharedLocalHistory'),
      'Подтверждённые действия таймера': object(
        repo.local.get('timerCommandReceipts'),
      ).values.toList(),
      'Нормы дня': repo.dailyNorms,
      'План помидорок по датам': repo.pomodoroRows,
      'Факты помидорок': repo.pomodoroFacts,
      'Отметки дня': repo.dailyChecks,
      'Цели': repo.entities('goals', 'goal'),
      'Финансовые операции': repo.cache('finance')['transactions'],
      'Импорт Coda': object(repo.cache('imports')['snapshot'])['work'],
      'Исходные issues': object(repo.cache('imports')['snapshot'])['issues'],
      'Исходные цели Coda': object(repo.cache('imports')['snapshot'])['goals'],
      'Пакет шаблонов Coda': object(repo.cache('imports')['reference'])['rows'],
      'История разбора конфликтов': repo.local.get('conflictHistory'),
      'Фоновая служба приложения': [object(repo.local.get('backgroundRuntime'))]
          .where((r) => r.isNotEmpty)
          .toList(),
      'Публикации': repo.cache('writing')['entries'],
      'Источники': repo.cache('references')['entries'],
      'Проблемы недели': repo.weeklyProblems,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle(
          'Данные устройства и сервера',
          trailing: TextButton(
            onPressed: () => safe(() async {
              final file = await repo.exportLocal(widget.folder);
              await background.shareExport(file);
              message('Выгрузка: $file');
            }),
            child: const Text('Выгрузить локальную копию'),
          ),
        ),
        SyncPanel(repo: repo),
        SelectableText(
          'SQLite: ${p.join(widget.folder, 'indicators-work.sqlite')}\nУстройство: ${repo.deviceId}\nСервер: ${repo.serverId ?? 'No Data'}',
        ),
        sectionTitle('Очередь отправки · ${repo.pending.length}'),
        ...repo.pending.map(
          (item) => Card(
            child: ListTile(
              title: Text(item['entity'].toString()),
              subtitle: Text(
                '${item['state']} · ${item['error'] ?? 'Ожидает квитанцию'}',
              ),
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Исходная запись очереди'),
                  content: SingleChildScrollView(
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(item),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Закрыть'),
                    ),
                    if (item['state'] == 'conflict')
                      TextButton(
                        onPressed: () => safe(() async {
                          await repo.resolveConflict(item, apply: false);
                          if (c.mounted) Navigator.pop(c);
                        }),
                        child: const Text(
                          'Сохранить исходник локально и пропустить',
                        ),
                      ),
                    if (item['state'] == 'conflict' &&
                        ![
                          '/api/offline/import',
                          '/api/timer',
                        ].contains(item['route']))
                      TextButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: c,
                            builder: (dialog) => AlertDialog(
                              title: const Text(
                                'Применить мою правку к текущей версии?',
                              ),
                              content: const Text(
                                'Твоя исходная команда останется в истории конфликтов. Новая команда применит поля из показанного исходника поверх текущих данных сервера; открой карточку и сравни её перед подтверждением.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, false),
                                  child: const Text('Отмена'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, true),
                                  child: const Text('Применить мою правку'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await safe(() async {
                              await repo.resolveConflict(item, apply: true);
                              if (c.mounted) Navigator.pop(c);
                            });
                          }
                        },
                        child: const Text('Разрешить конфликт явно'),
                      ),
                    if (item['state'] == 'conflict')
                      TextButton(
                        onPressed: () {
                          repo.local.retry(item['id'].toString());
                          Navigator.pop(c);
                          unawaited(repo.synchronize());
                        },
                        child: const Text('Повторить исходную команду'),
                      ),
                    if (item['route'] == '/api/offline/import' &&
                        item['state'] == 'conflict')
                      TextButton(
                        onPressed: () {
                          repo.local.exclude(item['id'].toString());
                          Navigator.pop(c);
                          unawaited(repo.synchronize());
                        },
                        child: const Text(
                          'Исключить из учёта · сохранить исходник',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (repo.local.get('pendingTimer') != null)
          Card(
            child: ListTile(
              title: const Text('Действие общего таймера ждёт подтверждения'),
              subtitle: Text(
                (repo.local.get('timerConflict') ??
                        'Ответ мог потеряться. Повтор использует тот же UUID.')
                    .toString(),
              ),
              trailing: TextButton(
                onPressed: () => safe(repo.checkPendingTimer),
                child: const Text('Проверить действие'),
              ),
            ),
          ),
        for (final dataset in datasets.entries)
          ExpansionTile(
            title: Text('${dataset.key} · ${rows(dataset.value).length}'),
            children: [
              InspectableTable(title: dataset.key, data: rows(dataset.value)),
            ],
          ),
      ],
    );
  }

  Future<void> settings() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Настройки'),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: Listenable.merge([repo, overlayAllowed]),
              builder: (c, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppearanceSettings(repo: repo),
                  const Divider(height: 32),
                  ListTile(
                    leading: const Icon(Icons.music_note_outlined),
                    title: const Text('Библиотека рингтонов'),
                    subtitle: const Text('Выбрать и прослушать сигнал таймера'),
                    onTap: ringtoneSettings,
                  ),
                  if (Platform.isAndroid) ...[
                    SwitchListTile(
                      title: const Text('Малое окно таймера'),
                      subtitle: Text(
                        overlayAllowed.value
                            ? 'При активном таймере показывать поверх других приложений'
                            : 'Для показа нужно разрешение Android «Поверх других приложений»',
                      ),
                      value: repo.local.get('androidOverlayEnabled') != false,
                      onChanged: (value) async {
                        repo.setAndroidOverlayEnabled(value);
                        if (value && !overlayAllowed.value) {
                          await background.requestOverlayPermission();
                        }
                      },
                    ),
                    if (!overlayAllowed.value &&
                        repo.local.get('androidOverlayEnabled') != false)
                      TextButton.icon(
                        onPressed: background.requestOverlayPermission,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Разрешить показ поверх приложений'),
                      ),
                  ],
                  if (Platform.isWindows)
                    SwitchListTile(
                      title: const Text('Таймер при сворачивании'),
                      subtitle: const Text(
                        'Показывать активный сеанс небольшим окном поверх остальных окон',
                      ),
                      value: repo.local.get('timerOnMinimize') != false,
                      onChanged: repo.setTimerOnMinimize,
                    ),
                  PomodoroChecklist(
                    repo: repo,
                    focus: (ref, title) async {
                      Navigator.pop(c);
                      await startTimer(ref: ref, title: title);
                    },
                  ),
                  const SizedBox(height: 12),
                  PomodoroWeek(repo: repo),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: connectionSettings,
            child: const Text('Сервер и разрешения'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> connectionSettings() async {
    await editFields(
      context,
      title: 'Подключение и фон',
      initial: {'url': repo.base, 'accessKey': ''},
      fields: const [
        FieldSpec('url', 'Адрес сервера · HTTPS / localhost'),
        FieldSpec(
          'accessKey',
          'Ключ доступа · пусто, чтобы сохранить прежний',
          obscure: true,
        ),
      ],
      save: (input) async {
        repo.setBase(input['url'].toString());
        repo.setServerAccessKey(input['accessKey'].toString());
        await repo.synchronize();
      },
    );
    if (Platform.isAndroid) await background.requestPermissions();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !Platform.isAndroid,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop &&
          Platform.isAndroid &&
          await showPlanningQuestion(force: true)) {
        await SystemNavigator.pop();
      }
    },
    child: FocusBackdrop(
      rotation: object(repo.local.get('focusRotation')),
      theme: (repo.local.get('theme') ?? 'green').toString(),
      enabled: focusMode || background.desktop?.compact == true,
      customImage: repo.local.get('customFocusImage') as String?,
      child: Scaffold(
        backgroundColor: focusMode || background.desktop?.compact == true
            ? Colors.transparent
            : null,
        appBar: DashboardWindowHeader(
          enabled: Platform.isWindows && widget.backgroundEnabled,
          themed: focusMode || background.desktop?.compact == true,
          toolbar: AppBar(
            toolbarHeight: MediaQuery.sizeOf(context).width < 600
                ? (MediaQuery.textScalerOf(context).scale(18) > 24 ? 88 : 64)
                : 72,
            flexibleSpace: Platform.isWindows
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: () => background.desktop?.toggleMaximized(),
                    child: const SizedBox.expand(),
                  )
                : null,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: focusMode || background.desktop?.compact == true
                ? Colors.transparent
                : null,
            foregroundColor: focusMode || background.desktop?.compact == true
                ? Colors.white
                : null,
            title: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: Platform.isWindows
                  ? () => background.desktop?.toggleMaximized()
                  : null,
              child: SizedBox(
                width: double.infinity,
                child: focusMode || background.desktop?.compact == true
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          border: Border.all(color: Colors.white70),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Pomodoro Club',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Indicators & Work Dashboard',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            actions: [
              if (focusMode || background.desktop?.compact == true) ...[
                IconButton(
                  onPressed: show,
                  icon: const Icon(Icons.dashboard_outlined),
                  tooltip: 'Все разделы',
                ),
                IconButton(
                  onPressed: () async {
                    foreground = false;
                    await background.desktop?.hide();
                  },
                  icon: const Icon(Icons.visibility_off_outlined),
                  tooltip: 'Скрыть таймер в трей',
                ),
              ] else ...[
                IconButton(
                  onPressed: repo.syncing ? null : repo.synchronize,
                  icon: Icon(
                    repo.online ? Icons.sync : Icons.cloud_off_outlined,
                  ),
                  tooltip: repo.status,
                ),
                IconButton(
                  onPressed: settings,
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Настройки и нормативы',
                ),
              ],
            ],
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final playerVisible =
                background.desktop?.compact == true || focusMode;
            final wide = constraints.maxWidth >= 950;
            visitedSections.add(section);
            final builders = [
              indicatorsPage,
              projectsPage,
              workPage,
              () => WritingScreen(repo: repo),
              dataPage,
            ];
            return Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: playerVisible,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide)
                        SizedBox(
                          width: 220,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: ListView(
                              key: const PageStorageKey('sidebar-scroll'),
                              children: [
                                const SizedBox(height: 16),
                                for (var i = 0; i < sections.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: FilledButton.tonal(
                                      onPressed: () => selectSection(i),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: section == i
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .secondaryContainer
                                            : Colors.transparent,
                                        alignment: Alignment.centerLeft,
                                        minimumSize: const Size(
                                          double.infinity,
                                          48,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(icons[i], size: 20),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              sections[i],
                                              softWrap: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                const SizedBox(height: 12),
                                const Text(
                                  'I&W · Native 0.1.37',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        key: const ValueKey('dashboard-page-stack'),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                              child: ActivityStatus(
                                repo: repo,
                                showTimer: false,
                                inspect: () => selectSection(4),
                              ),
                            ),
                            Expanded(
                              child: IndexedStack(
                                index: section,
                                children: [
                                  for (var i = 0; i < builders.length; i++)
                                    visitedSections.contains(i)
                                        ? ListView(
                                            key: ValueKey('section:$i'),
                                            controller: pageScrolls[i],
                                            padding: EdgeInsets.all(
                                              wide ? 28 : 16,
                                            ),
                                            children: [builders[i]()],
                                          )
                                        : const SizedBox.shrink(),
                                ],
                              ),
                            ),
                            DashboardTimerBar(
                              repo: repo,
                              pulse: clockPulse,
                              open: () => changeFocus(true),
                              pause: () => safe(
                                () => repo.timerAction(
                                  repo.active?['status'] == 'paused'
                                      ? 'resume'
                                      : 'pause',
                                ),
                              ),
                              finish: finishTimer,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (playerVisible) Positioned.fill(child: focusPlayer()),
              ],
            );
          },
        ),
        bottomNavigationBar:
            MediaQuery.sizeOf(context).width < 950 &&
                !focusMode &&
                background.desktop?.compact != true
            ? SectionNavigation(
                selected: section,
                select: selectSection,
                labels: sections,
                icons: icons,
              )
            : null,
      ),
    ),
  );
  @override
  void dispose() {
    ticker?.cancel();
    clockPulse.dispose();
    repo.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    overlayAllowed.dispose();
    scrollSave?.cancel();
    savePagePositions();
    for (final controller in pageScrolls) {
      controller.dispose();
    }
    if (widget.backgroundEnabled && Platform.isWindows) {
      windowManager.removeListener(this);
    }
    if (widget.backgroundEnabled) unawaited(background.close());
    super.dispose();
  }
}
