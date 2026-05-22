import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_online_status.dart';
import 'package:fladder/providers/dashboard_provider.dart';
import 'package:fladder/providers/library_screen_provider.dart';
import 'package:fladder/providers/views_provider.dart';

/// After OX auth, home/library tabs can mount with empty Riverpod state until pull-to-refresh.
/// Prefetch views + library rows so Google Play review (and normal Telegram) login shows the catalog immediately.
Future<void> oxplayerWarmupHomeLibraryAfterAuth(Ref ref) async {
  if (!OxplayerConfig.isEnabled) return;
  if (ref.read(effectiveOfflineModeProvider)) return;

  await ref.read(viewsProvider.notifier).fetchViews(force: true);
  await ref.read(libraryScreenProvider.notifier).fetchAllLibraries();
  await ref.read(dashboardProvider.notifier).fetchNextUpAndResume(force: true);
}
