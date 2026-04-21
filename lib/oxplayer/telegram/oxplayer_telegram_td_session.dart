import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tdlib/td_api.dart' as td_api;

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';

import 'oxplayer_telegram_td_runtime.dart';
import 'tdlib_controller.dart' if (dart.library.html) 'tdlib_controller_web.dart';
import 'tdlib_facade.dart';

const _kOxDeviceIdPrefsKey = 'oxplayer_td_device_id';

/// TDLib-backed Telegram login + the same backend `/auth/telegram` bridge as oxplayer-android.
final class OxplayerTelegramTdSession {
  OxplayerTelegramTdSession({TelegramTdlibFacade? tdlib}) : _td = tdlib ?? OxplayerTelegramTdRuntime.facade;

  final TelegramTdlibFacade _td;
  bool _clientInited = false;

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
    if (kIsWeb) return;
    await TelegramTdlibFacade.initTdlibPlugin();
  }

  Future<void> initClient() async {
    if (kIsWeb) {
      throw UnsupportedError('Telegram TDLib sign-in is not available on web.');
    }
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
  Future<bool> trySilentRestore() async {
    if (kIsWeb) return false;
    await initClient();
    try {
      await _td.ensureAuthorized();
      return true;
    } on TdlibInteractiveLoginRequired {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Starts the TDLib authorization machine (QR / phone). Completes when the user is signed in to Telegram.
  Future<void> beginTelegramAuthorization() async {
    if (kIsWeb) {
      throw UnsupportedError('Telegram TDLib sign-in is not available on web.');
    }
    await initClient();
    try {
      await _td.ensureAuthorized();
    } on TdlibInteractiveLoginRequired {
      await _td.authenticatedUserId.first;
    }
  }

  Future<void> startQrLogin() => _td.startQrLogin();

  Future<void> submitAuthenticationPhoneNumber(String phone) =>
      _td.submitAuthenticationPhoneNumber(phone);

  Future<void> submitAuthenticationCode(String code) =>
      _td.submitAuthenticationCode(code);

  Future<void> submitCloudPassword(String password) =>
      _td.submitCloudPassword(password);

  Future<void> resetLocalSessionForQrLogin() async {
    _clientInited = false;
    await _td.resetLocalSessionForQrLogin();
  }

  Future<void> dispose() => _td.dispose();

  /// Ensures TDLib is initialized and authorized (for library Telegram playback).
  static Future<bool> ensureReadyForPlayback() async {
    if (kIsWeb) return false;
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

  /// Same pipeline as oxplayer-android [DataRepository._fetchSignedInitData]: TDLib obtains signed WebApp initData.
  Future<String> fetchSignedInitData() async {
    await _td.ensureAuthorized();
    final botUser = OxplayerEnv.botUsername;
    if (botUser == null || botUser.isEmpty) {
      throw StateError('BOT_USERNAME (or OXPLAYER_BOT_USERNAME) is not configured.');
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

    final shortName = OxplayerEnv.telegramWebAppShortName?.trim() ?? '';
    if (shortName.isNotEmpty) {
      try {
        final result = await _td.send(
          td_api.GetWebAppLinkUrl(
            chatId: privateChat.id,
            botUserId: botUserId,
            webAppShortName: shortName,
            startParameter: '',
            theme: null,
            applicationName: 'oxplayer',
            allowWriteAccess: true,
          ),
        );
        if (result is td_api.HttpUrl) {
          webAppUrl = result.url;
        }
      } catch (e) {
        if (e is td_api.TdError) shortNameError = e;
      }
    }

    final fallbackUrl = OxplayerEnv.telegramWebAppUrl?.trim() ?? '';
    if (webAppUrl == null && fallbackUrl.isNotEmpty) {
      final fallbackResult = await _td.send(
        td_api.GetWebAppUrl(
          botUserId: botUserId,
          url: fallbackUrl,
          theme: null,
          applicationName: 'oxplayer',
        ),
      );
      if (fallbackResult is td_api.HttpUrl) {
        webAppUrl = fallbackResult.url;
      }
    }

    if (webAppUrl == null) {
      if (shortNameError != null) {
        throw StateError(
          'WebApp initData failed (${shortNameError.message}). '
          'Configure OXPLAYER_TELEGRAM_WEBAPP_SHORT_NAME or OXPLAYER_TELEGRAM_WEBAPP_URL.',
        );
      }
      throw StateError(
        'Cannot get WebApp URL. Set OXPLAYER_TELEGRAM_WEBAPP_SHORT_NAME or OXPLAYER_TELEGRAM_WEBAPP_URL.',
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
