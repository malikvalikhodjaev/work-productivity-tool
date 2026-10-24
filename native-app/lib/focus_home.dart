import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'active_timer_conflict.dart';
import 'background.dart';
import 'focus_theme.dart';
import 'domain.dart';
import 'focus_repository.dart';
import 'focus_backup.dart';
import 'forms.dart';
import 'leisure.dart';
import 'pomodoro_widgets.dart';
import 'timer_ringtones.dart';

class FocusHome extends StatefulWidget {
  final FocusRepository repo;
  final String folder;
  final bool backgroundEnabled;
  const FocusHome({
    super.key,
    required this.repo,
    required this.folder,
    this.backgroundEnabled = true,
  });
  @override
  State<FocusHome> createState() => _FocusHomeState();
}

class _FocusHomeState extends State<FocusHome>
    with WidgetsBindingObserver, WindowListener {
  FocusRepository get repo => widget.repo;
  late final BackgroundRuntime background;
  Timer? ticker;
  bool foreground = true, dialogOpen = false, exiting = false;
  String? alarmKey, reviewKey, leisurePrompt;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    background = BackgroundRuntime(
      repo,
      appTitle: 'Focus & Norms',
      timerOnly: true,
    );
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
        open: (screen) async {
          await show();
          if (screen == 'norms') {
            await showPlan();
          } else if (screen == 'leisure') {
            await safe(() => askLeisureReturn(context, repo));
          } else if (repo.active != null &&
              repo.active!['mode'] == 'pomodoro' &&
              elapsedMs(repo.active!, repo.now) >= repo.active!['plannedMs']) {
            await finish();
          }
        },
        windowChanged: () {
          if (mounted) setState(() {});
        },
      );
      repo.local.set('focusRuntime', {
        'ready': true,
        'version': '0.1.0',
        'platform': Platform.operatingSystem,
      });
    } catch (error) {
      if (mounted) message(error.toString());
    }
  }

  void changed() {
    if (mounted) setState(() {});
    if (widget.backgroundEnabled) {
      unawaited(
        background.update().catchError((Object error) {
          if (mounted) message(error.toString());
        }),
      );
    }
  }

  void message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> safe(Future<void> Function() action) async {
    try {
      await action();
    } on ActiveTimerConflict catch (error) {
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Уже есть активный таймер'),
          content: Text(error.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Оставить'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Открыть таймер'),
            ),
          ],
        ),
      );
      if (open == true) await show();
    } catch (error) {
      message(error is StateError ? error.message : error.toString());
    }
  }

  Future<void> show() async {
    if (widget.backgroundEnabled) await background.show();
    foreground = true;
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) changed();
  }

  @override
  void onWindowMinimize() {
    foreground = false;
    if (!dialogOpen) unawaited(background.showCompactTimer());
  }

  @override
  void onWindowRestore() {
    foreground = true;
  }

  @override
  void onWindowClose() async {
    if (exiting) return;
    if (await background.showCompactTimer()) return;
    await windowManager.hide();
    foreground = false;
  }

  Future<void> exitApp() async {
    if (!mounted) return;
    final exit = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Завершить Focus & Norms?'),
        content: const Text(
          'Данные сохранены. После полного выхода звук и сигналы прекратятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Оставить в фоне'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (exit == true) {
      exiting = true;
      await background.close();
      if (Platform.isWindows) {
        await windowManager.setPreventClose(false);
        await windowManager.close();
      } else {
        await SystemNavigator.pop();
      }
    }
  }

  void tick() {
    if (!mounted) return;
    setState(() {});
    final s = repo.active;
    final canPrompt =
        foreground && !dialogOpen && !Navigator.of(context).canPop();
    if (s != null &&
        s['status'] == 'running' &&
        s['mode'] == 'pomodoro' &&
        elapsedMs(s, repo.now) >= s['plannedMs']) {
      final key = '${s['id']}:${s['plannedMs']}';
      if (alarmKey != key) {
        alarmKey = key;
        if (widget.backgroundEnabled) {
          unawaited(background.notifyTimer(foreground: foreground));
        }
      }
      if (canPrompt && reviewKey != key) {
        reviewKey = key;
        unawaited(finish());
      }
    }
    if (leisureDue(s, repo.now) &&
        canPrompt &&
        leisurePrompt != leisureKey(s!)) {
      leisurePrompt = leisureKey(s);
      unawaited(safe(() => askLeisureReturn(context, repo)));
    }
    final until = repo.local.get('focusReminderUntil') as int? ?? 0;
    if (canPrompt &&
        s == null &&
        repo.now >= until &&
        (!repo.hasPomodoroPlan ||
            repo.pomodoroTargetsForDate().any(
              (n) => n['actualPomodoros'] < n['target'],
            ))) {
      unawaited(showPlan());
    }
  }

  Future<void> showPlan() async {
    if (dialogOpen || !mounted) return;
    dialogOpen = true;
    repo.local.set('focusReminderUntil', repo.now + 3600000);
    try {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(
            repo.hasPomodoroPlan
                ? 'Сделал это?'
                : 'Вы поставили нормативы на день?',
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: PomodoroChecklist(
                repo: repo,
                focus: (ref, title) async {
                  Navigator.pop(c);
                  await play(ref, title);
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Позже · через час'),
            ),
          ],
        ),
      );
    } finally {
      dialogOpen = false;
    }
  }

  Future<void> play(String ref, String title) =>
      safe(() => repo.focusWork(ref: ref, title: title));
  Future<void> editWork([Json? old]) async {
    await editFields(
      context,
      title: old == null ? 'Новая работа' : 'Изменить работу',
      initial: {
        'title': old?['title'] ?? '',
        'description': old?['description'] ?? '',
      },
      fields: const [
        FieldSpec('title', 'Название'),
        FieldSpec('description', 'Описание и заметки', lines: 4),
      ],
      save: (input) async {
        final id = old?['id'] ?? uuid.v4();
        repo.nativeSave('workspace', 'saveWorkItem', {
          ...input,
          'id': id,
          'create': old == null,
          'expectedRevision': old?['revision'] ?? 0,
        }, 'work:$id');
      },
    );
  }

  Future<void> finish() async {
    final s = repo.active;
    if (s == null || dialogOpen) return;
    dialogOpen = true;
    try {
      await editFields(
        context,
        title: s['phase'] == 'work'
            ? 'Как прошла работа?'
            : 'Завершить перерыв',
        submitLabel: 'Учесть',
        initial: {
          'minutes': (elapsedMs(s, repo.now) / 60000).toStringAsFixed(2),
          'observation': '',
        },
        fields: const [
          FieldSpec(
            'minutes',
            'Сколько минут действительно работал',
            numeric: true,
          ),
          FieldSpec('observation', 'Наблюдения', lines: 5),
        ],
        save: (input) async {
          if (repo.active?['id'] != s['id']) {
            throw StateError('Сеанс изменился. Открой текущий таймер.');
          }
          await repo.timerAction(
            'finish',
            workedSeconds: ((input['minutes'] as num) * 60).round(),
            observation: input['observation'].toString(),
          );
        },
      );
    } finally {
      dialogOpen = false;
    }
  }

  Future<void> cancel() async {
    final id = repo.active?['id'];
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Отменить сеанс без учёта?'),
        content: const Text(
          'Он останется в истории; рабочие минуты и помидорка не прибавятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Оставить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Отменить сеанс'),
          ),
        ],
      ),
    );
    if (yes == true && repo.active?['id'] == id) {
      await safe(() => repo.timerAction('cancel'));
    }
  }

  Future<void> timerSettings() async {
    await editFields(
      context,
      title: 'Настройки таймера',
      initial: {...repo.settings, 'mode': repo.timerMode},
      fields: const [
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
      save: (input) async =>
          repo.setFocusPreferences({...input, 'strategy': 'shared'}),
    );
  }

  Future<void> settings() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Настройки · Focus & Norms'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: repo,
              builder: (c, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Настройки таймера'),
                    onTap: timerSettings,
                  ),
                  ListTile(
                    title: const Text('Библиотека рингтонов'),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => TimerRingtoneLibrary(
                        repo: repo,
                        preview: background.previewRingtone,
                        stop: background.stopRingtonePreview,
                        changed: changed,
                        systemSettings: Platform.isAndroid
                            ? background.ringtoneSystemSettings
                            : null,
                      ),
                    ),
                  ),
                  if (Platform.isWindows)
                    SwitchListTile(
                      title: const Text('Таймер при сворачивании'),
                      value: repo.local.get('timerOnMinimize') != false,
                      onChanged: repo.setTimerOnMinimize,
                    ),
                  if (Platform.isAndroid) ...[
                    SwitchListTile(
                      title: const Text('Малое окно таймера'),
                      value: repo.local.get('androidOverlayEnabled') != false,
                      onChanged: (value) async {
                        repo.setAndroidOverlayEnabled(value);
                        if (value && widget.backgroundEnabled) {
                          await background.requestOverlayPermission();
                        }
                      },
                    ),
                    ListTile(
                      title: const Text('Разрешения уведомлений и будильника'),
                      onTap: background.requestPermissions,
                    ),
                  ],
                  ListTile(
                    title: const Text('Выгрузить копию'),
                    subtitle: const Text(
                      'Свои работы, нормы, сеансы и наблюдения в JSON',
                    ),
                    onTap: () => safe(() async {
                      final file = await repo.exportLocal(widget.folder);
                      if (widget.backgroundEnabled) {
                        await background.shareExport(file);
                      }
                      message('Копия: $file');
                    }),
                  ),
                  ListTile(
                    title: const Text('Восстановить из копии'),
                    subtitle: const Text('Выбрать JSON-файл Focus & Norms'),
                    onTap: () => safe(() async {
                      final raw = await pickFocusBackup();
                      if (raw == null || !mounted) return;
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialog) => AlertDialog(
                          title: const Text('Восстановить выбранную копию?'),
                          content: const Text(
                            'Текущие работы, нормы и история будут заменены содержимым файла. Перед заменой сохраняется отдельная копия прежних данных. Активную работу сначала нужно учесть или отменить.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog, false),
                              child: const Text('Отмена'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialog, true),
                              child: const Text('Восстановить'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        final previous = await repo.restoreBackup(
                          raw,
                          widget.folder,
                        );
                        message('Восстановлено. Предыдущая копия: $previous');
                      }
                    }),
                  ),
                  SelectableText(
                    'Данные: ${widget.folder}\nВерсия 0.1.0 · локальная работа · UTC+5',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget player({bool compact = false}) {
    final s = repo.active;
    return FocusSurface(
      theme: (repo.local.get('theme') ?? 'green').toString(),
      radius: 22,
      padding: EdgeInsets.all(compact ? 18 : 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Focus & Norms',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              if (compact)
                IconButton(
                  tooltip: 'Полный вид',
                  onPressed: show,
                  icon: const Icon(Icons.open_in_full, color: Colors.white),
                ),
              IconButton(
                tooltip: 'Настройки',
                onPressed: settings,
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
              ),
            ],
          ),
          Text(
            s == null ? 'Готов к фокусу' : clockOf(s, repo.now),
            style: TextStyle(
              fontSize: compact ? 54 : 76,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            s == null
                ? 'Выбери работу в чек-листе или списке'
                : s['title'].toString(),
            style: const TextStyle(fontSize: 20, color: Colors.white),
          ),
          if (s != null)
            Text(
              '${s['status'] == 'paused' ? 'Пауза · ' : ''}${(elapsedMs(s, repo.now) / 60000).toStringAsFixed(1)} мин',
              style: const TextStyle(color: Colors.white70),
            ),
          if (inLeisure(s)) LeisureInfo(session: s!, now: repo.now),
          const SizedBox(height: 16),
          if (s != null)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => safe(
                    () => repo.timerAction(
                      s['status'] == 'paused' ? 'resume' : 'pause',
                    ),
                  ),
                  child: Text(s['status'] == 'paused' ? 'Продолжить' : 'Пауза'),
                ),
                FilledButton.tonal(
                  onPressed: finish,
                  child: const Text('Учесть'),
                ),
                if (!compact) ...[
                  TextButton(
                    onPressed: () => safe(() => repo.timerAction('extend')),
                    child: const Text(
                      '+ 5 мин',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  if (s['phase'] == 'work')
                    TextButton(
                      onPressed: () => safe(() => chooseLeisure(context, repo)),
                      child: const Text(
                        'Leisure',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  TextButton(
                    onPressed: cancel,
                    child: const Text(
                      'Отменить',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 16),
          PomodoroChecklist(repo: repo, compact: compact, focus: play),
          if (!compact) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final pair in focusThemes.entries)
                  ChoiceChip(
                    label: Text(pair.value),
                    selected: (repo.local.get('theme') ?? 'green') == pair.key,
                    onSelected: (_) {
                      repo.local.set('theme', pair.key);
                      changed();
                    },
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: (repo.local.get('sound') ?? 'brown')
                        .toString(),
                    decoration: const InputDecoration(
                      labelText: 'Фоновый звук',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: [
                      for (final pair in {
                        'brown': 'Коричневый шум',
                        'pink': 'Розовый шум',
                        'white': 'Белый шум',
                        'rain': 'Дождь',
                        'wind': 'Ветер',
                        'lofi': 'Лофи',
                      }.entries)
                        DropdownMenuItem(
                          value: pair.key,
                          child: Text(pair.value),
                        ),
                    ],
                    onChanged: (value) {
                      repo.local.set('sound', value);
                      changed();
                    },
                  ),
                ),
                Switch(
                  value: repo.local.get('soundEnabled') == true,
                  onChanged: (value) {
                    repo.local.set('soundEnabled', value);
                    changed();
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget works() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Работы',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: () => editWork(),
                icon: const Icon(Icons.add),
                label: const Text('Новая работа'),
              ),
            ],
          ),
          if (repo.entities('workItems', 'work').isEmpty)
            const Text('Создай работу или сразу добавь норматив в чек-листе.'),
          for (final work in repo.entities('workItems', 'work'))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(work['title'].toString()),
              subtitle: Text((work['description'] ?? '').toString()),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Фокус',
                    onPressed: () =>
                        play('work:${work['id']}', work['title'].toString()),
                    icon: const Icon(Icons.play_arrow),
                  ),
                  IconButton(
                    tooltip: 'Изменить работу',
                    onPressed: () => editWork(work),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
          TextButton(
            onPressed: () => safe(() => repo.sharedAction('startBreak', {})),
            child: const Text('Начать перерыв'),
          ),
        ],
      ),
    ),
  );
  Widget history() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Учтённые минуты и история',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          Text(
            'Сегодня: ${((repo.workedMillisecondsByDay[today()] ?? 0) / 60000).toStringAsFixed(1)} мин · ${today()} · UTC+5',
          ),
          for (final session in rows(
            repo.cache('timer')['sessions'],
          ).reversed.take(60))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(session['title'].toString()),
              subtitle: Text(
                '${session['startedAt']} · ${session['status']} · ${(elapsedMs(session, repo.now) / 60000).toStringAsFixed(1)} мин\n${session['observation'] ?? ''}',
              ),
            ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final compact = background.desktop?.compact == true;
    return Scaffold(
      appBar: compact
          ? null
          : AppBar(
              title: const Text('Focus & Norms'),
              actions: [
                IconButton(
                  tooltip: 'Настройки',
                  onPressed: settings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 8 : 18),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 500 : 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                player(compact: compact),
                if (!compact) ...[
                  const SizedBox(height: 18),
                  works(),
                  const SizedBox(height: 18),
                  PomodoroWeek(repo: repo),
                  const SizedBox(height: 18),
                  history(),
                  const SizedBox(height: 14),
                  const Text(
                    'Данные сохраняются на этом устройстве. Сервер и аккаунт для запуска не нужны.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    ticker?.cancel();
    repo.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    if (widget.backgroundEnabled && Platform.isWindows) {
      windowManager.removeListener(this);
    }
    if (widget.backgroundEnabled) unawaited(background.close());
    super.dispose();
  }
}
