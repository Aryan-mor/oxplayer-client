import 'dart:async';

/// Single-flight mutex for OX session refresh (splash gate, background refresh, 401 handler).
///
/// `POST /auth/refresh` rotates access + refresh tokens server-side; concurrent refreshes
/// invalidate in-flight Jellyfin requests and can strand the UI on "Refreshing session".
Future<void>? _sessionRefreshMutex;

DateTime? _lastSessionRefreshCompletedAt;

/// Splash or login just established a valid session; skip redundant background token rotation.
bool _sessionEstablishedThisProcess = false;

void oxplayerNoteSessionEstablished() {
  _sessionEstablishedThisProcess = true;
  oxplayerNoteSessionRefreshCompleted();
}

void oxplayerClearSessionEstablished() {
  _sessionEstablishedThisProcess = false;
  _lastSessionRefreshCompletedAt = null;
}

bool get oxplayerSessionEstablishedThisProcess => _sessionEstablishedThisProcess;

void oxplayerNoteSessionRefreshCompleted() {
  _lastSessionRefreshCompletedAt = DateTime.now();
}

bool oxplayerSessionRefreshCompletedRecently([
  Duration window = const Duration(seconds: 15),
]) {
  final completed = _lastSessionRefreshCompletedAt;
  return completed != null && DateTime.now().difference(completed) < window;
}

Future<void> oxplayerWaitForExclusiveSessionRefresh() async {
  final waiting = _sessionRefreshMutex;
  if (waiting != null) {
    await waiting;
  }
}

Future<T> oxplayerWithExclusiveSessionRefresh<T>(Future<T> Function() run) async {
  while (true) {
    final waiting = _sessionRefreshMutex;
    if (waiting != null) {
      await waiting;
      continue;
    }

    final gate = Completer<void>();
    _sessionRefreshMutex = gate.future;
    try {
      final result = await run();
      oxplayerNoteSessionRefreshCompleted();
      return result;
    } finally {
      gate.complete();
      if (identical(_sessionRefreshMutex, gate.future)) {
        _sessionRefreshMutex = null;
      }
    }
  }
}
