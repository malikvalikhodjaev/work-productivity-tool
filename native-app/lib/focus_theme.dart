import 'dart:io';

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
  'modigliani': 'Модильяни · Мадам Помпадур',
  'renoir': 'Ренуар · Букет хризантем',
  'pissarro': 'Писсарро · Хрустальный дворец',
  'soutine': 'Сутин · Пейзаж Сере',
  'levitan': 'Левитан · Золотая осень',
  'shishkin': 'Шишкин · Рожь',
  'custom': 'Своя картина',
};

class FocusBackdrop extends StatelessWidget {
  final String theme;
  final String? customImage;
  final bool enabled;
  final Widget child;
  const FocusBackdrop({
    super.key,
    required this.theme,
    required this.enabled,
    this.customImage,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => enabled
      ? DecoratedBox(
          decoration: focusDecoration(theme, customImage: customImage),
          child: child,
        )
      : child;
}

BoxDecoration focusDecoration(String theme, {String? customImage}) =>
    BoxDecoration(
      color: focusColors[theme] ?? focusColors['green']!,
      image:
          theme == 'custom' &&
              customImage != null &&
              File(customImage).existsSync()
          ? DecorationImage(
              image: FileImage(File(customImage)),
              fit: BoxFit.cover,
              colorFilter: const ColorFilter.mode(
                Color(0x800c1720),
                BlendMode.srcOver,
              ),
            )
          : focusArt.containsKey(theme)
          ? DecorationImage(
              image: AssetImage('assets/art/${focusArt[theme]}'),
              fit: BoxFit.cover,
              alignment: const Alignment(-.3, -.05),
              colorFilter: const ColorFilter.mode(
                Color(0x800c1720),
                BlendMode.srcOver,
              ),
            )
          : null,
    );

const focusArt = {
  'monet': 'monet-water-lilies-1906.jpg',
  'modigliani': 'modigliani-painting.jpg',
  'renoir': 'renoir-painting.jpg',
  'pissarro': 'pissarro-painting.jpg',
  'soutine': 'soutine-painting.jpg',
  'levitan': 'levitan-painting.jpg',
  'shishkin': 'shishkin-painting.jpg',
};

/// The painting is bundled locally; selecting it never needs a network call.
class FocusSurface extends StatelessWidget {
  final String theme;
  final String? customImage;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const FocusSurface({
    super.key,
    required this.theme,
    required this.child,
    this.customImage,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: focusColors[theme] ?? focusColors['green']!,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: Ink(
      decoration: focusDecoration(theme, customImage: customImage),
      child: Padding(padding: padding, child: child),
    ),
  );
}
