import 'package:flutter/material.dart' hide ConnectionState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/oxplayer_online_status.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(oxplayerAppStatusProvider);
    final theme = Theme.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: status.shouldShowBanner ? 1 : 0,
      child: IgnorePointer(
        child: Row(
          spacing: 12,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              switch (status.kind) {
                OxplayerAppStatusKind.offline => IconsaxPlusLinear.cloud_cross,
                OxplayerAppStatusKind.connecting => IconsaxPlusLinear.global_refresh,
                OxplayerAppStatusKind.error => IconsaxPlusLinear.info_circle,
                OxplayerAppStatusKind.online => IconsaxPlusLinear.cloud,
              },
              color: theme.colorScheme.onErrorContainer,
              size: 20,
            ),
            Text(
              status.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
