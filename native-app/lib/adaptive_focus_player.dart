import 'package:flutter/material.dart';

import 'focus_problem_line.dart';

/// Natural-height content; only the whole page scrolls in a short window.
class AdaptiveFocusPlayer extends StatefulWidget {
  final String clock, mode, weeklyProblem, dailyProblem;
  final Listenable changes;
  final bool paused;
  final String pauseClock;
  final VoidCallback? takeBreak, editWeeklyProblem, editDailyProblem;
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
  final pageScroll = ScrollController();
  @override
  void dispose() {
    pageScroll.dispose();
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
      final narrow = box.maxWidth < 400;
      return Scrollbar(
        controller: pageScroll,
        child: SingleChildScrollView(
          key: const ValueKey('focus-page-scroll'),
          controller: pageScroll,
          primary: false,
          padding: EdgeInsets.all(narrow ? 8 : 16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: EdgeInsets.all(narrow ? 12 : 20),
                decoration: BoxDecoration(
                  color: const Color(0xb312261f),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyMedium!
                      .copyWith(color: Colors.white, fontSize: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FocusProblemLine(
                        kind: 'week',
                        label: 'Главная проблема недели',
                        title: 'Главная проблема недели',
                        text: widget.weeklyProblem,
                        visibleLines: 2,
                        edit: widget.editWeeklyProblem,
                      ),
                      const SizedBox(height: 8),
                      FocusProblemLine(
                        kind: 'day',
                        label: 'Главная проблема на сегодня',
                        title: 'Главная проблема на сегодня',
                        text: widget.dailyProblem,
                        visibleLines: 2,
                        edit: widget.editDailyProblem,
                      ),
                      const SizedBox(height: 16),
                      if (widget.paused)
                        Text(
                          widget.pauseClock.isEmpty
                              ? 'На паузе'
                              : 'Пауза · ${widget.pauseClock}',
                          key: const ValueKey('focus-paused-status'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xffffdc9a),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.clock,
                            key: const ValueKey('focus-clock'),
                            style: TextStyle(
                              fontSize: narrow ? 96 : 112,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            filledButtonTheme: FilledButtonThemeData(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(112, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          child: widget.actions,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (widget.mode.isNotEmpty)
                        Text(
                          widget.mode,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      const SizedBox(height: 4),
                      widget.description,
                      const SizedBox(height: 16),
                      Material(
                        key: const ValueKey('focus-checklist-panel'),
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: widget.norms,
                      ),
                      const SizedBox(height: 8),
                      Theme(
                        data: Theme.of(context).copyWith(
                          textButtonTheme: TextButtonThemeData(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size(48, 48),
                            ),
                          ),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            if (widget.takeBreak != null)
                              TextButton(
                                onPressed: widget.takeBreak,
                                child: const Text('Перерыв'),
                              ),
                            TextButton(
                              onPressed: () => open('problems'),
                              child: const Text('Проблемы'),
                            ),
                            TextButton.icon(
                              onPressed: () => open('settings'),
                              icon: const Icon(
                                Icons.settings_outlined,
                                size: 18,
                              ),
                              label: const Text('Настройки таймера'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
