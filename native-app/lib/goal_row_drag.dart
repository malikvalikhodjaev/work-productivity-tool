import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class GoalDragData {
  final String id, serverId;
  const GoalDragData(this.id, this.serverId);
}

class GoalDragHandle extends StatelessWidget {
  final GoalDragData data;
  final String title;
  final bool enabled;
  final ValueChanged<bool> dragging;
  const GoalDragHandle({
    super.key,
    required this.data,
    required this.title,
    required this.enabled,
    required this.dragging,
  });
  @override
  Widget build(BuildContext context) {
    final handle = Tooltip(
      triggerMode: TooltipTriggerMode.manual,
      message: enabled ? 'Перетащить строку вместе с подцелями' : 'Для переноса включи «Порядок строк» и восстанови ветвь из архива или корзины',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.grab : SystemMouseCursors.basic,
        child: SizedBox(
          width: 28,
          height: 40,
          child: Icon(
            Icons.drag_indicator,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: enabled ? .65 : .25),
          ),
        ),
      ),
    );
    if (!enabled) return handle;
    final feedback = Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(title, softWrap: true),
        ),
      ),
    );
    final mobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (mobile) {
      return LongPressDraggable<GoalDragData>(
        data: data,
        feedback: feedback,
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: () => dragging(true),
        onDragEnd: (_) => dragging(false),
        child: handle,
      );
    }
    return Draggable<GoalDragData>(
      data: data,
      feedback: feedback,
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => dragging(true),
      onDragEnd: (_) => dragging(false),
      child: handle,
    );
  }
}

/// Top/bottom quarters reorder siblings; the centre nests the entire branch.
class GoalDropSurface extends StatefulWidget {
  final Widget child;
  final bool root;
  final bool Function(GoalDragData, String) accepts;
  final void Function(GoalDragData, String) drop;
  final void Function(Offset)? hover;
  const GoalDropSurface({
    super.key,
    required this.child,
    required this.accepts,
    required this.drop,
    this.root = false,
    this.hover,
  });
  @override
  State<GoalDropSurface> createState() => _GoalDropSurfaceState();
}

class _GoalDropSurfaceState extends State<GoalDropSurface> {
  String? placement;
  String position(Offset global) {
    if (widget.root) return 'root';
    final box = context.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(global).dy, height = box.size.height;
    return y < height * .25
        ? 'before'
        : y > height * .75
        ? 'after'
        : 'inside';
  }

  void clear() {
    if (placement != null) setState(() => placement = null);
  }

  @override
  Widget build(BuildContext context) => DragTarget<GoalDragData>(
    onWillAcceptWithDetails: (d) => [
      'before',
      'inside',
      'after',
      'root',
    ].any((p) => widget.accepts(d.data, p)),
    onMove: (d) {
      widget.hover?.call(d.offset);
      final p = position(d.offset), next = widget.accepts(d.data, p) ? p : null;
      if (next != placement) setState(() => placement = next);
    },
    onLeave: (_) => clear(),
    onAcceptWithDetails: (d) {
      final p = position(d.offset);
      clear();
      if (widget.accepts(d.data, p)) widget.drop(d.data, p);
    },
    builder: (context, candidates, rejected) {
      final color = Theme.of(context).colorScheme.primary;
      return Stack(
        children: [
          widget.child,
          if (placement != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  key: ValueKey('goal-drop-guide:$placement'),
                  decoration: BoxDecoration(
                    color: placement == 'inside' || placement == 'root'
                        ? color.withValues(alpha: .08)
                        : null,
                    border: Border(
                      top: BorderSide(
                        color:
                            placement == 'before' ||
                                placement == 'inside' ||
                                placement == 'root'
                            ? color
                            : Colors.transparent,
                        width: 2,
                      ),
                      bottom: BorderSide(
                        color:
                            placement == 'after' ||
                                placement == 'inside' ||
                                placement == 'root'
                            ? color
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  alignment: placement == 'after'
                      ? Alignment.bottomRight
                      : Alignment.topRight,
                  child: Container(
                    color: color,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text(
                      switch (placement) {
                        'before' => 'Перед строкой',
                        'after' => 'После строки',
                        'root' => 'На верхний уровень',
                        _ => 'Вложить под строку',
                      },
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
