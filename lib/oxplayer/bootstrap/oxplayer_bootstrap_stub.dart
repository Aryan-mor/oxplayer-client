import 'package:fladder/bootstrap/app_bootstrap.dart';

/// Fallback declaration — never selected at runtime; exists so the Dart analyser
/// resolves [executePlatformSpecificBoot] when neither `dart.library.js_interop`
/// nor `dart.library.io` is available (e.g. pure Dart unit-test host).
Future<void> executePlatformSpecificBoot(AppBootstrapResult bootstrap) async {}
