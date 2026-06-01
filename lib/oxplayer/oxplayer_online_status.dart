import 'package:fladder/oxplayer/oxplayer_api_reachability.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/user_provider.dart';
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

final oxplayerBackgroundAuthStatusProvider =
    StateProvider<OxplayerBackgroundAuthStatus>((ref) {
  return OxplayerBackgroundAuthStatus.idle;
});

final oxplayerBackgroundAuthErrorProvider = StateProvider<Object?>((ref) {
  return null;
});

bool oxplayerHasApiSessionToken(Ref ref) {
  final fromUser =
      ref.watch(userProvider.select((u) => u?.credentials.token.trim() ?? ''));
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
    final networkOffline =
        ref.watch(connectivityStatusProvider) == ConnectionState.offline;
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
  final networkOffline =
      ref.watch(connectivityStatusProvider) == ConnectionState.offline;
  final apiReachable = ref.watch(oxplayerApiServerReachableProvider);

  if (!apiReachable && (hasToken || hasRefresh)) {
    return const OxplayerAppStatus(
      kind: OxplayerAppStatusKind.error,
      label: 'Server unavailable',
    );
  }

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

  return const OxplayerAppStatus(
    kind: OxplayerAppStatusKind.online,
    label: 'Online',
  );
});

/// Offline for UI: Fladder = network only; OX = no saved api-v2 session.
final effectiveOfflineModeProvider = Provider<bool>((ref) {
  if (!OxplayerConfig.isEnabled) {
    return ref.watch(connectivityStatusProvider) == ConnectionState.offline;
  }
  if (!oxplayerHasApiSessionToken(ref) && !oxplayerHasOxRefreshToken(ref)) {
    return true;
  }
  return false;
});
