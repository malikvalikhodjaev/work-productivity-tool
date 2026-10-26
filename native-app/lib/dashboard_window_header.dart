import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// The caption shares the parent painting, including Windows window controls.
class DashboardWindowHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final PreferredSizeWidget toolbar;
  final bool enabled, themed;
  const DashboardWindowHeader({
    super.key,
    required this.toolbar,
    required this.enabled,
    required this.themed,
  });
  @override
  Size get preferredSize =>
      Size.fromHeight(toolbar.preferredSize.height + (enabled ? 32 : 0));
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (enabled)
        SizedBox(
          height: 32,
          child: WindowCaption(
            backgroundColor: Colors.transparent,
            brightness: themed ? Brightness.dark : Theme.of(context).brightness,
            title: Text(
              themed ? 'Pomodoro Club' : 'Indicators & Work Dashboard',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: themed
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      Expanded(child: toolbar),
    ],
  );
}
