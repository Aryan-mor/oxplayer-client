import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_debug.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/util/normalize_url.dart';

/// VM / desktop / mobile: same URL sync as legacy [OxplayerPersistedUrlSync], using [AccountModel].
Future<void> syncAccountsIfNeededNative(SharedPreferences prefs) async {
  if (!OxplayerConfig.isEnabled) return;
  final envRaw = OxplayerEnv.effectiveMediaServerUrl;
  if (envRaw == null || envRaw.trim().isEmpty) return;

  final nEnv = normalizeUrl(envRaw);
  if (nEnv.isEmpty) return;

  const loginCredentialsPrefsKey = 'loginCredentialsKey';

  final list = prefs.getStringList(loginCredentialsPrefsKey);
  if (list == null || list.isEmpty) return;

  final out = <String>[];
  var anyChanged = false;

  for (final jsonStr in list) {
    try {
      final account = AccountModel.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      final cred = account.credentials;
      final oldUrlNorm = normalizeUrl(cred.url);
      final oldLocal = cred.localUrl?.trim() ?? '';
      final oldLocalNorm = oldLocal.isNotEmpty ? normalizeUrl(oldLocal) : '';

      var newCred = cred;

      if (oldUrlNorm.isNotEmpty && oldUrlNorm != nEnv) {
        newCred = newCred.copyWith(url: nEnv);
        anyChanged = true;
        oxEnvLog(
          'Oxplayer URL sync: ${account.name} credentials.url '
          '$oldUrlNorm -> $nEnv',
        );
      }

      if (oldLocalNorm.isNotEmpty && oldLocalNorm != nEnv) {
        final clearLocal =
            oldLocalNorm == oldUrlNorm || oldLocal.toLowerCase().contains('ngrok');
        if (clearLocal) {
          newCred = newCred.copyWith(localUrl: null);
          anyChanged = true;
          oxEnvLog(
            'Oxplayer URL sync: ${account.name} cleared localUrl '
            '($oldLocalNorm)',
          );
        }
      }

      final updated = newCred == cred ? account : account.copyWith(credentials: newCred);
      out.add(jsonEncode(updated.toJson()));
    } catch (_) {
      out.add(jsonStr);
    }
  }

  if (anyChanged) {
    await prefs.setStringList(loginCredentialsPrefsKey, out);
  }
}
