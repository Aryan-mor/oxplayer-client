import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/providers/oxplayer_swr_cache.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_runtime.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/user_provider.dart';

enum OxplayerBackgroundAuthStatus {
  idle,
  connecting,
  refreshing,
  online,
  error,
}

enum OxplayerAppStatusKind {
  offline,
  connecting,
  updating,
  online,
  error,
}

class OxplayerAppStatus {
  const OxplayerAppStatus({
    required this.kind,
    required this.label,
    this.message,
  });

  final OxplayerAppStatusKind kind;
  final String label;
  final String? message;

  bool get isOffline => kind == OxplayerAppStatusKind.offline;
  bool get shouldShowBanner => kind != OxplayerAppStatusKind.online;
}

final oxplayerBackgroundAuthStatusProvider =
    StateProvider<OxplayerBackgroundAuthStatus>((ref) {
  return OxplayerBackgroundAuthStatus.idle;
});

final oxplayerBackgroundAuthErrorProvider = StateProvider<Object?>((ref) {
  return null;
});

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

final oxplayerAppStatusProvider = Provider<OxplayerAppStatus>((ref) {
  final networkOffline = ref.watch(connectivityStatusProvider) == ConnectionState.offline;
  if (networkOffline) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.offline,
      label: 'Offline',
    );
  }

  if (!OxplayerConfig.isEnabled) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.online,
      label: 'Online',
    );
  }

  final user = ref.watch(userProvider);
  final hasToken = user != null && user.credentials.token.trim().isNotEmpty;
  if (!hasToken) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.offline,
      label: 'Offline',
      message: 'No saved session',
    );
  }

  final authStatus = ref.watch(oxplayerBackgroundAuthStatusProvider);
  final activeRequests = ref.watch(oxplayerSwrActiveRequestCountProvider);
  if (authStatus == OxplayerBackgroundAuthStatus.error) {
    return OxplayerAppStatus(
      kind: OxplayerAppStatusKind.error,
      label: 'Connection issue',
      message: ref.watch(oxplayerBackgroundAuthErrorProvider)?.toString(),
    );
  }
  if (authStatus == OxplayerBackgroundAuthStatus.connecting) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.connecting,
      label: 'Connecting',
    );
  }
  if (authStatus == OxplayerBackgroundAuthStatus.refreshing) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.connecting,
      label: 'Refreshing session',
    );
  }
  if (activeRequests > 0) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.updating,
      label: 'Updating',
    );
  }

  final tgReady = kIsWeb ? true : ref.watch(oxplayerTelegramSessionReadyProvider);
  if (!tgReady && authStatus != OxplayerBackgroundAuthStatus.online) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.connecting,
      label: 'Connecting Telegram',
    );
  }

  return const OxplayerAppStatus(
    kind: OxplayerAppStatusKind.online,
    label: 'Online',
  );
});

/// Offline for UI and route logic: plain Fladder = no network only.
/// OX = real network loss or no saved Jellyfin token. Telegram reconnection is
/// represented as "connecting" so saved users can continue using cached UI.
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
  return false;
});
