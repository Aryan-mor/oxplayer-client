import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Increment after a successful "Add to library index" so [MyTelegramChatMediaScreen] can
/// reload the Indexed tab without a manual pull-to-refresh.
final myTelegramIndexedIngestBumpedProvider = StateProvider<int>((ref) => 0);
