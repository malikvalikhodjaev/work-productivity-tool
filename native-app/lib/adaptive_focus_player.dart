import 'dart:math';

import 'package:flutter/material.dart';

/// The countdown/actions and the open checklist have separate bounded areas.
/// Only problems and settings open a temporary panel.
class AdaptiveFocusPlayer extends StatefulWidget {
  final String clock, mode;
  final Listenable changes;
  final Widget contextPanel, description, actions, norms, settings;
  const AdaptiveFocusPlayer({
    super.key,
    required this.changes,
    required this.clock,
    required this.mode,
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
              style: const TextStyle(color: Colors.white, fontSize: 14),
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
      final dense = box.maxHeight < 540;
      final side = box.maxWidth >= 980 && box.maxHeight >= 480;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final clock = SizedBox(
        height: (dense ? 56.0 : 88.0) / min(scale, 1.5),
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
      );
      final tools = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!dense)
            Expanded(
              child: Text(
                widget.mode,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          for (final name in ['problems', 'settings'])
            if (dense)
              IconButton(
                tooltip: name == 'problems' ? 'Проблемы' : 'Тема и звук',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
                padding: const EdgeInsets.all(4),
                visualDensity: VisualDensity.compact,
                onPressed: () => open(name),
                icon: Icon(
                  name == 'problems' ? Icons.flag_outlined : Icons.tune,
                  color: Colors.white,
                  size: 20,
                ),
              )
            else
              TextButton(
                onPressed: () => open(name),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(name == 'problems' ? 'Проблемы' : 'Тема и звук'),
              ),
        ],
      );
      final core = Container(
        key: const ValueKey('focus-fixed-core'),
        padding: EdgeInsets.all(dense ? 8 : 18),
        decoration: BoxDecoration(
          color: const Color(0x9a12261f),
          borderRadius: BorderRadius.circular(22),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (box.maxHeight >= 780)
                SizedBox(
                  height: min(130, box.maxHeight * .16),
                  child: SingleChildScrollView(child: widget.contextPanel),
                ),
              if (dense)
                Row(
                  children: [
                    Expanded(child: clock),
                    tools,
                  ],
                )
              else
                clock,
              const SizedBox(height: 4),
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    key: const ValueKey('focus-context-scroll'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (dense)
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
              const SizedBox(height: 4),
              widget.actions,
              if (!dense) tools,
            ],
          ),
        ),
      );
      // This panel is permanent at every size, including the compact window.
      final checklist = Material(
        key: const ValueKey('focus-checklist-panel'),
        color: Colors.transparent,
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
            constraints: BoxConstraints(maxWidth: side ? 1040 : 560),
            child: side
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: core),
                      const SizedBox(width: 16),
                      Expanded(child: checklist),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(flex: 53, child: core),
                      const SizedBox(height: 8),
                      Expanded(flex: 47, child: checklist),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
