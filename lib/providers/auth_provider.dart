import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/api_result.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/models/login_screen_model.dart';
import 'package:fladder/oxplayer/oxplayer_account_flags.dart';
import 'package:fladder/oxplayer/oxplayer_online_status.dart';
import 'package:fladder/oxplayer/oxplayer_session_refresh_coordinator.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:flutter/foundation.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/dashboard_provider.dart';
import 'package:fladder/providers/favourites_provider.dart';
import 'package:fladder/providers/image_provider.dart';
import 'package:fladder/providers/library_screen_provider.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/seerr_dashboard_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/screens/login/lock_screen.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/fladder_config.dart';
import 'package:fladder/util/localization_helper.dart';

final authProvider =
    StateNotifierProvider<AuthNotifier, LoginScreenModel>((ref) {
  return AuthNotifier(ref);
});

class AuthNotifier extends StateNotifier<LoginScreenModel> {
  AuthNotifier(this.ref) : super(LoginScreenModel());

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  BuildContext? get localContext => ref.read(localizationContextProvider);

  /// When [clearUserState] is false (OX Telegram bootstrap), do not clear [userProvider] —
  /// the default deep link may open splash after a session exists; clearing would drop the
  /// active account until prefs are re-read.
  Future<void> initModel({bool clearUserState = true}) async {
    if (clearUserState) {
      ref.read(userProvider.notifier).clear();
    }
    final currentAccounts = ref.read(authProvider.notifier).getSavedAccounts();
    ref.read(lockScreenActiveProvider.notifier).update((state) => true);
    if (FladderConfig.baseUrl != null) {
      final url = FladderConfig.baseUrl;
      state = state.copyWith(
        hasBaseUrl: true,
      );
      if (url != null) {
        await setServer(url);
      }
    }
    state = state.copyWith(
      accounts: currentAccounts,
      screen: currentAccounts.isEmpty
          ? LoginScreenType.login
          : LoginScreenType.users,
    );
  }

  Future<void> _fetchServerInfo(String url) async {
    if (OxplayerConfig.isEnabled) {
      await _fetchServerInfoOx(url);
      return;
    }
    try {
      final newCredentials =
          CredentialsModel.createNewCredentials().copyWith(url: url);
      final newLoginModel = ServerLoginModel(tempCredentials: newCredentials);
      state = state.copyWith(
        serverLoginModel: newLoginModel,
        loading: true,
      );
      final publicUsers = (await getPublicUsers())?.body ?? [];
      final quickConnectStatus =
          (await api.quickConnectEnabled()).body ?? false;
      final branding = await api.getBranding();
      final serverResponse = await api.systemInfoPublicGet();
      final serverId = serverResponse.body?.id ?? "";
      state = state.copyWith(
        errorMessage: null,
        screen:
            quickConnectStatus ? LoginScreenType.code : LoginScreenType.login,
        serverLoginModel: newLoginModel.copyWith(
          tempCredentials: newCredentials.copyWith(
            serverName: serverResponse.body?.serverName ?? "",
            serverId: serverId,
          ),
          accounts: publicUsers,
          hasQuickConnect: quickConnectStatus,
          serverMessage: branding.body?.loginDisclaimer,
        ),
        loading: false,
      );

      final seerrUrl = _findSeerrUrlForServer(serverId);
      setTempSeerrUrl(seerrUrl);
    } catch (e) {
      state = state.copyWith(
        errorMessage: localContext?.localized.invalidUrl,
        loading: false,
      );
      FladderSnack.show(localContext?.localized.unableToConnectHost ?? "");
    }
  }

  /// Ensures [serverLoginModel] exists for claim-code / refresh login (OX API as Jellyfin).
  Future<void> ensureOxplayerServerLoginModel() async {
    if (oxplayerServerLoginModel != null) return;
    final url = FladderConfig.baseUrl ?? OxplayerEnv.effectiveMediaServerUrl;
    if (url == null || url.trim().isEmpty) {
      throw StateError(
        'API URL is not configured (OXPLAYER_API_BASE_URL in default.env).',
      );
    }
    if (FladderConfig.baseUrl == null || FladderConfig.baseUrl!.trim().isEmpty) {
      FladderConfig.baseUrl = url;
    }
    state = state.copyWith(hasBaseUrl: true);
    await _fetchServerInfoOx(url.trim());
    if (oxplayerServerLoginModel == null) {
      throw StateError(state.errorMessage ?? 'Could not reach the API');
    }
  }

  /// OX v2: skip Jellyfin public-user / quick-connect probes on every cold start.
  Future<void> _fetchServerInfoOx(String url) async {
    try {
      final newCredentials =
          CredentialsModel.createNewCredentials().copyWith(url: url);
      final saved = ref.read(sharedUtilityProvider).getActiveAccount();
      final merged = saved != null
          ? newCredentials.copyWith(
              token: saved.credentials.token,
              serverId: saved.credentials.serverId,
              serverName: saved.credentials.serverName,
              oxRefreshToken: saved.credentials.oxRefreshToken,
            )
          : newCredentials;
      state = state.copyWith(
        errorMessage: null,
        loading: false,
        serverLoginModel: ServerLoginModel(
          tempCredentials: merged,
          accounts: const [],
          hasQuickConnect: false,
        ),
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: localContext?.localized.invalidUrl,
        loading: false,
      );
    }
  }

  Future<Response<List<AccountModel>>?> getPublicUsers() async {
    try {
      state = state.copyWith(loading: true);
      final credentials = state.serverLoginModel?.tempCredentials;
      if (credentials == null) return null;
      var response = await api.usersPublicGet(credentials);
      if (response.isSuccessful && response.body != null) {
        var models = response.body ?? [];
        return response.copyWith(body: models.toList());
      }
      state = state.copyWith(
        serverLoginModel: state.serverLoginModel?.copyWith(
          accounts: response.body ?? [],
        ),
      );
      return response.copyWith(body: []);
    } catch (e) {
      return null;
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  Future<ApiResult<AccountModel>> authenticateUsingSecret(String secret) async {
    clearAllProviders();
    var response = await api.quickConnectAuthenticate(secret);
    return _createAccountModel(response).apiResult;
  }

  Future<Response<AccountModel>?> authenticateByName(
      String userName, String password) async {
    clearAllProviders();
    var response = await api.usersAuthenticateByNamePost(
        userName: userName, password: password);
    return _createAccountModel(response);
  }

  Future<Response<AccountModel>> _createAccountModel(
      Response<AuthenticationResult> response) async {
    CredentialsModel? credentials = state.serverLoginModel?.tempCredentials;
    if (credentials == null) return Response(response.base, null);
    if (response.isSuccessful &&
        (response.body?.accessToken?.isNotEmpty ?? false)) {
      var serverResponse = await api.systemInfoPublicGet();
      credentials = credentials.copyWith(
        token: response.body?.accessToken ?? "",
        serverId: response.body?.serverId ?? "",
        serverName: serverResponse.body?.serverName ?? "",
      );
      var imageUrl = ref
          .read(imageUtilityProvider)
          .getUserImageUrl(response.body?.user?.id ?? "");
      AccountModel newUser = AccountModel(
        name: response.body?.user?.name ?? "",
        id: response.body?.user?.id ?? "",
        avatar: imageUrl,
        credentials: credentials,
        lastUsed: DateTime.now(),
      );
      ref.read(sharedUtilityProvider).addAccount(newUser);
      ref.read(userProvider.notifier).userState = newUser;
      final currentAccounts =
          ref.read(authProvider.notifier).getSavedAccounts();

      state = state.copyWith(
        accounts: currentAccounts,
      );

      return Response(response.base, newUser);
    }
    return Response(response.base, null);
  }

  Future<Response?> logOutUser() async {
    final currentUser = ref.read(userProvider);
    state = state.copyWith(serverLoginModel: null);

    // Zero out tokens in SharedPreferences BEFORE removal so the splash gate
    // cannot reuse a session if the process dies mid-logout.
    if (currentUser != null) {
      final zeroed = currentUser.copyWith(
        credentials: currentUser.credentials.copyWith(
          token: '',
          oxRefreshToken: '',
        ),
      );
      await ref.read(sharedUtilityProvider).addAccount(zeroed);
    }

    await ref.read(sharedUtilityProvider).removeAccount(currentUser);
    getSavedAccounts();

    try {
      await ref.read(seerrApiProvider).logout();
    } catch (e) {
      // Ignore logout errors for seerr
    }
    clearAllProviders();
    ref.read(oxplayerAccountDeleteDisabledProvider.notifier).state = false;
    return null;
  }

  Future<void> switchUser() async {
    clearAllProviders();
  }

  /// Clears cached home/library UI state without clearing [userProvider].
  ///
  /// [applyOxplayerTelegramAuthResponse] used to call [switchUser] (which clears the
  /// active user) before attaching the new session. A second concurrent TDLib
  /// `authenticatedUserId` event could re-enter the bridge, call [switchUser] again,
  /// and null the user right after the first navigation — [AuthGuard] then sent
  /// users back to `/splash` / login.
  void clearJellyfinDataCachesOnly() {
    ref.read(dashboardProvider.notifier).clear();
    ref.read(viewsProvider.notifier).clear();
    ref.read(favouritesProvider.notifier).clear();
    ref.read(libraryScreenProvider.notifier).clear();
    ref.read(seerrDashboardProvider.notifier).clear();
  }

  ServerLoginModel? get oxplayerServerLoginModel => state.serverLoginModel;

  /// OXPlayer Telegram login: attach the issued Jellyfin token to the current [serverLoginModel] session.
  void oxplayerAttachSessionToken(
    String token, {
    String? serverId,
    String? refreshToken,
  }) {
    final sm = state.serverLoginModel;
    if (sm == null) return;
    final nextServerId = (serverId != null && serverId.isNotEmpty)
        ? serverId
        : sm.tempCredentials.serverId;
    final creds = sm.tempCredentials;
    final nextOxRefresh =
        refreshToken != null ? refreshToken.trim() : creds.oxRefreshToken;
    state = state.copyWith(
      serverLoginModel: sm.copyWith(
        tempCredentials: creds.copyWith(
          token: token,
          serverId: nextServerId,
          oxRefreshToken: nextOxRefresh,
        ),
      ),
    );
  }

  /// Applies a full OX `POST /auth/telegram` or `POST /auth/refresh` payload (Jellyfin-shaped + refresh).
  ///
  /// When [awaitServerInfo] is false (background refresh on cold start), tokens are persisted
  /// immediately and server metadata is fetched without blocking navigation.
  Future<void> applyOxplayerTelegramAuthResponse(
    OxplayerTelegramAuthResponse exchanged, {
    bool awaitServerInfo = true,
  }) async {
    clearJellyfinDataCachesOnly();

    final ar = exchanged.jellyfin;
    final token = exchanged.accessToken.isNotEmpty
        ? exchanged.accessToken
        : (ar.accessToken ?? '');
    if (token.isEmpty) {
      throw StateError('Missing access token');
    }
    if (oxplayerServerLoginModel == null) {
      await ensureOxplayerServerLoginModel();
    }

    oxplayerAttachSessionToken(
      token,
      serverId: ar.serverId,
      refreshToken: exchanged.refreshToken,
    );

    final login = oxplayerServerLoginModel!;
    final mergedCreds = login.tempCredentials;
    final credsWithToken = mergedCreds.copyWith(
      token: token,
      serverId: ar.serverId ?? mergedCreds.serverId,
      oxRefreshToken: exchanged.refreshToken ?? mergedCreds.oxRefreshToken,
    );

    // Login bootstrap uses initModel(clearUserState: false); JellyRequest prefers
    // userProvider over tempCredentials — set the new session before any API call.
    final imageUrl = exchanged.photoUrl ?? '';
    final newUser = AccountModel(
      name: ar.user?.name ?? '',
      id: ar.user?.id ?? '',
      avatar: imageUrl,
      credentials: credsWithToken,
      lastUsed: DateTime.now(),
      authMethod: Authentication.autoLogin,
    );
    ref.read(userProvider.notifier).userState = newUser;
    await ref.read(sharedUtilityProvider).addAccount(newUser);
    ref.read(oxplayerAccountDeleteDisabledProvider.notifier).state =
        exchanged.accountDeleteDisabled;
    getSavedAccounts();

    if (awaitServerInfo) {
      final serverResponse = await api.systemInfoPublicGet();
      final creds = credsWithToken.copyWith(
        serverName: serverResponse.body?.serverName ?? credsWithToken.serverName,
      );
      final persistedUser = newUser.copyWith(credentials: creds);
      await ref.read(sharedUtilityProvider).addAccount(persistedUser);
      ref.read(userProvider.notifier).userState = persistedUser;
    }

    if (OxplayerConfig.isEnabled && !kIsWeb) {
      oxplayerNoteSessionEstablished();
      ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.online;
    }
  }

  void clearAllProviders() {
    if (OxplayerConfig.isEnabled) {
      oxplayerClearSessionEstablished();
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.idle;
      ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
    }
    ref.read(dashboardProvider.notifier).clear();
    ref.read(viewsProvider.notifier).clear();
    ref.read(favouritesProvider.notifier).clear();
    ref.read(userProvider.notifier).clear();
    ref.read(libraryScreenProvider.notifier).clear();
    ref.read(seerrDashboardProvider.notifier).clear();
  }

  Future<void> setServer(String server) async {
    if (state.hasBaseUrl) {
      await _fetchServerInfo(FladderConfig.baseUrl!);
      return;
    }
    final trimmed = server.trim();
    if (trimmed.isEmpty) return;
    final result = await probeAndNormalizeUrl(trimmed, probeJellyfinUrl);
    await _fetchServerInfo(result.url);
  }

  List<AccountModel> getSavedAccounts() {
    state =
        state.copyWith(accounts: ref.read(sharedUtilityProvider).getAccounts());
    return state.accounts;
  }

  void reOrderUsers(int oldIndex, int newIndex) {
    final accounts = state.accounts.toList();
    final original = accounts.elementAt(oldIndex);
    accounts.removeAt(oldIndex);
    accounts.insert(newIndex, original);
    state = state.copyWith(accounts: accounts);
    ref.read(sharedUtilityProvider).saveAccounts(accounts);
  }

  void addNewUser() {
    state = state.copyWith(
      screen: LoginScreenType.login,
    );
  }

  void goUserSelect() {
    state = state.copyWith(
      serverLoginModel: state.hasBaseUrl ? state.serverLoginModel : null,
      screen: LoginScreenType.users,
    );
  }

  String? _findSeerrUrlForServer(String? serverId) {
    if (FladderConfig.seerrBaseUrl?.isNotEmpty == true) {
      return FladderConfig.seerrBaseUrl;
    }
    if (serverId == null || serverId.isEmpty) return null;
    final matches = state.accounts.where(
      (account) =>
          account.credentials.serverId == serverId &&
          (account.seerrCredentials?.serverUrl.isNotEmpty ?? false),
    );

    if (matches.isEmpty) return null;

    final sorted = matches.toList()
      ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));

    return sorted.first.seerrCredentials?.serverUrl;
  }

  void setTempSeerrUrl(String? url) {
    state = state.copyWith(
        tempSeerrUrl: url?.trim().isEmpty == true ? null : url?.trim());
  }

  void setTempSeerrSessionCookie(String? cookie) {
    state = state.copyWith(
        tempSeerrSessionCookie:
            cookie?.trim().isEmpty == true ? null : cookie?.trim());
  }
}
