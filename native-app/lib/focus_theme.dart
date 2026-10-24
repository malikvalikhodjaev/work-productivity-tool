import 'package:flutter/material.dart';

const focusColors = {
  'green': Color(0xff243b30),
  'evening': Color(0xff40394f),
  'desert': Color(0xff826246),
  'lofi': Color(0xff343e57),
  'monet': Color(0xff293e4a),
};

const focusThemes = {
  'green': 'Зелень',
  'evening': 'Вечер',
  'desert': 'Пустыня',
  'lofi': 'Лофи',
  'monet': 'Моне · Кувшинки',
};

/// The painting is bundled locally; selecting it never needs a network call.
class FocusSurface extends StatelessWidget {
  final String theme;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const FocusSurface({
    super.key,
    required this.theme,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: focusColors[theme] ?? focusColors['green']!,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: Ink(
      decoration: BoxDecoration(
        image: theme == 'monet'
            ? const DecorationImage(
                image: AssetImage('assets/art/monet-water-lilies-1906.jpg'),
                fit: BoxFit.cover,
                // Keep the quiet blue water near the countdown at every size.
                alignment: Alignment(-.3, -.05),
                colorFilter: ColorFilter.mode(
                  Color(0x800c1720),
                  BlendMode.srcOver,
                ),
              )
            : null,
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}
