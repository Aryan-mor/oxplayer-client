import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fladder/td_api_generated/td_api.dart' as td_api;

import 'package:fladder/oxplayer/oxplayer_debug.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';

import 'oxplayer_telegram_td_runtime.dart';
import 'tdlib_controller.dart' if (dart.library.html) 'tdlib_controller_web.dart';
import 'tdlib_facade.dart';

String _describeTdSendFailure(Object e) {
  if (e is td_api.TdError) {
    return '${e.message} (code ${e.code})';
  }
  try {
    final dyn = e as dynamic;
    final m = dyn.message;
    if (m is String && m.isNotEmpty) {
      return m;
    }
  } catch (_) {}
  final s = e.toString();
  if (s.contains('[object Object]') || s.contains('LegacyJavaScriptObject')) {
    return 'JS/TDLib request failed (open browser console → Network / TDLib for the rejected promise).';
  }
  return s;
}

const _kOxDeviceIdPrefsKey = 'oxplayer_td_device_id';

/// TDLib-backed Telegram login + the same backend `/auth/telegram` bridge as oxplayer-android.
final class OxplayerTelegramTdSession {
  OxplayerTelegramTdSession({TelegramTdlibFacade? tdlib}) : _td = tdlib ?? OxplayerTelegramTdRuntime.facade;

  final TelegramTdlibFacade _td;
  bool _clientInited = false;

  /// Dedupes concurrent [fetchSignedInitData] (e.g. duplicate [authenticatedUserId] events)
  /// so Telegram one-shot WebApp auth tokens are not consumed twice in parallel.
  Future<String>? _signedInitDataInFlight;

  TdlibFacade get td => _td;

  Stream<String?> get qrLoginPayload => _td.qrLoginPayload;

  Stream<TdlibCloudPasswordChallenge?> get cloudPasswordChallenge =>
      _td.cloudPasswordChallenge;

  Stream<TdlibSmsCodeChallenge?> get smsCodeChallenge => _td.smsCodeChallenge;

  Stream<bool> get authorizationWaitPhoneNumber =>
      _td.authorizationWaitPhoneNumber;

  Stream<int> get authenticatedUserId => _td.authenticatedUserId;

  Stream<String?> get functionErrors => _td.functionErrors;

  static Future<void> initPlugin() async {
    await TelegramTdlibFacade.initTdlibPlugin();
  }

  Future<void> initClient() async {
    await initPlugin();
    final apiId = int.tryParse(OxplayerEnv.telegramApiId ?? '') ?? 0;
    final apiHash = OxplayerEnv.telegramApiHash ?? '';
    if (apiId <= 0 || apiHash.isEmpty) {
      throw StateError(
        'Set TELEGRAM_API_ID and TELEGRAM_API_HASH in assets/env/default.env (or dart-define).',
      );
    }
    if (_clientInited) return;
    // [TelegramTdlibFacade] is a process-wide singleton. A second
    // [OxplayerTelegramTdSession] (bootstrap warm-up + Riverpod notifier) must not
    // call [init] again: [_performInit] shuts down the existing client first,
    // which emits AuthorizationStateClosed and can destabilize or crash the app.
    if (_td.isInitialized) {
      _clientInited = true;
      return;
    }
    await _td.init(apiId: apiId, apiHash: apiHash, sessionString: '');
    _clientInited = true;
  }

  /// Returns true when an on-disk TDLib session is already authorized.
  ///
  /// [ensureAuthorized] can otherwise block (e.g. 2FA password, slow GetMe) while the splash
  /// screen has no UI for that. Used only for a best-effort restore before falling back to HTTP.
  static const _kSilentRestoreMaxWait = Duration(seconds: 25);
  static const _kSilentRestoreFirstAttemptWait = Duration(seconds: 8);

  Future<bool> trySilentRestore() async {
    await initClient();
    try {
      await _td.ensureAuthorized().timeout(
        _kSilentRestoreMaxWait,
        onTimeout: () => throw TimeoutException('TDLib.ensureAuthorized', _kSilentRestoreMaxWait),
      );
      return true;
    } on TdlibInteractiveLoginRequired {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> trySilentRestoreWithRestart() async {
    await initClient();
    try {
      await _td.ensureAuthorized().timeout(
        _kSilentRestoreFirstAttemptWait,
        onTimeout: () => throw TimeoutException(
          'TDLib.ensureAuthorized first attempt',
          _kSilentRestoreFirstAttemptWait,
        ),
      );
      return true;
    } on TdlibInteractiveLoginRequired {
      return false;
    } on TimeoutException {
      debugPrint('[OX TDLib] silent restore timed out; restarting TDLib client once.');
      try {
        await _td.restartPreservingSession();
      } catch (e) {
        debugPrint('[OX TDLib] restartPreservingSession failed: $e');
      }
      _clientInited = false;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return trySilentRestore();
    } catch (e) {
      debugPrint('[OX TDLib] silent restore failed; restarting TDLib client once: $e');
      try {
        await _td.restartPreservingSession();
      } catch (_) {}
      _clientInited = false;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return trySilentRestore();
    }
  }

  /// Starts the TDLib authorization machine (QR / phone). Completes when the user is signed in to Telegram.
  Future<void> beginTelegramAuthorization() async {
    await initClient();
    try {
      await _td.ensureAuthorized();
    } on TdlibInteractiveLoginRequired {
      await _td.authenticatedUserId.first;
    }
  }

  Future<void> startQrLogin() async {
    debugPrint('[OX TDLib] startQrLogin: begin');
    await initClient();
    await _ensureFreshPhoneNumberGateForQrStart();
    await _waitForPhoneNumberState();
    debugPrint('[OX TDLib] startQrLogin: posting RequestQrCodeAuthentication to TDLib');
    try {
      await _td.startQrLogin();
    } catch (e) {
      if (!_isStaleTelegramAuthTokenError(e)) rethrow;
      debugPrint(
        '[OX TDLib] startQrLogin: stale auth token (${e is td_api.TdError ? e.message : e}) — resetting once.',
      );
      await resetLocalSessionForQrLogin();
      await initClient();
      await _waitForPhoneNumberState();
      await _td.startQrLogin();
    }
  }

  /// After a refresh, TDLib can resume mid-login (2FA, QR confirm). [RequestQrCodeAuthentication]
  /// is only valid from [td_api.AuthorizationStateWaitPhoneNumber]; clear local storage first.
  Future<void> abandonStaleInteractiveAuthIfNeeded() async {
    await initClient();
    final td_api.TdObject r;
    try {
      r = await _td
          .send(const td_api.GetAuthorizationState())
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return;
    }
    if (r is! td_api.AuthorizationState) return;
    final dirty = r is td_api.AuthorizationStateWaitPassword ||
        r is td_api.AuthorizationStateWaitCode ||
        r is td_api.AuthorizationStateWaitOtherDeviceConfirmation ||
        r is td_api.AuthorizationStateWaitEmailAddress ||
        r is td_api.AuthorizationStateWaitEmailCode ||
        r is td_api.AuthorizationStateWaitRegistration;
    if (!dirty) return;
    debugPrint(
      '[OX TDLib] abandonStaleInteractiveAuthIfNeeded: clearing partial login (${r.runtimeType})',
    );
    await resetLocalSessionForQrLogin();
    await initClient();
  }

  Future<void> _ensureFreshPhoneNumberGateForQrStart() async {
    td_api.TdObject r;
    try {
      r = await _td
          .send(const td_api.GetAuthorizationState())
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return;
    }
    if (r is td_api.AuthorizationStateWaitPhoneNumber) return;
    if (r is td_api.AuthorizationStateWaitTdlibParameters) {
      await _waitForPhoneNumberState();
      return;
    }
    debugPrint(
      '[OX TDLib] QR requires WaitPhoneNumber; saw ${r.runtimeType} — resetting local Telegram session.',
    );
    await resetLocalSessionForQrLogin();
    await initClient();
    await _waitForPhoneNumberState();
  }

  static bool _isStaleTelegramAuthTokenError(Object e) {
    final raw = e is td_api.TdError ? e.message : e.toString();
    final compact = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    return compact.contains('AUTH_TOKEN_ALREADY_ACCEPTED') ||
        compact.contains('AUTHTOKENALREADYACCEPTED') ||
        raw.toUpperCase().contains('ALREADY ACCEPTED');
  }

  Future<void> submitAuthenticationPhoneNumber(String phone) async {
    await _waitForPhoneNumberState();
    return _td.submitAuthenticationPhoneNumber(phone);
  }

  /// Waits until TDLib has observed [AuthorizationStateWaitPhoneNumber] for this client
  /// (see [TdlibFacade.hasReachedAuthorizationWaitPhoneNumber]), or until a timeout.
  ///
  /// On web, [authorizationWaitPhoneNumber] stream events can be missed while tdweb warms up;
  /// the controller also advances auth via `getAuthorizationState` polling.
  Future<void> _waitForPhoneNumberState() async {
    const step = Duration(milliseconds: 100);
    const maxWait = Duration(seconds: 16);
    final sw = Stopwatch()..start();
    if (_td.hasReachedAuthorizationWaitPhoneNumber) {
      debugPrint(
        '[OX TDLib] _waitForPhoneNumberState: gate already open (${sw.elapsedMilliseconds}ms)',
      );
      return;
    }
    debugPrint(
      '[OX TDLib] _waitForPhoneNumberState: polling hasReached (max ${maxWait.inSeconds}s)…',
    );
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      if (_td.hasReachedAuthorizationWaitPhoneNumber) {
        debugPrint(
          '[OX TDLib] _waitForPhoneNumberState: gate open after ${sw.elapsedMilliseconds}ms',
        );
        return;
      }
      await Future<void>.delayed(step);
    }
    debugPrint(
      '[OX TDLib] _waitForPhoneNumberState: timeout after ${sw.elapsedMilliseconds}ms '
      '(hasReached=${_td.hasReachedAuthorizationWaitPhoneNumber}) — proceeding anyway',
    );
  }

  Future<void> submitAuthenticationCode(String code) =>
      _td.submitAuthenticationCode(code);

  Future<void> submitCloudPassword(String password) =>
      _td.submitCloudPassword(password);

  Future<void> resetLocalSessionForQrLogin() async {
    _clientInited = false;
    // Use forceDestroyAfterLogOut (kill isolate first, then destroy) to avoid
    // the native crash where tdJsonClientDestroy races with a 1-second
    // tdJsonClientReceive poll that is still in flight in the receive isolate.
    if (_td.isInitialized) {
      await _td.forceDestroyAfterLogOut();
    }
  }

  /// Signs out from Telegram by sending [LogOut] to revoke the device session
  /// on Telegram's servers. Then safely destroys the TDLib client by killing
  /// the receive isolate first (prevents the native tdJsonClientDestroy crash).
  Future<void> signOut() async {
    if (_td.isInitialized) {
      try {
        // Revoke server-side device session.
        await _td.send(const td_api.LogOut());
        // Brief delay so TDLib can process LogOut before we destroy.
        await Future<void>.delayed(const Duration(milliseconds: 400));
      } catch (_) {
        // Ignore — session may already be invalid.
      }
      // Kill isolate first, wait for receive drain, then destroy safely.
      await _td.forceDestroyAfterLogOut();
    }
    _clientInited = false;
  }

  Future<void> dispose() => _td.dispose();

  /// Ensures TDLib is initialized and authorized (for library Telegram playback).
  static Future<bool> ensureReadyForPlayback() async {
    try {
      final s = OxplayerTelegramTdSession();
      await s.initClient();
      await s.td.ensureAuthorized();
      return true;
    } on TdlibInteractiveLoginRequired {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// TDLib [chatId] of the private chat with [OxplayerEnv.botUsername], or `null` if unconfigured
  /// or the bot could not be resolved (same resolution path as [fetchSignedInitData]).
  Future<int?> resolveMainBotPrivateChatId() async {
    try {
      await _td.ensureAuthorized();
    } catch (_) {
      return null;
    }
    final botUser = OxplayerEnv.botUsername;
    if (botUser == null || botUser.isEmpty) {
      return null;
    }
    final resolved = await _td.send(td_api.SearchPublicChat(username: botUser));
    if (resolved is! td_api.Chat || resolved.type is! td_api.ChatTypePrivate) {
      return null;
    }
    final botUserId = (resolved.type as td_api.ChatTypePrivate).userId;
    final privateChat = await _td.send(
      td_api.CreatePrivateChat(userId: botUserId, force: false),
    );
    if (privateChat is! td_api.Chat) {
      return null;
    }
    return privateChat.id;
  }

  /// Same pipeline as oxplayer-android [DataRepository._fetchSignedInitData]: TDLib obtains signed WebApp initData.
  Future<String> fetchSignedInitData() async {
    final existing = _signedInitDataInFlight;
    if (existing != null) return existing;
    final created = _fetchSignedInitDataImpl();
    _signedInitDataInFlight = created;
    try {
      return await created;
    } finally {
      _signedInitDataInFlight = null;
    }
  }

  Future<String> _fetchSignedInitDataImpl() async {
    await _td.ensureAuthorized();
    final botUser = OxplayerEnv.botUsername;
    if (botUser == null || botUser.isEmpty) {
      throw StateError('BOT_USERNAME (or OXPLAYER_BOT_USERNAME) is not configured.');
    }

    final initDbg = OxplayerEnv.telegramWebAppInitDataDebugOverride;
    if (initDbg != null && initDbg.isNotEmpty) {
      oxEnvLog(
        'fetchSignedInitData: OXPLAYER_DEBUG_TELEGRAM_INIT_DATA set (web debug bypass; skips GetWebApp*)',
      );
      return initDbg;
    }

    final resolved =
        await _td.send(td_api.SearchPublicChat(username: botUser));
    if (resolved is! td_api.Chat || resolved.type is! td_api.ChatTypePrivate) {
      throw StateError('Cannot resolve BOT_USERNAME to a private chat with the bot.');
    }
    final botUserId = (resolved.type as td_api.ChatTypePrivate).userId;

    final privateChat = await _td.send(
      td_api.CreatePrivateChat(userId: botUserId, force: false),
    );
    if (privateChat is! td_api.Chat) {
      throw StateError('Failed to create private chat with bot');
    }

    String? webAppUrl;
    td_api.TdError? shortNameError;
    td_api.TdError? fallbackUrlError;
    String? otherFailure;

    final shortName = OxplayerEnv.telegramWebAppShortName?.trim() ?? '';

    var fallbackUrl = OxplayerEnv.telegramWebAppUrl ?? '';
    if (fallbackUrl.isEmpty) {
      fallbackUrl = OxplayerEnv.telegramMiniAppOpenLink ?? '';
    }
    fallbackUrl = OxplayerEnv.compactTelegramWireUrl(fallbackUrl);

    if (kIsWeb) {
      // tdweb pin may omit [getWebAppLinkUrl] and [getWebAppUrl]; [getMainWebApp] is older.
      const params = td_api.WebAppOpenParameters(theme: null, applicationName: 'oxplayer');
      final webErrs = <String>[];
      Future<String?> sendWeb(td_api.TdFunction fn) async {
        try {
          final r = await _td.send(fn).timeout(const Duration(seconds: 25));
          if (r is td_api.HttpUrl) {
            return r.url;
          }
          if (r is td_api.MainWebApp) {
            final u = r.url.trim();
            if (u.isNotEmpty) {
              return u;
            }
          }
        } on td_api.TdError catch (e) {
          webErrs.add('${fn.runtimeType}: ${e.message} (${e.code})');
        } catch (e) {
          webErrs.add('${fn.runtimeType}: ${_describeTdSendFailure(e)}');
        }
        return null;
      }

      if (shortName.isNotEmpty) {
        webAppUrl = await sendWeb(
          td_api.GetMainWebApp(
            chatId: privateChat.id,
            botUserId: botUserId,
            startParameter: shortName,
            parameters: params,
          ),
        );
      }
      webAppUrl ??= await sendWeb(
        td_api.GetMainWebApp(
          chatId: privateChat.id,
          botUserId: botUserId,
          startParameter: '',
          parameters: params,
        ),
      );
      if (webAppUrl == null && fallbackUrl.isNotEmpty) {
        webAppUrl = await sendWeb(
          td_api.GetWebAppUrl(
            botUserId: botUserId,
            url: fallbackUrl,
            parameters: params,
          ),
        );
      }
      if (webAppUrl == null && webErrs.isNotEmpty) {
        otherFailure = webErrs.join(' | ');
      }
    } else {
      // Native tdlib-json: [getWebAppLinkUrl] then [getWebAppUrl].
      if (shortName.isNotEmpty) {
        for (var attempt = 0; attempt < 2 && webAppUrl == null; attempt++) {
          try {
            final result = await _td.send(
              td_api.GetWebAppLinkUrl(
                chatId: privateChat.id,
                botUserId: botUserId,
                webAppShortName: shortName,
                startParameter: '',
                allowWriteAccess: true,
                parameters: const td_api.WebAppOpenParameters(
                  theme: null,
                  applicationName: 'oxplayer',
                ),
              ),
            );
            if (result is td_api.HttpUrl) {
              webAppUrl = result.url;
            }
          } catch (e) {
            if (attempt == 0 && _isStaleTelegramAuthTokenError(e)) {
              await Future<void>.delayed(const Duration(milliseconds: 450));
              continue;
            }
            if (e is td_api.TdError) {
              shortNameError = e;
            } else {
              otherFailure ??= _describeTdSendFailure(e);
            }
          }
        }
      }

      if (webAppUrl == null && fallbackUrl.isNotEmpty) {
        for (var attempt = 0; attempt < 2 && webAppUrl == null; attempt++) {
          try {
            final fallbackResult = await _td.send(
              td_api.GetWebAppUrl(
                botUserId: botUserId,
                url: fallbackUrl,
                parameters: const td_api.WebAppOpenParameters(
                  theme: null,
                  applicationName: 'oxplayer',
                ),
              ),
            );
            if (fallbackResult is td_api.HttpUrl) {
              webAppUrl = fallbackResult.url;
            }
          } catch (e) {
            if (attempt == 0 && _isStaleTelegramAuthTokenError(e)) {
              await Future<void>.delayed(const Duration(milliseconds: 450));
              continue;
            }
            if (e is td_api.TdError) {
              fallbackUrlError = e;
            } else {
              otherFailure ??= _describeTdSendFailure(e);
            }
          }
        }
      }
    }

    if (webAppUrl == null) {
      const tdwebSyncHint =
          'On web, sync tdweb to tool/tdlib/TD_VERSION.json (see web/tdweb/README). '
          'Debug-only: OXPLAYER_DEBUG_TELEGRAM_INIT_DATA when kDebugMode.';
      final short = OxplayerEnv.telegramWebAppShortName?.trim() ?? '';
      final directUrl = OxplayerEnv.telegramWebAppUrl ?? '';
      final mini = OxplayerEnv.compactTelegramWireUrl(
        OxplayerEnv.telegramMiniAppOpenLink ?? '',
      );
      if (shortNameError != null || fallbackUrlError != null || otherFailure != null) {
        final b = StringBuffer('Cannot get WebApp URL from Telegram.');
        if (shortNameError != null) {
          b.write(
            ' GetWebAppLinkUrl: ${shortNameError.message} (code ${shortNameError.code}).',
          );
        }
        if (fallbackUrlError != null) {
          b.write(
            ' GetWebAppUrl: ${fallbackUrlError.message} (code ${fallbackUrlError.code}).',
          );
        }
        if (otherFailure != null) {
          b.write(' $otherFailure');
        }
        b.write(
          ' short_name="$short" mini="$mini" dotenv=${OxplayerDotenv.isLoaded}.',
        );
        if (kIsWeb) {
          b.write(' $tdwebSyncHint');
        }
        throw StateError(b.toString());
      }
      throw StateError(
        'Cannot get WebApp URL from Telegram (TDLib returned no URL and no error). '
        'short_name="$short" direct_url_set=${directUrl.isNotEmpty} mini="$mini" '
        'dotenv=${OxplayerDotenv.isLoaded}. Use pnpm flutter:web or '
        '--dart-define-from-file=dart_defines.dev.json.'
        '${kIsWeb ? ' $tdwebSyncHint' : ''}',
      );
    }

    final initData = _extractTgWebAppData(webAppUrl);
    if (initData == null || initData.isEmpty) {
      throw StateError('tgWebAppData not found in WebApp URL from Telegram.');
    }
    return initData;
  }

  static String? _extractTgWebAppData(String webAppUrl) {
    final uri = Uri.tryParse(webAppUrl);
    if (uri == null) return null;
    final fromQuery = _extractQueryParamRaw(query: uri.query, key: 'tgWebAppData');
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      final queryFromFragment =
          fragment.contains('?') ? fragment.substring(fragment.indexOf('?') + 1) : fragment;
      final fromFragment =
          _extractQueryParamRaw(query: queryFromFragment, key: 'tgWebAppData');
      if (fromFragment != null && fromFragment.isNotEmpty) return fromFragment;
    }
    return null;
  }

  static String? _extractQueryParamRaw({required String query, required String key}) {
    if (query.isEmpty) return null;
    for (final pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final rawKey = eq >= 0 ? pair.substring(0, eq) : pair;
      final decodedKey = _decodeComponentSafe(rawKey);
      if (decodedKey != key) continue;
      final rawValue = eq >= 0 ? pair.substring(eq + 1) : '';
      return _decodeComponentSafe(rawValue);
    }
    return null;
  }

  static String _decodeComponentSafe(String input) {
    if (input.isEmpty) return input;
    try {
      return Uri.decodeComponent(input);
    } catch (_) {
      return input;
    }
  }

  static Future<({String deviceId, String? deviceName})> resolveDeviceIdentity({
    required String defaultDeviceName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var storedId = prefs.getString(_kOxDeviceIdPrefsKey)?.trim() ?? '';
    if (storedId.isEmpty) {
      storedId = _generateDeviceId();
      await prefs.setString(_kOxDeviceIdPrefsKey, storedId);
    }
    return (deviceId: storedId, deviceName: defaultDeviceName);
  }

  static String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'oxa-$hex';
  }

  Future<OxplayerTelegramAuthResponse> authenticateWithOxApi({
    required String deviceName,
  }) async {
    final apiBase = OxplayerEnv.apiBaseUrl;
    if (apiBase == null) {
      throw StateError('OXPLAYER_API_BASE_URL is not configured.');
    }
    final initData = await fetchSignedInitData();
    final identity = await resolveDeviceIdentity(defaultDeviceName: deviceName);
    final client = OxplayerTelegramAuthClient(apiBase: apiBase);
    return client.exchangeInitData(
      initData: initData,
      deviceId: identity.deviceId,
      deviceName: identity.deviceName,
    );
  }
}
