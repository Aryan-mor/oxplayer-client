import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_client.dart';

part 'ox_my_telegram_api.g.dart';

/// Dependency hook for OX `/me/chats` REST from [Riverpod](https://riverpod.dev/). Add
/// `@riverpod` notifiers and families (indexed media, pagination, invalidation) in this
/// directory — do not call `http` from OX `lib/oxplayer/**/widgets` directly.
///
/// Conventions: `oxplayer-client/.cursor/rules/oxplayer-override-strategy.mdc` (Riverpod section).
@riverpod
OxplayerUserChatsClient? myTelegramOxChatsClient(MyTelegramOxChatsClientRef ref) {
  return ref.watch(oxplayerUserChatsClientProvider);
}
