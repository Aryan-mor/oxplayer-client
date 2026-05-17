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
