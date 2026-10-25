import 'dart:math';

import 'package:flutter/material.dart';

/// The countdown/actions and the open checklist have separate bounded areas.
/// Only problems and settings open a temporary panel.
class AdaptiveFocusPlayer extends StatefulWidget {
  final String clock, mode;
  final Listenable changes;
  final bool paused;
  final Widget weeklyProblem,
      contextPanel,
      description,
      actions,
      norms,
      settings;
  const AdaptiveFocusPlayer({
    super.key,
    required this.changes,
    required this.clock,
    required this.mode,
    this.paused = false,
    required this.weeklyProblem,
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
                      name == 'problems' ? 'Проблемы' : 'Тема и звук',
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
      final height = min(900.0, max(0.0, box.maxHeight - 16));
      final dense = height < 540;
      final tiny = height < 310;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final clock = SizedBox(
        height:
            (tiny
                ? 44.0
                : dense
                ? 44.0
                : 82.0) /
            min(scale, 1.5),
        child: Column(
          children: [
            if (widget.paused)
              const Text(
                'На паузе',
                key: ValueKey('focus-paused-status'),
                style: TextStyle(
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
      final tools = Wrap(
        alignment: WrapAlignment.end,
        spacing: 4,
        children: [
          for (final name in ['problems', 'settings'])
            TextButton(
              onPressed: () => open(name),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 30),
                textStyle: Theme.of(context).textTheme.labelLarge!
                    .copyWith(fontSize: tiny ? 12 : 14),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(name == 'problems' ? 'Проблемы' : 'Тема и звук'),
            ),
        ],
      );
      final core = Container(
        key: const ValueKey('focus-fixed-core'),
        padding: EdgeInsets.fromLTRB(
          dense ? 8 : 18,
          dense ? 4 : 8,
          dense ? 8 : 18,
          4,
        ),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: Colors.white, fontSize: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: tiny
                      ? 50
                      : dense
                      ? 50
                      : 110,
                ),
                child: SingleChildScrollView(
                  key: const ValueKey('focus-weekly-scroll'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      widget.weeklyProblem,
                      if (tiny) widget.description,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(flex: 1, child: clock),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        height: dense ? 38 : 48,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: widget.actions,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!tiny) const SizedBox(height: 4),
              if (!tiny)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: tiny
                        ? 24
                        : dense
                        ? 24
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
              tools,
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
          child: SingleChildScrollView(
            key: const ValueKey('focus-checklist-scroll'),
            child: widget.norms,
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: height),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xb312261f),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  core,
                  const SizedBox(height: 8),
                  Flexible(fit: FlexFit.loose, child: checklist),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
