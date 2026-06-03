import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/oxplayer_help_content.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class OxplayerHelpScreen extends StatelessWidget {
  const OxplayerHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.localized.oxplayerHelpTitle)),
      body: const SafeArea(child: OxplayerHelpContent()),
    );
  }
}
