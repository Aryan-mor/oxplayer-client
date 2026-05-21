import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

// import 'package:fladder/models/funding_model.dart' as funding;
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_test_mode_api.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/crash_screen/crash_screen.dart';
import 'package:fladder/screens/settings/settings_scaffold.dart';
import 'package:fladder/screens/settings/widgets/settings_update_information.dart';
import 'package:fladder/screens/shared/fladder_icon.dart';
import 'package:fladder/screens/shared/fladder_logo.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';

class _Socials {
  final String label;
  final String url;
  final IconData icon;

  const _Socials(this.label, this.url, this.icon);
}

const socials = [
  _Socials(
    'Github',
    'https://github.com/Aryan-mor/oxplayer-client',
    FontAwesomeIcons.githubAlt,
  ),
  _Socials(
    'Website',
    'https://t.me/OXPlayer',
    IconsaxPlusLinear.global,
  ),
];

@RoutePage()
class AboutSettingsPage extends ConsumerStatefulWidget {
  const AboutSettingsPage({super.key});

  @override
  ConsumerState<AboutSettingsPage> createState() => _AboutSettingsPageState();
}

class _AboutSettingsPageState extends ConsumerState<AboutSettingsPage> {
  Timer? _testModeHoldTimer;
  bool _testModeActivating = false;

  @override
  void dispose() {
    _cancelTestModeHold();
    super.dispose();
  }

  void _cancelTestModeHold() {
    _testModeHoldTimer?.cancel();
    _testModeHoldTimer = null;
  }

  void _onTestModeHoldStart() {
    if (!OxplayerConfig.isEnabled || _testModeActivating) return;
    _cancelTestModeHold();
    _testModeHoldTimer = Timer(const Duration(seconds: 3), () {
      _testModeHoldTimer = null;
      unawaited(_activateTestMode());
    });
  }

  Future<void> _activateTestMode() async {
    if (_testModeActivating || !mounted) return;
    final user = ref.read(userProvider);
    if (user == null) {
      if (mounted) {
        FladderSnack.show('Sign in required', context: context);
      }
      return;
    }

    setState(() => _testModeActivating = true);
    try {
      final result = await oxplayerPostTestModeActivate(
        authorizationHeaders: user.credentials.header(ref),
      );
      if (!mounted) return;
      final parts = <String>[
        'Test mode enabled. Your library was filled with demo titles.',
        if (result.addedCount > 0) 'Added: ${result.addedCount}.',
        if (result.skippedCount > 0) 'Already in library: ${result.skippedCount}.',
      ];
      final unresolved = [
        ...result.unresolvedMovieTmdb,
        ...result.unresolvedTvTmdb,
      ];
      if (unresolved.isNotEmpty) {
        parts.add('Some TMDB ids were not found on the server: ${unresolved.join(", ")}.');
      }
      FladderSnack.show(parts.join(' '), context: context);
    } on OxplayerTestModeApiException catch (e) {
      if (mounted) {
        FladderSnack.show(e.message, context: context);
      }
    } catch (e) {
      if (mounted) {
        FladderSnack.show('Test mode failed: $e', context: context);
      }
    } finally {
      if (mounted) {
        setState(() => _testModeActivating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final applicationInfo = ref.watch(applicationInfoProvider);

    return SettingsScaffold(
      label: "",
      items: [
        GestureDetector(
          onLongPressStart: (_) => _onTestModeHoldStart(),
          onLongPressEnd: (_) => _cancelTestModeHold(),
          onLongPressCancel: _cancelTestModeHold,
          child: Opacity(
            opacity: _testModeActivating ? 0.6 : 1,
            child: const FladderLogo(),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(context.localized.aboutVersion(applicationInfo.versionAndPlatform)),
            Text(context.localized.aboutBuild(applicationInfo.buildNumber)),
            const SizedBox(height: 16),
            Text(context.localized.aboutCreatedBy),
          ],
        ),
        const FractionallySizedBox(
          widthFactor: 0.25,
          child: Divider(
            indent: 16,
            endIndent: 16,
          ),
        ),
        const _SocialsSection(),
        // const _SponsorsSection(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.tonal(
              onPressed: () => showLicensePage(
                context: context,
                applicationIcon: const FladderIcon(size: 55),
                applicationVersion: applicationInfo.versionPlatformBuild,
                applicationLegalese: "DonutWare",
                useRootNavigator: true,
              ),
              child: Text(context.localized.aboutLicenses),
            )
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.tonal(
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const CrashScreen(),
              ),
              child: Text(context.localized.errorLogs),
            )
          ],
        ),
        const SettingsUpdateInformation(),
      ].addInBetween(const SizedBox(height: 16)),
    );
  }
}

class _SocialsSection extends StatelessWidget {
  const _SocialsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          context.localized.aboutSocials,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: socials
              .map(
                (e) => IconButton.filledTonal(
                  onPressed: () => launchUrl(context, e.url),
                  icon: Column(
                    children: [
                      Icon(e.icon),
                      Text(e.label),
                    ],
                  ),
                ),
              )
              .toList()
              .addInBetween(const SizedBox(width: 16)),
        )
      ],
    );
  }
}
