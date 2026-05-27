import 'package:flutter/material.dart';

import 'package:flexible_scrollbar/flexible_scrollbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FladderScrollbar extends ConsumerWidget {
  final ScrollController controller;
  final Widget child;
  final bool visible;
  const FladderScrollbar({
    required this.controller,
    required this.child,
    this.visible = true,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!visible) return child;

    // flexible_scrollbar calls getBarDelta before barMaxScrollExtent is set when
    // maxScrollExtent is 0 or the controller is not attached (OXPLAYER-CLIENT-N).
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.hasClients || controller.position.maxScrollExtent <= 0) {
          return child;
        }
        return FlexibleScrollbar(
          child: child,
          controller: controller,
          alwaysVisible: false,
          scrollThumbBuilder: (ScrollbarInfo info) {
            return AnimatedContainer(
              width: info.isDragging ? 24 : 8,
              height: (info.thumbMainAxisSize / 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: info.isDragging
                    ? Theme.of(context).colorScheme.secondary
                    : Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.75),
              ),
              duration: const Duration(milliseconds: 250),
            );
          },
        );
      },
    );
  }
}
