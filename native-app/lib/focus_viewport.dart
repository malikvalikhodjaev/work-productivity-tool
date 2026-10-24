import 'package:flutter/material.dart';

/// A readable focus column, with explicit scrolling on short windows.
class FocusViewport extends StatefulWidget {
  final Widget child;
  const FocusViewport({super.key, required this.child});
  @override
  State<FocusViewport> createState() => _FocusViewportState();
}

class _FocusViewportState extends State<FocusViewport> {
  final controller = ScrollController();
  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: controller,
    thumbVisibility: true,
    interactive: true,
    child: ListView(
      controller: controller,
      padding: const EdgeInsets.all(12),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            key: const ValueKey('focus-readable-column'),
            constraints: const BoxConstraints(maxWidth: 560),
            child: SizedBox(width: double.infinity, child: widget.child),
          ),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
