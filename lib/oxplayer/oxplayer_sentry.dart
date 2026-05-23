import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';

/// Optional crash reporting via [Sentry](https://sentry.io). Disabled when [OxplayerEnv.sentryDsn] is empty.
abstract final class OxplayerSentry {
  static const String _cGitCommit = String.fromEnvironment('GIT_COMMIT');

  /// `true` when a DSN is configured (dotenv or dart-define).
  static bool get isActive => OxplayerEnv.sentryDsn != null;

  /// Runs [body] inside [SentryFlutter.init] when [isActive]; otherwise runs [body] directly.
  static Future<void> runApp(Future<void> Function() body) async {
    if (!isActive) {
      await body();
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    await SentryFlutter.init(
      (options) => _configure(options, packageInfo),
      appRunner: body,
    );
  }

  /// Chain Sentry onto handlers installed by [CrashLogNotifier] (runs after bootstrap).
  static void wrapCrashHandlers() {
    if (!isActive) return;

    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      prevFlutter?.call(details);
      unawaited(
        Sentry.captureException(
          details.exception,
          stackTrace: details.stack,
        ),
      );
    };

    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      final handled = prevPlatform?.call(error, stack) ?? false;
      unawaited(Sentry.captureException(error, stackTrace: stack));
      return handled;
    };
  }

  static void _configure(SentryFlutterOptions options, PackageInfo packageInfo) {
    options.dsn = OxplayerEnv.sentryDsn;
    options.environment = OxplayerEnv.sentryEnvironment;
    options.tracesSampleRate = OxplayerEnv.sentryTracesSampleRate;
    options.debug = OxplayerEnv.sentryDebug;
    options.attachStacktrace = true;
    options.enableAutoSessionTracking = false;
    options.recordHttpBreadcrumbs = false;
    options.captureNativeFailedRequests = false;
    options.beforeSend = _beforeSend;
    options.release = _releaseName(packageInfo);
  }

  static String _releaseName(PackageInfo packageInfo) {
    final commit = _cGitCommit.trim();
    if (commit.isNotEmpty) {
      final short = commit.length > 7 ? commit.substring(0, 7) : commit;
      return 'oxplayer-client@$short';
    }
    return 'oxplayer-client@${packageInfo.version}+${packageInfo.buildNumber}';
  }

  static FutureOr<SentryEvent?> _beforeSend(SentryEvent event, Hint _) {
    if (_eventContainsSecret(event)) return null;
    return event;
  }

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
