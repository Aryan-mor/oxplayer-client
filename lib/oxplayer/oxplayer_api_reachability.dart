import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether oxplayer-be responded to `GET /health` on the last check.
final oxplayerApiServerReachableProvider = StateProvider<bool>((ref) => true);

void oxplayerSetApiServerReachable(WidgetRef ref, bool reachable) {
  ref.read(oxplayerApiServerReachableProvider.notifier).state = reachable;
}
