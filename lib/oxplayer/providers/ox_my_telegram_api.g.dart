// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ox_my_telegram_api.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$myTelegramOxChatsClientHash() =>
    r'b90aea03e5a291eb9371ff5ab6a8825d8a3c9742';

/// Dependency hook for OX `/me/chats` REST from [Riverpod](https://riverpod.dev/). Add
/// `@riverpod` notifiers and families (indexed media, pagination, invalidation) in this
/// directory — do not call `http` from OX `lib/oxplayer/**/widgets` directly.
///
/// Conventions: `oxplayer-client/.cursor/rules/oxplayer-override-strategy.mdc` (Riverpod section).
///
/// Copied from [myTelegramOxChatsClient].
@ProviderFor(myTelegramOxChatsClient)
final myTelegramOxChatsClientProvider =
    AutoDisposeProvider<OxplayerUserChatsClient?>.internal(
  myTelegramOxChatsClient,
  name: r'myTelegramOxChatsClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$myTelegramOxChatsClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MyTelegramOxChatsClientRef
    = AutoDisposeProviderRef<OxplayerUserChatsClient?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
