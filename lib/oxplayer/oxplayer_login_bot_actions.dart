import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/oxplayer_bot_qr_dialog.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/localization_helper.dart';

class OxplayerLoginBotActions extends StatelessWidget {
  const OxplayerLoginBotActions({super.key});

  @override
  Widget build(BuildContext context) {
    final link = OxplayerEnv.telegramBotLoginLink;
    final bot = OxplayerEnv.botUsername;
    if (link == null || bot == null) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => launchUrl(context, link),
            icon: const Icon(Icons.telegram),
            label: Text(context.localized.oxplayerHelpOpenBot(bot)),
          ),
        ),
        IconButton(
          tooltip: context.localized.oxplayerHelpQrCaption,
          onPressed: () => showOxplayerBotQrSheet(context, telegramLink: link, botUsername: bot),
          icon: const Icon(Icons.qr_code_2_rounded),
        ),
      ],
    );
  }
}
