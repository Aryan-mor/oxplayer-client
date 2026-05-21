import 'package:flutter/material.dart';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/api_result.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/models/login_screen_model.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:flutter/foundation.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_runtime.dart';
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

    // Sign out from Telegram to revoke the device session server-side and
    // wipe local TDLib database files so trySilentRestore() returns false.
    if (OxplayerConfig.isEnabled && !kIsWeb) {
      try {
        final session = OxplayerTelegramTdSession(
          tdlib: OxplayerTelegramTdRuntime.facade,
        );
        await session.signOut();
      } catch (e) {
        // Non-fatal: log the error but continue the logout flow.
        debugPrint('[OX logout] Telegram signOut error: $e');
      }
    }

    try {
      await ref.read(seerrApiProvider).logout();
    } catch (e) {
      // Ignore logout errors for seerr
    }
    clearAllProviders();
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
  Future<void> applyOxplayerTelegramAuthResponse(
    OxplayerTelegramAuthResponse exchanged,
  ) async {
    clearJellyfinDataCachesOnly();

    final ar = exchanged.jellyfin;
    final token = exchanged.accessToken.isNotEmpty
        ? exchanged.accessToken
        : (ar.accessToken ?? '');
    if (token.isEmpty) {
      throw StateError('Missing access token');
    }
    if (oxplayerServerLoginModel == null) {
      throw StateError('Server is not configured; connect to Jellyfin first');
    }

    oxplayerAttachSessionToken(
      token,
      serverId: ar.serverId,
      refreshToken: exchanged.refreshToken,
    );

    final serverResponse = await api.systemInfoPublicGet();
    final login = oxplayerServerLoginModel!;
    final mergedCreds = login.tempCredentials;
    final creds = mergedCreds.copyWith(
      serverName: serverResponse.body?.serverName ?? mergedCreds.serverName,
      serverId: ar.serverId ?? mergedCreds.serverId,
      oxRefreshToken: exchanged.refreshToken ?? mergedCreds.oxRefreshToken,
    );

    // Use Telegram photoUrl instead of Jellyfin image URL
    final imageUrl = exchanged.photoUrl ?? '';
    // final imageUrl = ref
    //     .read(imageUtilityProvider)
    //     .getUserImageUrl(ar.user?.id ?? '');
    final newUser = AccountModel(
      name: ar.user?.name ?? '',
      id: ar.user?.id ?? '',
      avatar: imageUrl,
      credentials: creds,
      lastUsed: DateTime.now(),
    );

    await ref.read(sharedUtilityProvider).addAccount(newUser);
    ref.read(userProvider.notifier).userState = newUser;
    getSavedAccounts();
  }

  void clearAllProviders() {
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
