import 'dart:async';

import 'package:fladder/td_api_generated/td_api.dart' as td;

class TdlibInteractiveLoginRequired implements Exception {
  const TdlibInteractiveLoginRequired();

  @override
  String toString() => 'Telegram session is not ready yet.';
}

class TdlibCloudPasswordChallenge {
  const TdlibCloudPasswordChallenge({required this.hint});

  final String hint;
}

class TdlibSmsCodeChallenge {
  const TdlibSmsCodeChallenge({
    required this.phoneNumber,
    required this.resendTimeoutSeconds,
  });

  final String phoneNumber;
  final int resendTimeoutSeconds;
}

abstract class TdTelegramClient {
  bool get isInitialized;

  /// True after TDLib has entered [AuthorizationStateWaitPhoneNumber] at least once
  /// for the current client (stream listeners may have missed the first `true`).
  bool get hasReachedAuthorizationWaitPhoneNumber;

  Future<void> init({
    required int apiId,
    required String apiHash,
    required String sessionString,
  });

  Future<void> ensureAuthorized();

  Stream<Map<String, dynamic>> updates();

  Future<td.TdObject> send(td.TdFunction request);

  Stream<String?> get qrLoginPayload;

  Stream<TdlibCloudPasswordChallenge?> get cloudPasswordChallenge;

  Stream<TdlibSmsCodeChallenge?> get smsCodeChallenge;

  Stream<bool> get authorizationWaitPhoneNumber;

  Stream<int> get authenticatedUserId;

  Stream<String?> get functionErrors;

  Future<void> startQrLogin();

  Future<void> submitCloudPassword(String password);

  Future<void> submitAuthenticationPhoneNumber(String phoneNumber);

  Future<void> submitAuthenticationCode(String code);

  Future<void> resetLocalSessionForQrLogin();

  Future<void> restartPreservingSession();

  Future<void> forceDestroyAfterLogOut();

  Future<void> dispose();
}

/// Historical name; prefer [TdTelegramClient].
typedef TdlibFacade = TdTelegramClient;

/// Expected control-flow signal: TDLib needs QR / phone / 2FA (not a crash).
bool isTdlibInteractiveLoginRequired(Object? error) =>
    error is TdlibInteractiveLoginRequired;

/// After a timeout or UI bail-out, the caller no longer awaits [future]; swallow
/// late async errors (e.g. [TdlibInteractiveLoginRequired]) so they are not reported as crashes.
void detachFutureErrors(Future<dynamic> future) {
  unawaited(future.then<void>((_) {}, onError: (_, __) {}));
}

/// Awaits [future] up to [timeout]. On timeout, [onTimeout] runs and [future] is detached.
Future<T> awaitFutureWithTimeout<T>(
  Future<T> future,
  Duration timeout, {
  required T Function() onTimeout,
}) {
  return future.timeout(
    timeout,
    onTimeout: () {
      detachFutureErrors(future);
      return onTimeout();
    },
  );
}

/// Awaits [TdTelegramClient.ensureAuthorized], optionally bounded by [timeout].
///
/// When [timeout] fires first, the underlying [ensureAuthorized] future is still
/// active; late [TdlibInteractiveLoginRequired] errors are swallowed so they do
/// not surface as unhandled async errors on [PlatformDispatcher.onError].
Future<void> awaitTdEnsureAuthorized(
  TdTelegramClient td, {
  Duration? timeout,
}) async {
  final auth = td.ensureAuthorized();
  if (timeout == null) {
    await auth;
    return;
  }
  try {
    await auth.timeout(timeout);
  } on TimeoutException {
    detachFutureErrors(auth);
    rethrow;
  }
}
