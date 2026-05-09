import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped when [InputDetector] first switches to DPAD on Android so widgets that
/// `watch` this provider rebuild and pick up TV-oriented default shortcuts.
final hotkeyLayoutEpochProvider = StateProvider<int>((ref) => 0);
