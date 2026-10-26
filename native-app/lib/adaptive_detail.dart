import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A centered form keeps its state while adapting to narrow windows/keyboard.
Future<T?> showAdaptiveDetail<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => Navigator.of(context).push<T>(
  PageRouteBuilder<T>(
    opaque: false,
    barrierDismissible: false,
    barrierColor: Colors.black26,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondary) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: LayoutBuilder(
          builder: (context, size) {
            final wide = size.maxWidth >= 700;
            return Align(
              alignment: Alignment.center,
              child: SizedBox(
                key: const ValueKey('adaptive-detail-panel'),
                width: wide ? min(720, size.maxWidth - 48) : size.maxWidth,
                height: wide ? max(0, size.maxHeight - 48) : size.maxHeight,
                child: Material(
                  elevation: wide ? 12 : 0,
                  borderRadius: BorderRadius.circular(wide ? 16 : 0),
                  clipBehavior: Clip.antiAlias,
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(child: Builder(builder: builder)),
                ),
              ),
            );
          },
        ),
      ),
    ),
  ),
);

class DetailFrame extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  const DetailFrame({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Назад к списку',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: body,
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 8,
          children: actions,
        ),
      ),
    ],
  );
}
