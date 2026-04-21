import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_runtime.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/user_provider.dart';

/// TDLib has an authenticated user (native OX builds only). Drives offline gate with API token.
final oxplayerTelegramSessionReadyProvider =
    NotifierProvider<OxplayerTelegramSessionReadyNotifier, bool>(
  OxplayerTelegramSessionReadyNotifier.new,
);

class OxplayerTelegramSessionReadyNotifier extends Notifier<bool> {
  StreamSubscription<int>? _authSub;

  @override
  bool build() {
    if (kIsWeb || !OxplayerConfig.isEnabled) {
      return true;
    }

    ref.onDispose(() {
      unawaited(_authSub?.cancel());
    });

    _authSub = OxplayerTelegramTdRuntime.facade.authenticatedUserId.listen((id) {
      state = id != 0;
    });

    unawaited(_bootstrapFromDisk());
    return false;
  }

  Future<void> _bootstrapFromDisk() async {
    try {
      await OxplayerTelegramTdSession.initPlugin();
      final s = OxplayerTelegramTdSession();
      await s.initClient();
      final ok = await s.trySilentRestore();
      if (ok) {
        state = true;
      }
    } catch (_) {
      state = false;
    }
  }
}

/// Offline for UI and session logic: plain Fladder = no network only.
/// OX = network **and** Jellyfin token **and** (on native) Telegram TDLib authorized.
final effectiveOfflineModeProvider = Provider<bool>((ref) {
  final networkOffline = ref.watch(connectivityStatusProvider) == ConnectionState.offline;
  if (!OxplayerConfig.isEnabled) {
    return networkOffline;
  }
  if (networkOffline) {
    return true;
  }
  final user = ref.watch(userProvider);
  final hasToken = user != null && user.credentials.token.trim().isNotEmpty;
  if (!hasToken) {
    return true;
  }
  if (kIsWeb) {
    return false;
  }
  final tgReady = ref.watch(oxplayerTelegramSessionReadyProvider);
  return !tgReady;
});
