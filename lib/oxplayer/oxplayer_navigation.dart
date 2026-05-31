import 'package:auto_route/auto_route.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/routes/auto_router.gr.dart';

/// Stack to open after sign-out / switch user (no Fladder server login when OX is on).
List<PageRouteInfo<dynamic>> oxplayerSignOutRouteList() {
  if (OxplayerConfig.isEnabled) {
    return const <PageRouteInfo<dynamic>>[OxplayerLoginRoute()];
  }
  return <PageRouteInfo<dynamic>>[LoginRoute()];
}

/// Route to push when user adds another account from settings.
PageRouteInfo<dynamic> oxplayerAddAccountRoute() {
  if (OxplayerConfig.isEnabled) {
    return const OxplayerLoginRoute();
  }
  return LoginRoute();
}
