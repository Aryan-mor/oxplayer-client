import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PinchPosterZoom extends ConsumerStatefulWidget {
  final Widget child;
  final Function(double difference)? scaleDifference;
  const PinchPosterZoom({required this.child, this.scaleDifference, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PinchPosterZoomState();
}

class _PinchPosterZoomState extends ConsumerState<PinchPosterZoom> {
  double lastScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final pinchEnabled =
        ref.watch(clientSettingsProvider.select((value) => value.pinchPosterZoom));
    // A [GestureDetector] with scale handlers registers a scale recognizer that competes with
    // vertical scrolling and breaks [RefreshIndicator] pull-to-refresh. Omit it entirely when
    // pinch zoom is off (the default).
    if (!pinchEnabled) {
      return widget.child;
    }

    return GestureDetector(
      onScaleStart: (_) {
        lastScale = 1;
      },
      onScaleUpdate: (details) {
        final difference = details.scale - lastScale;
        widget.scaleDifference?.call(difference);
        lastScale = details.scale;
      },
      child: widget.child,
    );
  }
}
