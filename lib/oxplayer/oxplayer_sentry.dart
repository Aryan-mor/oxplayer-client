import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_debug.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';

/// Optional crash reporting via [Sentry](https://sentry.io). Disabled when [OxplayerEnv.sentryDsn] is empty.
abstract final class OxplayerSentry {
  static const String _cGitCommit = String.fromEnvironment('GIT_COMMIT');

  static bool _handlersWrapped = false;

  /// `true` when a DSN is configured (dotenv or dart-define).
  static bool get isActive => OxplayerEnv.sentryDsn != null;

  /// Log whether Sentry will init (filter Logcat / console by `OX_ENV`).
  static void logStartupStatus() {
    final dsn = OxplayerEnv.sentryDsn;
    oxEnvLog(
      'Sentry startup: active=$isActive environment=${OxplayerEnv.sentryEnvironment} '
      'dotenvLoaded=${OxplayerDotenv.isLoaded} dotenvKeys=${OxplayerDotenv.keyCount} '
      'dsnConfigured=${dsn != null} dsnLength=${dsn?.length ?? 0}',
    );
  }

  /// Runs [body] inside [SentryFlutter.init] when [isActive]; otherwise runs [body] directly.
  static Future<void> runApp(Future<void> Function() body) async {
    logStartupStatus();
    if (!isActive) {
      await body();
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    try {
      await SentryFlutter.init(
        (options) => _configure(options, packageInfo),
        appRunner: body,
      );
      oxEnvLog('SentryFlutter.init completed');
    } catch (e, stack) {
      oxEnvLog('SentryFlutter.init failed: $e\n$stack');
      await body();
    }
  }

  /// Chain OX crash filters (and Sentry when [isActive]) after [CrashLogNotifier].
  static void wrapCrashHandlers() {
    if (_handlersWrapped) return;
    _handlersWrapped = true;

    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      prevFlutter?.call(details);
      if (!isActive || _shouldDropError(details.exception)) return;
      unawaited(
        Sentry.captureException(
          details.exception,
          stackTrace: details.stack,
        ),
      );
    };

    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      // Expected when splash silent-restore times out before TDLib needs login UI.
      if (_shouldDropError(error)) {
        return true;
      }
      final handled = prevPlatform?.call(error, stack) ?? false;
      if (isActive) {
        unawaited(Sentry.captureException(error, stackTrace: stack));
      }
      return handled;
    };
    oxEnvLog(
      'OX platform error handler chained after CrashLogNotifier (sentry=$isActive)',
    );
  }

  /// Sends a one-off test event when [OxplayerEnv.sentryDebug] is on (dev wiring check).
  static Future<void> debugPingIfEnabled() async {
    if (!kDebugMode || !isActive || !OxplayerEnv.sentryDebug) return;
    try {
      final id = await Sentry.captureException(
        StateError('OXPlayer Sentry dev ping'),
        stackTrace: StackTrace.current,
      );
      oxEnvLog('Sentry dev ping eventId=$id');
    } catch (e, stack) {
      oxEnvLog('Sentry dev ping failed: $e\n$stack');
    }
  }

  /// Hidden About → Error logs long-press: test Sentry in release/production builds.
  ///
  /// Returns the Sentry event id when sent, or `null` when the DSN is not configured.
  static Future<String?> sendProductionTestPing() async {
    if (!isActive) return null;
    final id = await Sentry.captureException(
      StateError('OXPlayer Sentry production test ping'),
      stackTrace: StackTrace.current,
    );
    oxEnvLog('Sentry production test ping eventId=$id');
    return id.toString();
  }

  static void _configure(SentryFlutterOptions options, PackageInfo packageInfo) {
    options.dsn = OxplayerEnv.sentryDsn;
    options.environment = OxplayerEnv.sentryEnvironment;
    // Required for transactions, route TTID/TTFD, and HTTP child spans.
    options.tracesSampleRate = OxplayerEnv.sentryTracesSampleRate;
    if ((options.tracesSampleRate ?? 0) <= 0) {
      options.tracesSampleRate = kDebugMode ? 1.0 : 0.1;
    }
    options.debug = OxplayerEnv.sentryDebug;
    options.enableLogs = OxplayerEnv.sentryDebug;
    options.attachStacktrace = true;
    options.enableAutoSessionTracking = false;
    options.recordHttpBreadcrumbs = false;
    options.captureNativeFailedRequests = false;
    options.enableAutoPerformanceTracing = true;
    options.enableTimeToFullDisplayTracing = true;
    options.beforeSend = _beforeSend;
    options.release = _releaseName(packageInfo);
    options.dist = packageInfo.buildNumber;
  }

  static String _releaseName(PackageInfo packageInfo) {
    final commit = _cGitCommit.trim();
    if (commit.isNotEmpty) {
      final short = commit.length > 7 ? commit.substring(0, 7) : commit;
      return 'oxplayer-client@$short';
    }
    return 'oxplayer-client@${packageInfo.version}+${packageInfo.buildNumber}';
  }

  static FutureOr<SentryEvent?> _beforeSend(SentryEvent event, Hint hint) {
    if (_eventContainsSecret(event)) return null;
    if (_shouldDropError(event.throwable) || _eventIsBenignControlFlow(event)) {
      return null;
    }
    return event;
  }

  static bool _shouldDropError(Object? error) {
    if (isTdlibInteractiveLoginRequired(error)) return true;
    return _isBenignNetworkError(error);
  }

  /// Offline DNS / GitHub release check failures are not app defects.
  static bool _isBenignNetworkError(Object? error) {
    if (error is SocketException) return true;
    if (error is OSError && _textLooksLikeOfflineHost(error.message)) {
      return true;
    }
    if (error is http.ClientException && _textLooksLikeGithubReleaseCheck(error.message)) {
      return true;
    }
    return false;
  }

  static bool _eventIsBenignControlFlow(SentryEvent event) {
    for (final e in event.exceptions ?? const <SentryException>[]) {
      if (_exceptionLooksLikeTdLoginRequired(e.type, e.value)) return true;
      if (_exceptionLooksLikeBenignNetwork(e.type, e.value)) return true;
    }
    final message = event.message?.formatted;
    if (message != null) {
      if (_textLooksLikeTdLoginRequired(message)) return true;
      if (_textLooksLikeGithubReleaseCheck(message) ||
          _textLooksLikeOfflineHost(message)) {
        return true;
      }
    }
    return false;
  }

  static bool _exceptionLooksLikeBenignNetwork(String? type, String? value) {
    if (type == 'SocketException' || type == 'ClientException') return true;
    if (value != null &&
        (_textLooksLikeGithubReleaseCheck(value) || _textLooksLikeOfflineHost(value))) {
      return true;
    }
    return false;
  }

  static bool _textLooksLikeOfflineHost(String text) {
    final lower = text.toLowerCase();
    return lower.contains('no address associated with hostname') ||
        lower.contains('failed host lookup');
  }

  static bool _textLooksLikeGithubReleaseCheck(String text) =>
      text.contains('api.github.com') && text.contains('releases');

  static bool _exceptionLooksLikeTdLoginRequired(String? type, String? value) {
    if (type == 'TdlibInteractiveLoginRequired') return true;
    if (value != null && _textLooksLikeTdLoginRequired(value)) return true;
    return false;
  }

  static bool _textLooksLikeTdLoginRequired(String text) =>
      text.contains('Telegram session is not ready yet') ||
      text.contains('TdlibInteractiveLoginRequired');

  static bool _eventContainsSecret(SentryEvent event) {
    final message = event.message?.formatted;
    if (message != null && _containsSecret(message)) return true;
    for (final e in event.exceptions ?? const <SentryException>[]) {
      final v = e.value;
      if (v != null && _containsSecret(v)) return true;
    }
    return false;
  }

  static bool _containsSecret(String value) {
    final lower = value.toLowerCase();
    return lower.contains('mediabrowser token=') ||
        lower.contains('authorization:') ||
        lower.contains('initdata=') ||
        lower.contains('telegram_api_hash') ||
        lower.contains('access_token');
  }
}
