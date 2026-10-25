import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The same route and form state survive resizing from a side panel to a page.
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
      child: LayoutBuilder(
        builder: (context, size) {
          final side = size.maxWidth >= 1100;
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              key: const ValueKey('adaptive-detail-panel'),
              width: side ? min(600, size.maxWidth * .48) : size.maxWidth,
              height: size.maxHeight,
              child: Material(
                elevation: side ? 12 : 0,
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(child: Builder(builder: builder)),
              ),
            ),
          );
        },
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
