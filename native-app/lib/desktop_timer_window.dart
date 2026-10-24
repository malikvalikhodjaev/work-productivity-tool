import 'dart:async';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

/// Changes only presentation: the dashboard keeps its repository and timer.
abstract class DesktopWindowPort {
  Future<Rect> bounds();
  Future<bool> maximized();
  Future<bool> pinned();
  Future<void> restore();
  Future<void> unmaximize();
  Future<void> maximize();
  Future<void> minimum(Size size);
  Future<void> resize(Rect bounds);
  Future<void> pin(bool value);
  Future<void> show({bool inactive = false});
  Future<void> focus();
  Future<void> hide();
}

class NativeDesktopWindow implements DesktopWindowPort {
  @override
  Future<Rect> bounds() => windowManager.getBounds();
  @override
  Future<bool> maximized() => windowManager.isMaximized();
  @override
  Future<bool> pinned() => windowManager.isAlwaysOnTop();
  @override
  Future<void> restore() => windowManager.restore();
  @override
  Future<void> unmaximize() => windowManager.unmaximize();
  @override
  Future<void> maximize() => windowManager.maximize();
  @override
  Future<void> minimum(Size size) => windowManager.setMinimumSize(size);
  @override
  Future<void> resize(Rect bounds) => windowManager.setBounds(bounds);
  @override
  Future<void> pin(bool value) => windowManager.setAlwaysOnTop(value);
  @override
  Future<void> show({bool inactive = false}) =>
      windowManager.show(inactive: inactive);
  @override
  Future<void> focus() => windowManager.focus();
  @override
  Future<void> hide() => windowManager.hide();
}

class DesktopTimerWindow {
  final DesktopWindowPort window;
  final void Function() changed;
  bool compact = false;
  bool player = false;
  bool transitioning = false;
  Rect? _previousBounds;
  bool _previousMaximized = false;
  bool _previousPinned = false;
  Completer<void>? _transitionDone;

  DesktopTimerWindow(this.window, {required this.changed});

  Future<void> minimize({required bool active, required bool enabled}) async {
    if (!active || !enabled || transitioning) return;
    _transitionDone = Completer<void>();
    transitioning = true;
    try {
      // A minimized Win32 window reports an off-screen rectangle. Restore
      // first, then capture the actual dashboard geometry before shrinking.
      await window.restore();
      if (!compact && !player) {
        _previousBounds = await window.bounds();
        _previousMaximized = await window.maximized();
        _previousPinned = await window.pinned();
      }
      compact = true;
      player = false;
      changed();
      await window.unmaximize();
      await window.minimum(const Size(340, 330));
      final origin = _previousBounds!.topLeft;
      await window.resize(origin & const Size(430, 430));
      await window.pin(true);
      await window.show(inactive: true);
    } finally {
      transitioning = false;
      _transitionDone!.complete();
    }
  }

  Future<void> showDashboard() async {
    while (transitioning) {
      await _transitionDone!.future;
    }
    _transitionDone = Completer<void>();
    transitioning = true;
    try {
      await window.restore();
      if (compact || player) {
        await window.minimum(const Size(380, 540));
        await window.resize(_previousBounds!);
        await window.pin(_previousPinned);
        if (_previousMaximized) await window.maximize();
        compact = false;
        player = false;
        changed();
      }
      await window.show();
      await window.focus();
    } finally {
      transitioning = false;
      _transitionDone!.complete();
    }
  }

  Future<void> showPlayer({required bool pinned}) async {
    while (transitioning) {
      await _transitionDone!.future;
    }
    _transitionDone = Completer<void>();
    transitioning = true;
    try {
      await window.restore();
      if (!compact && !player) {
        _previousBounds = await window.bounds();
        _previousMaximized = await window.maximized();
        _previousPinned = await window.pinned();
      }
      await window.unmaximize();
      await window.minimum(const Size(380, 540));
      await window.resize(_previousBounds!.topLeft & const Size(460, 720));
      await window.pin(pinned);
      compact = false;
      player = true;
      changed();
      await window.show();
      await window.focus();
    } finally {
      transitioning = false;
      _transitionDone!.complete();
    }
  }

  /// Explicit hiding does not change or stop the active timer.
  Future<void> hide() => window.hide();
}
