import 'dart:async';

import 'package:fladder/oxplayer/oxplayer_api_reachability.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_runtime.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final oxplayerBackgroundAuthStatusProvider = StateProvider<OxplayerBackgroundAuthStatus>((ref) {
  return OxplayerBackgroundAuthStatus.idle;
});

final oxplayerBackgroundAuthErrorProvider = StateProvider<Object?>((ref) {
  return null;
});

/// TDLib has an authenticated user (native OX builds only). Drives offline gate with API token.
final oxplayerTelegramSessionReadyProvider = NotifierProvider<OxplayerTelegramSessionReadyNotifier, bool>(
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
      if (await s.hasPartialInteractiveAuthorization()) {
        state = false;
        return;
      }
      final ok = await s.trySilentRestore();
      state = ok;
    } catch (_) {
      state = false;
    }
  }
}

/// Jellyfin access token from [userProvider] or OX auth bootstrap [authProvider] temp creds.
bool oxplayerHasApiSessionToken(Ref ref) {
  final fromUser = ref.watch(userProvider.select((u) => u?.credentials.token.trim() ?? ''));
  if (fromUser.isNotEmpty) return true;
  final fromAuth = ref.watch(
    authProvider.select((s) => s.serverLoginModel?.tempCredentials.token.trim() ?? ''),
  );
  return fromAuth.isNotEmpty;
}

bool oxplayerHasOxRefreshToken(Ref ref) {
  final fromUser =
      ref.watch(userProvider.select((u) => u?.credentials.oxRefreshToken.trim() ?? ''));
  if (fromUser.isNotEmpty) return true;
  return ref.watch(
        authProvider.select((s) => s.serverLoginModel?.tempCredentials.oxRefreshToken.trim() ?? ''),
      ).isNotEmpty;
}

final oxplayerAppStatusProvider = Provider<OxplayerAppStatus>((ref) {
  if (!OxplayerConfig.isEnabled) {
    final networkOffline = ref.watch(connectivityStatusProvider) == ConnectionState.offline;
    if (networkOffline) {
      return const OxplayerAppStatus(
        kind: OxplayerAppStatusKind.offline,
        label: 'Offline',
      );
    }
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.online,
      label: 'Online',
    );
  }

  final hasToken = oxplayerHasApiSessionToken(ref);
  final hasRefresh = oxplayerHasOxRefreshToken(ref);
  final networkOffline = ref.watch(connectivityStatusProvider) == ConnectionState.offline;
  final apiReachable = ref.watch(oxplayerApiServerReachableProvider);

  if (!apiReachable && (hasToken || hasRefresh)) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.error,
      label: 'Server unavailable',
    );
  }

  // v2: api-v2 session is enough; do not show Offline when Jellyfin calls are working but
  // connectivity_plus flapped or [userProvider] is briefly empty after bootstrap.
  if (!hasToken && !hasRefresh) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.offline,
      label: 'Offline',
      message: 'No saved session',
    );
  }
  if (networkOffline && !hasToken) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.offline,
      label: 'Offline',
    );
  }

  final authStatus = ref.watch(oxplayerBackgroundAuthStatusProvider);
  if (authStatus == OxplayerBackgroundAuthStatus.error && !hasToken) {
    return OxplayerAppStatus(
      kind: OxplayerAppStatusKind.error,
      label: 'Connection issue',
      message: ref.watch(oxplayerBackgroundAuthErrorProvider)?.toString(),
    );
  }
  if (authStatus == OxplayerBackgroundAuthStatus.refreshing) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.connecting,
      label: 'Refreshing session',
    );
  }
  if (authStatus == OxplayerBackgroundAuthStatus.connecting) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.connecting,
      label: 'Connecting',
    );
  }

  // TDLib optional (My Telegram only); never block "Online" for claim-code + api-v2.
  if (!kIsWeb && hasToken) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.online,
      label: 'Online',
    );
  }

  final tgReady = ref.watch(oxplayerTelegramSessionReadyProvider);
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
  if (!OxplayerConfig.isEnabled) {
    return ref.watch(connectivityStatusProvider) == ConnectionState.offline;
  }
  if (!oxplayerHasApiSessionToken(ref) && !oxplayerHasOxRefreshToken(ref)) {
    return true;
  }
  // OX: cached session + LAN api-v2 — not "offline mode" when the radio says offline but HTTP works.
  return false;
});
