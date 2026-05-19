import 'package:fladder/bootstrap/app_bootstrap.dart';

/// Web implementation — intentional no-op.
///
/// TDLib warm-up is native-only; on web the WASM client is initialised lazily
/// when the login screen first calls [OxplayerTelegramTdSession.initClient].
/// Keeping this file free of any native-only imports (dart:io, path_provider,
/// Riverpod auth graph) is the whole reason this split exists.
Future<void> executePlatformSpecificBoot(AppBootstrapResult bootstrap) async {}
