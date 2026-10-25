import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import 'focus_art_catalog.dart';
import 'focus_rotation.dart';
export 'focus_art_catalog.dart';

const focusColors = {
  'green': Color(0xff243b30),
  'evening': Color(0xff40394f),
  'desert': Color(0xff826246),
  'lofi': Color(0xff343e57),
  'monet': Color(0xff293e4a),
};

Map<String, String> get focusThemes => {
  'green': 'Зелень',
  'evening': 'Вечер',
  'desert': 'Пустыня',
  'lofi': 'Лофи',
  for (final painting in focusArtworks) painting.id: painting.label,
  'custom': 'Своя картина',
};

class FocusBackdrop extends StatefulWidget {
  final String theme;
  final String? customImage;
  final bool enabled;
  final Map<String, dynamic> rotation;
  final Widget child;
  const FocusBackdrop({
    super.key,
    required this.theme,
    required this.enabled,
    this.customImage,
    this.rotation = const {},
    required this.child,
  });
  @override
  State<FocusBackdrop> createState() => _FocusBackdropState();
}

class _FocusBackdropState extends State<FocusBackdrop>
    with WidgetsBindingObserver {
  Timer? timer;
  String? theme;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    theme = focusThemeAt(
      widget.theme,
      widget.rotation,
      DateTime.now().millisecondsSinceEpoch,
    );
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (!widget.enabled || widget.rotation['enabled'] != true) return;
    final anchor = widget.rotation['anchorMs'];
    if (anchor is! int) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final period = rotationMinutes(widget.rotation) * 60000;
    final elapsed = now > anchor ? now - anchor : 0;
    final delay = now < anchor
        ? anchor - now + period
        : period - elapsed % period;
    timer = Timer(Duration(milliseconds: delay), () {
      refresh();
      schedule();
    });
  }

  void refresh() {
    final next = focusThemeAt(
      widget.theme,
      widget.rotation,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (!mounted) return;
    // No repository notifications, database writes or editor reconstruction.
    if (theme != next) setState(() => theme = next);
  }

  @override
  void didUpdateWidget(covariant FocusBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    theme = focusThemeAt(
      widget.theme,
      widget.rotation,
      DateTime.now().millisecondsSinceEpoch,
    );
    schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      schedule();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.enabled
      ? DecoratedBox(
          decoration: focusDecoration(
            theme ?? widget.theme,
            customImage: widget.customImage,
          ),
          child: RepaintBoundary(child: widget.child),
        )
      : widget.child;
}

BoxDecoration focusDecoration(String theme, {String? customImage}) =>
    BoxDecoration(
      color: focusColors[theme] ?? focusColors['green']!,
      image:
          theme == 'custom' &&
              customImage != null &&
              File(customImage).existsSync()
          ? DecorationImage(
              image: ResizeImage.resizeIfNeeded(
                1920,
                null,
                FileImage(File(customImage)),
              ),
              fit: BoxFit.cover,
              colorFilter: const ColorFilter.mode(
                Color(0x800c1720),
                BlendMode.srcOver,
              ),
            )
          : focusArt.containsKey(theme)
          ? DecorationImage(
              image: ResizeImage.resizeIfNeeded(
                1920,
                null,
                AssetImage('assets/art/${focusArt[theme]}'),
              ),
              fit: BoxFit.cover,
              alignment: const Alignment(-.3, -.05),
              colorFilter: const ColorFilter.mode(
                Color(0x800c1720),
                BlendMode.srcOver,
              ),
            )
          : null,
    );

Map<String, String> get focusArt => {
  for (final painting in focusArtworks) painting.id: painting.file,
};

/// The painting is bundled locally; selecting it never needs a network call.
class FocusSurface extends StatelessWidget {
  final String theme;
  final String? customImage;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final Map<String, dynamic> rotation;

  const FocusSurface({
    super.key,
    required this.theme,
    required this.child,
    this.customImage,
    this.rotation = const {},
    this.radius = 24,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: focusColors[theme] ?? focusColors['green']!,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: FocusBackdrop(
      theme: theme,
      customImage: customImage,
      rotation: rotation,
      enabled: true,
      child: Padding(padding: padding, child: child),
    ),
  );
}
