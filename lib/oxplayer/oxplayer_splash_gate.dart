import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_api_reachability.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_device_identity.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_online_status.dart';
import 'package:fladder/oxplayer/oxplayer_riverpod_ref.dart';
import 'package:fladder/oxplayer/oxplayer_session_refresh_coordinator.dart';
import 'package:fladder/oxplayer/oxplayer_session_recovery_navigation.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/login/lock_screen.dart';
import 'package:fladder/util/app_http_client.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/fladder_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OxplayerSplashGateResult {
  proceedToDashboard,
  /// Saved session kept; oxplayer-be did not respond to `/health`.
  serverUnavailable,
  needLogin,
}

/// Upper bound for splash session restore (health probe + refresh).
const Duration kOxplayerSplashSessionGateMaxWait = Duration(seconds: 15);

/// `GET /health` before `POST /auth/refresh` so a dead API does not block splash.
const Duration kOxplayerSplashApiProbeTimeout = Duration(seconds: 3);

Future<void> oxplayerClearIncompleteLoginSession(dynamic ref) async {
  if (!OxplayerConfig.isEnabled) return;
  final r = oxplayerCoerceRef(ref);

  AccountModel? currentUser = r.read(userProvider);
  currentUser ??= r.read(sharedUtilityProvider).getActiveAccount();

  if (currentUser != null) {
    final zeroed = currentUser.copyWith(
      credentials: currentUser.credentials.copyWith(
        token: '',
        oxRefreshToken: '',
      ),
    );
    await r.read(sharedUtilityProvider).addAccount(zeroed);
    await r.read(sharedUtilityProvider).removeAccount(currentUser);
  }

  r.read(authProvider.notifier).clearAllProviders();
  oxplayerClearSessionEstablished();
  r.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
      OxplayerBackgroundAuthStatus.idle;
  r.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
}

final oxplayerBackgroundSessionRefreshProvider = Provider<OxplayerBackgroundSessionRefresh>((ref) {
  return OxplayerBackgroundSessionRefresh(ref);
});

class OxplayerBackgroundSessionRefresh {
  OxplayerBackgroundSessionRefresh(this.ref);

  final Ref ref;
  Future<void>? _inFlight;

  Future<void> start() {
    final current = _inFlight;
    if (current != null) return current;

    final future = _run();
    _inFlight = future;
    future.whenComplete(() => _inFlight = null);
    return future;
  }

  Future<void> _run() async {
    if (!OxplayerConfig.isEnabled) {
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.online;
      return;
    }

    if (oxplayerSessionEstablishedThisProcess ||
        oxplayerSessionRefreshCompletedRecently(const Duration(minutes: 2))) {
      ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.online;
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.idle;
      return;
    }

    final ok = await oxplayerSilentRefreshSession(ref);
    if (!ok) {
      final stillHaveToken =
          ref.read(sharedUtilityProvider).getActiveAccount()?.credentials.token.trim().isNotEmpty == true;
      if (!stillHaveToken) {
        await oxplayerClearIncompleteLoginSession(ref);
        oxplayerScheduleSessionRecoveryNavigation(ref);
      }
    }
  }
}

Future<void> oxplayerOnBackgroundSessionRefreshFailed(dynamic ref) async {
  if (OxplayerConfig.isEnabled) {
    unawaited(oxplayerClearIncompleteLoginSession(ref));
    oxplayerScheduleSessionRecoveryNavigation(ref);
  }
}

Future<OxplayerSplashGateResult> oxplayerRunSplashSessionGate(WidgetRef ref) async {
  if (!OxplayerConfig.isEnabled) {
    return OxplayerSplashGateResult.proceedToDashboard;
  }

  final result = await oxplayerWithExclusiveSessionRefresh(
    () => _oxplayerSplashSessionGateWithTimeout(ref),
  );

  if (result == OxplayerSplashGateResult.proceedToDashboard) {
    oxplayerNoteSessionEstablished();
    oxplayerSetApiServerReachable(ref, true);
    ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
    ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
        OxplayerBackgroundAuthStatus.online;
  } else if (result == OxplayerSplashGateResult.serverUnavailable) {
    oxplayerSetApiServerReachable(ref, false);
  }

  return result;
}

Future<OxplayerSplashGateResult> _oxplayerSplashSessionGateWithTimeout(WidgetRef ref) {
  return _oxplayerRunSplashSessionGateImpl(ref).timeout(
    kOxplayerSplashSessionGateMaxWait,
    onTimeout: () {
      if (kDebugMode) {
        debugPrint('[OX] splash gate timeout — keeping cached session if present');
      }
      final saved = ref.read(sharedUtilityProvider).getActiveAccount();
      final token = saved?.credentials.token.trim() ?? '';
      final refresh = saved?.credentials.oxRefreshToken.trim() ?? '';
      if (token.isNotEmpty && refresh.isNotEmpty) {
        _oxplayerResumeWithCachedSession(ref);
        return OxplayerSplashGateResult.proceedToDashboard;
      }
      return OxplayerSplashGateResult.needLogin;
    },
  );
}

/// Restores saved tokens into Riverpod without network I/O.
OxplayerSplashGateResult? _oxplayerResumeWithCachedSession(WidgetRef ref) {
  final saved = ref.read(sharedUtilityProvider).getActiveAccount();
  if (saved == null) return null;
  final token = saved.credentials.token.trim();
  final refresh = saved.credentials.oxRefreshToken.trim();
  if (token.isEmpty || refresh.isEmpty) return null;

  ref.read(authProvider.notifier).oxplayerAttachSessionToken(
        token,
        serverId: saved.credentials.serverId,
        refreshToken: refresh,
      );
  ref.read(userProvider.notifier).updateUser(saved);
  ref.read(lockScreenActiveProvider.notifier).update((s) => false);
  return OxplayerSplashGateResult.proceedToDashboard;
}

/// `GET {apiBase}/health` — fast fail when oxplayer-be is down or URL is wrong.
Future<bool> oxplayerProbeApiReachable(String apiBase) async {
  try {
    final uri = Uri.parse(apiBase).resolve('health');
    final response = await appHttpClient.get(uri).timeout(kOxplayerSplashApiProbeTimeout);
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[OX] API health probe failed ($apiBase): $e');
    }
    return false;
  }
}

/// Returns false when the server rejects the refresh token (user must log in again).
Future<bool> oxplayerSilentRefreshSession(
  dynamic ref, {
  Duration httpTimeout = kOxAuthHttpTimeoutSplash,
}) async {
  if (!OxplayerConfig.isEnabled) return true;

  final r = oxplayerCoerceRef(ref);
  final api = OxplayerEnv.apiBaseUrl;
  if (api == null) return true;

  final saved = r.read(sharedUtilityProvider).getActiveAccount();
  final refresh = saved?.credentials.oxRefreshToken.trim() ?? '';
  if (refresh.isEmpty) return false;

  try {
    final app = r.read(applicationInfoProvider);
    final deviceName = '${app.name} / ${defaultTargetPlatform.name}';
    final identity = await oxplayerResolveDeviceIdentity(defaultDeviceName: deviceName);
    final exchanged = await OxplayerTelegramAuthClient(apiBase: api).refreshAccessToken(
      refreshToken: refresh,
      deviceId: identity.deviceId,
      httpTimeout: httpTimeout,
    );
    await r.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(
          exchanged,
          awaitServerInfo: false,
        );
    r.read(oxplayerApiServerReachableProvider.notifier).state = true;
    r.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
    r.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
        OxplayerBackgroundAuthStatus.online;
    return true;
  } on OxplayerTelegramAuthException catch (e) {
    if (kDebugMode) {
      debugPrint('[OX] silent refresh auth failed: ${e.message}');
    }
    if (e.isNetworkUnreachable) {
      r.read(oxplayerApiServerReachableProvider.notifier).state = false;
      final stillHaveToken =
          r.read(sharedUtilityProvider).getActiveAccount()?.credentials.token.trim().isNotEmpty == true;
      if (stillHaveToken) {
        r.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
            OxplayerBackgroundAuthStatus.online;
        return true;
      }
    }
    r.read(oxplayerBackgroundAuthErrorProvider.notifier).state = e.message;
    r.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
        OxplayerBackgroundAuthStatus.error;
    return false;
  } catch (e) {
    // Network / timeout: keep the saved session so cold start does not force re-login.
    if (kDebugMode) {
      debugPrint('[OX] silent refresh failed (keeping session): $e');
    }
    final stillHaveToken =
        r.read(sharedUtilityProvider).getActiveAccount()?.credentials.token.trim().isNotEmpty == true;
    if (stillHaveToken) {
      r.read(oxplayerApiServerReachableProvider.notifier).state = false;
      r.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.online;
      return true;
    }
    r.read(oxplayerBackgroundAuthErrorProvider.notifier).state = e.toString();
    r.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
        OxplayerBackgroundAuthStatus.error;
    return false;
  }
}

Future<OxplayerSplashGateResult> _oxplayerRunSplashSessionGateImpl(WidgetRef ref) async {
  final api = OxplayerEnv.apiBaseUrl;
  final media = OxplayerEnv.effectiveMediaServerUrl;
  if (api == null || media == null) {
    return OxplayerSplashGateResult.needLogin;
  }
  FladderConfig.baseUrl = media;

  try {
    await ref.read(authProvider.notifier).initModel(clearUserState: false);
  } catch (_) {
    return OxplayerSplashGateResult.needLogin;
  }

  if (ref.read(authProvider).errorMessage != null) {
    return OxplayerSplashGateResult.needLogin;
  }

  final saved = ref.read(sharedUtilityProvider).getActiveAccount();
  if (saved == null) {
    return OxplayerSplashGateResult.needLogin;
  }

  final token = saved.credentials.token.trim();
  final refresh = saved.credentials.oxRefreshToken.trim();
  if (token.isEmpty && refresh.isEmpty) {
    return OxplayerSplashGateResult.needLogin;
  }

  if (!await oxplayerProbeApiReachable(api)) {
    if (kDebugMode) {
      debugPrint('[OX] splash: API unreachable — keep session, server-unavailable UI');
    }
    if (token.isNotEmpty || refresh.isNotEmpty) {
      _oxplayerResumeWithCachedSession(ref);
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.idle;
      return OxplayerSplashGateResult.serverUnavailable;
    }
    return OxplayerSplashGateResult.needLogin;
  }

  oxplayerSetApiServerReachable(ref, true);

  // Restore cached tokens first, then refresh without logging out on transient failures.
  if (token.isNotEmpty && refresh.isNotEmpty) {
    final resumed = _oxplayerResumeWithCachedSession(ref);
    if (resumed != null) {
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.refreshing;
      final refreshed = await oxplayerSilentRefreshSession(ref);
      if (!refreshed) {
        return OxplayerSplashGateResult.needLogin;
      }
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.online;
      return OxplayerSplashGateResult.proceedToDashboard;
    }
  }

  if (refresh.isEmpty) {
    return OxplayerSplashGateResult.needLogin;
  }

  ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
      OxplayerBackgroundAuthStatus.refreshing;

  final refreshed = await oxplayerSilentRefreshSession(ref);
  if (!refreshed) {
    await oxplayerClearIncompleteLoginSession(ref);
    return OxplayerSplashGateResult.needLogin;
  }

  if (ref.read(userProvider) == null) {
    final resumed = _oxplayerResumeWithCachedSession(ref);
    if (resumed == null) {
      return OxplayerSplashGateResult.needLogin;
    }
  }

  ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
      OxplayerBackgroundAuthStatus.online;
  return OxplayerSplashGateResult.proceedToDashboard;
}
