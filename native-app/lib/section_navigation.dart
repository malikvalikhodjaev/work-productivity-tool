import 'package:flutter/material.dart';

/// Full single-line labels keep their font size. On narrow screens or with
/// enlarged system text the bar scrolls horizontally instead of wrapping.
class SectionNavigation extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> select;
  const SectionNavigation({
    super.key,
    required this.labels,
    required this.icons,
    required this.selected,
    required this.select,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium!;
    final scaler = MediaQuery.textScalerOf(context);
    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, box) {
            final widths = labels.map((label) {
              final painter = TextPainter(
                text: TextSpan(text: label, style: style),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                maxLines: 1,
              )..layout();
              final width = painter.width + 20;
              painter.dispose();
              return width < 64 ? 64.0 : width;
            }).toList();
            final total = widths.fold<double>(0, (a, b) => a + b);
            final extra = total < box.maxWidth
                ? (box.maxWidth - total) / labels.length
                : 0.0;
            return SingleChildScrollView(
              key: const ValueKey('section-navigation-scroll'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Semantics(
                      selected: selected == i,
                      button: true,
                      label: labels[i],
                      child: InkWell(
                        key: ValueKey('section-tab:$i'),
                        onTap: () => select(i),
                        child: SizedBox(
                          width: widths[i] + extra,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected == i
                                        ? scheme.secondaryContainer
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Icon(icons[i], size: 24),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  labels[i],
                                  style: style,
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
