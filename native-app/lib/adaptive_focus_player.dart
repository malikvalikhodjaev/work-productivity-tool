import 'dart:math';

import 'package:flutter/material.dart';

/// The clock and main actions never belong to a scrolling list.
/// Long context and secondary panels have their own bounded viewports.
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
  String selected = 'norms';
  Widget panel(String name) => switch (name) {
    'problems' => widget.contextPanel,
    'settings' => widget.settings,
    _ => widget.norms,
  };
  String label(String name) => switch (name) {
    'problems' => 'Проблемы',
    'settings' => 'Тема и звук',
    _ => 'Нормативы',
  };
  void open(String name, bool inline) {
    setState(() => selected = name);
    if (!inline) {
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
                        label(name),
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
                        child: panel(name),
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
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final short = box.maxHeight < 780;
      final tiny = box.maxHeight < 400;
      final side = box.maxWidth >= 980 && box.maxHeight >= 480;
      final inline = box.maxHeight >= 620 || side;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final core = Container(
        key: const ValueKey('focus-fixed-core'),
        padding: EdgeInsets.all(
          tiny
              ? 10
              : short
              ? 14
              : 22,
        ),
        decoration: BoxDecoration(
          color: const Color(0x9a12261f),
          borderRadius: BorderRadius.circular(22),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!short)
                SizedBox(
                  height: min(130, box.maxHeight * .18),
                  child: SingleChildScrollView(child: widget.contextPanel),
                ),
              Text(widget.mode, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              SizedBox(
                height:
                    (tiny
                        ? 56.0
                        : short
                        ? 66.0
                        : 108.0) /
                    min(scale, 1.5),
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
              const SizedBox(height: 6),
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    key: const ValueKey('focus-context-scroll'),
                    child: widget.description,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              widget.actions,
              const SizedBox(height: 8),
              if (tiny)
                Row(
                  children: [
                    for (final name in ['norms', 'problems', 'settings'])
                      Expanded(
                        child: IconButton(
                          tooltip: label(name),
                          onPressed: () => open(name, inline),
                          icon: Icon(
                            name == 'norms'
                                ? Icons.checklist
                                : name == 'problems'
                                ? Icons.flag_outlined
                                : Icons.tune,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                )
              else
                Wrap(
                  spacing: 4,
                  children: [
                    for (final name in ['norms', 'problems', 'settings'])
                      TextButton(
                        onPressed: () => open(name, inline),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: selected == name && inline
                              ? Colors.white12
                              : null,
                        ),
                        child: Text(label(name)),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
      final support = Container(
        key: const ValueKey('focus-support-panel'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xc922372e),
          borderRadius: BorderRadius.circular(22),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 14),
          child: Scrollbar(
            child: SingleChildScrollView(child: panel(selected)),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: side ? 1040 : 560),
            child: side
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: core),
                      const SizedBox(width: 16),
                      Expanded(child: support),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(flex: 6, child: core),
                      if (inline) ...[
                        const SizedBox(height: 12),
                        Expanded(flex: 4, child: support),
                      ],
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
