import 'dart:math';

import 'package:flutter/material.dart';

import 'focus_problem_line.dart';

/// The countdown/actions and the open checklist have separate bounded areas.
/// Only problems and settings open a temporary panel.
class AdaptiveFocusPlayer extends StatefulWidget {
  final String clock, mode, weeklyProblem, dailyProblem;
  final Listenable changes;
  final bool paused;
  final String pauseClock;
  final VoidCallback? takeBreak;
  final VoidCallback? editWeeklyProblem, editDailyProblem;
  final Widget contextPanel, description, actions, norms, settings;
  const AdaptiveFocusPlayer({
    super.key,
    required this.changes,
    required this.clock,
    required this.mode,
    this.paused = false,
    this.pauseClock = '',
    this.takeBreak,
    required this.weeklyProblem,
    required this.dailyProblem,
    this.editWeeklyProblem,
    this.editDailyProblem,
    required this.contextPanel,
    required this.description,
    required this.actions,
    required this.norms,
    required this.settings,
  });
  @override
  State<AdaptiveFocusPlayer> createState() => _AdaptiveFocusPlayerState();
}

class _AdaptiveFocusPlayerState extends State<AdaptiveFocusPlayer> {
  final coreScroll = ScrollController();
  final checklistScroll = ScrollController();
  @override
  void dispose() {
    coreScroll.dispose();
    checklistScroll.dispose();
    super.dispose();
  }

  void open(String name) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff243b30),
      builder: (context) => ListenableBuilder(
        listenable: widget.changes,
        builder: (context, _) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .82,
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: Colors.white, fontSize: 14),
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      name == 'problems' ? 'Проблемы' : 'Настройки таймера',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Закрыть панель',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: name == 'problems'
                          ? widget.contextPanel
                          : widget.settings,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final height = min(900.0, max(0.0, box.maxHeight));
      final dense = height < 540;
      final tiny = height < 310;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final clock = SizedBox(
        height:
            (tiny
                ? 42.0
                : dense
                ? 44.0
                : 82.0) /
            min(scale, 1.5),
        child: Column(
          children: [
            if (widget.paused)
              Text(
                widget.pauseClock.isEmpty
                    ? 'На паузе'
                    : 'Пауза · ${widget.pauseClock}',
                key: ValueKey('focus-paused-status'),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xffffdc9a),
                  fontWeight: FontWeight.w800,
                ),
              ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.clock,
                  key: const ValueKey('focus-clock'),
                  style: const TextStyle(
                    fontSize: 88,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      final tools = SingleChildScrollView(
        primary: false,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final name in [
              if (widget.takeBreak != null) 'break',
              'problems',
              'settings',
            ])
              TextButton(
                onPressed: name == 'break'
                    ? widget.takeBreak
                    : () => open(name),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                  textStyle: Theme.of(context).textTheme.labelLarge!
                      .copyWith(fontSize: tiny ? 12 : 14),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text(
                  name == 'break'
                      ? 'Перерыв'
                      : name == 'problems'
                      ? 'Проблемы'
                      : 'Настройки',
                ),
              ),
          ],
        ),
      );
      final core = Container(
        key: const ValueKey('focus-fixed-core'),
        padding: EdgeInsets.fromLTRB(
          dense ? 8 : 18,
          dense ? 0 : 8,
          dense ? 8 : 18,
          dense ? 0 : 4,
        ),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: Colors.white, fontSize: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FocusProblemLine(
                kind: 'week',
                label: 'Неделя',
                title: 'Главная проблема недели',
                text: widget.weeklyProblem,
                visibleLines: dense ? 1 : 2,
                edit: widget.editWeeklyProblem,
              ),
              SizedBox(height: dense ? 0 : 6),
              FocusProblemLine(
                kind: 'day',
                label: 'Сегодня',
                title: 'Главная проблема на сегодня',
                text: widget.dailyProblem,
                visibleLines: dense ? 1 : 2,
                edit: widget.editDailyProblem,
              ),
              SizedBox(height: dense ? 0 : 4),
              Row(
                children: [
                  Expanded(flex: 1, child: clock),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: dense ? 3 : 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          filledButtonTheme: FilledButtonThemeData(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              padding: EdgeInsets.symmetric(
                                horizontal: dense ? 4 : 24,
                              ),
                            ),
                          ),
                        ),
                        child: widget.actions,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: dense ? 0 : 4),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: tiny
                      ? MediaQuery.textScalerOf(context).scale(17) * 1.4 + 2
                      : dense
                      ? MediaQuery.textScalerOf(context).scale(17) * 1.4 + 2
                      : 78,
                ),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    key: const ValueKey('focus-context-scroll'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!dense)
                          Text(
                            widget.mode,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        widget.description,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      // This panel is permanent at every size, including the compact window.
      final checklist = Material(
        key: const ValueKey('focus-checklist-panel'),
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Scrollbar(
          controller: checklistScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: checklistScroll,
            key: const ValueKey('focus-checklist-scroll'),
            primary: false,
            child: widget.norms,
          ),
        ),
      );
      return Padding(
        padding: EdgeInsets.all(dense ? 4 : 8),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: height),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                dense ? 4 : 8,
                dense ? 0 : 8,
                dense ? 4 : 8,
                dense ? 0 : 8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xb312261f),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    flex: dense ? 11 : 3,
                    fit: FlexFit.loose,
                    child: Scrollbar(
                      controller: coreScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: coreScroll,
                        primary: false,
                        key: const ValueKey('focus-core-scroll'),
                        child: core,
                      ),
                    ),
                  ),
                  SizedBox(height: dense ? 4 : 8),
                  Flexible(
                    flex: dense ? 9 : 2,
                    fit: FlexFit.loose,
                    child: checklist,
                  ),
                  tools,
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
