import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_debug.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/util/normalize_url.dart';

/// Web-only URL alignment for saved Jellyfin accounts.
///
/// Mutates persisted JSON as [Map]s only — no [AccountModel] / [CredentialsModel] / Freezed
/// graph (avoids transitive imports that touch native I/O during bootstrap).
abstract final class OxplayerWebUrlSync {
  /// Must match [SharedKeys.loginCredentialsKey] in `shared_provider.dart`.
  static const String _loginCredentialsPrefsKey = 'loginCredentialsKey';

  static Future<void> syncAccountsIfNeeded(SharedPreferences prefs) async {
    if (!OxplayerConfig.isEnabled) return;
    final envRaw = OxplayerEnv.effectiveMediaServerUrl;
    if (envRaw == null || envRaw.trim().isEmpty) return;

    final nEnv = normalizeUrl(envRaw);
    if (nEnv.isEmpty) return;

    final list = prefs.getStringList(_loginCredentialsPrefsKey);
    if (list == null || list.isEmpty) return;

    final out = <String>[];
    var anyChanged = false;

    for (final jsonStr in list) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is! Map) {
          out.add(jsonStr);
          continue;
        }
        final root = Map<String, dynamic>.from(decoded);
        final credObj = root['credentials'];
        final credMap = _credentialsAsMap(credObj);
        if (credMap == null) {
          out.add(jsonStr);
          continue;
        }

        final urlRaw = (credMap['url'] as String?) ?? '';
        final oldUrlNorm = normalizeUrl(urlRaw);
        final oldLocal = (credMap['localUrl'] as String?)?.trim() ?? '';
        final oldLocalNorm = oldLocal.isNotEmpty ? normalizeUrl(oldLocal) : '';

        var changed = false;

        if (oldUrlNorm.isNotEmpty && oldUrlNorm != nEnv) {
          credMap['url'] = nEnv;
          changed = true;
          final name = (root['name'] as String?) ?? '';
          oxEnvLog('Oxplayer URL sync (web): $name credentials.url $oldUrlNorm -> $nEnv');
        }

        if (oldLocalNorm.isNotEmpty && oldLocalNorm != nEnv) {
          final clearLocal =
              oldLocalNorm == oldUrlNorm || oldLocal.toLowerCase().contains('ngrok');
          if (clearLocal) {
            credMap['localUrl'] = null;
            changed = true;
            final name = (root['name'] as String?) ?? '';
            oxEnvLog('Oxplayer URL sync (web): $name cleared localUrl ($oldLocalNorm)');
          }
        }

        if (changed) {
          root['credentials'] = _writeCredentialsBack(credObj, credMap);
          anyChanged = true;
        }
        out.add(jsonEncode(root));
      } catch (_) {
        out.add(jsonStr);
      }
    }

    if (anyChanged) {
      await prefs.setStringList(_loginCredentialsPrefsKey, out);
    }
  }

  static Map<String, dynamic>? _credentialsAsMap(Object? cred) {
    if (cred is Map<String, dynamic>) return cred;
    if (cred is Map) return Map<String, dynamic>.from(cred);
    if (cred is String) {
      try {
        final inner = jsonDecode(cred);
        if (inner is Map<String, dynamic>) return inner;
        if (inner is Map) return Map<String, dynamic>.from(inner);
      } catch (_) {}
    }
    return null;
  }

  /// Preserve string-vs-map credential encoding when mutating.
  static Object _writeCredentialsBack(Object? original, Map<String, dynamic> updated) {
    if (original is String) {
      return jsonEncode(updated);
    }
    return updated;
  }
}
