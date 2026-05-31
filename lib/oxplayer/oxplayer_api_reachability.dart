import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether oxplayer-be responded to `GET /health` on the last check.
///
/// `false` after splash probe failure or explicit mark; does not clear saved tokens.
final oxplayerApiServerReachableProvider = StateProvider<bool>((ref) => true);

void oxplayerSetApiServerReachable(WidgetRef ref, bool reachable) {
  ref.read(oxplayerApiServerReachableProvider.notifier).state = reachable;
}
