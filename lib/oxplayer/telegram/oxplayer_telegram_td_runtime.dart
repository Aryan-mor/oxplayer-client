import 'tdlib_controller.dart' if (dart.library.html) 'tdlib_controller_web.dart';

/// Single [TelegramTdlibFacade] for login + Telegram media playback.
final class OxplayerTelegramTdRuntime {
  OxplayerTelegramTdRuntime._();

  static TelegramTdlibFacade? _facade;

  static TelegramTdlibFacade get facade => _facade ??= TelegramTdlibFacade();
}
