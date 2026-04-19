import 'dart:developer' as developer;

/// Log line visible in Android Studio Logcat — filter by **`OX_ENV`**.
void oxEnvLog(String message) {
  developer.log(message, name: 'OX_ENV');
}
