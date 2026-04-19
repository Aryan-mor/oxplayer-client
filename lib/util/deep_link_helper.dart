import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:auto_route/auto_route.dart' show DeepLink, PageRouteInfo;
import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/routes/auto_router.gr.dart';

FutureOr<DeepLink> deepLinkBuilder(Uri? payload) {
  if (kDebugMode) {
    debugPrint(
      '[OX deepLink] uri=$payload oxplayer=${OxplayerConfig.isEnabled}',
    );
  }
  final route = payloadToRoute(payload);
  if (route != null) {
    final path = pageRouteInfoToPath(route);
    if (kDebugMode) {
      debugPrint('[OX deepLink] matched route -> DeepLink.path($path)');
    }
    return DeepLink.path(path);
  }
  // OX builds used to default to `/ox-login`, but that route calls [AuthNotifier.initModel]
  // and briefly clears in-memory session — returning users saw a login flash and could
  // be bounced through TDLib bootstrap again. Use the same cold-start path as upstream:
  // [SplashScreen] restores the last auto-login account or sends users to Telegram login.
  if (OxplayerConfig.isEnabled) {
    if (kDebugMode) {
      debugPrint('[OX deepLink] default -> DeepLink.single(SplashRoute)');
    }
    return DeepLink.single(SplashRoute());
  }
  if (kDebugMode) {
    debugPrint('[OX deepLink] default -> DeepLink.single(SplashRoute)');
  }
  return DeepLink.single(SplashRoute());
}

class AuthLinkData {
  final String serverUrl;
  final String? seerrUrl;
  final String userName;
  final String? password;

  AuthLinkData({
    required this.serverUrl,
    this.seerrUrl,
    required this.userName,
    this.password,
  });

  Map<String, dynamic> toJson() => {
        'server': serverUrl,
        if (seerrUrl != null) 'seerr': seerrUrl,
        'userName': userName,
        if (password != null && password!.isNotEmpty) 'password': password,
      };

  factory AuthLinkData.fromJson(Map<String, dynamic> json) => AuthLinkData(
        serverUrl: json['server'] as String,
        seerrUrl: json['seerr'] as String?,
        userName: json['userName'] as String,
        password: json['password'] as String?,
      );

  static AuthLinkData? parse(String encoded) {
    String removeUrlPrefix = encoded.replaceFirst(RegExp(r'^fladder:\/\/\/login\?authLink='), '');
    try {
      final pad = removeUrlPrefix.length % 4;
      if (pad != 0) {
        removeUrlPrefix = removeUrlPrefix.padRight(removeUrlPrefix.length + (4 - pad), '=');
      }
      final bytes = base64Url.decode(removeUrlPrefix);
      final jsonStr = utf8.decode(bytes);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AuthLinkData.fromJson(map);
    } catch (e) {
      log("Failed to parse auth link data: $e");
      return null;
    }
  }

  @override
  String toString() {
    return 'AuthLinkData(serverUrl: $serverUrl, seerrUrl: $seerrUrl, userName: $userName, password: ${password != null ? "****" : null})';
  }
}

String encodeAuthLink(AuthLinkData data) {
  final jsonStr = jsonEncode(data.toJson());
  final bytes = utf8.encode(jsonStr);
  var encoded = base64Url.encode(bytes);
  encoded = encoded.replaceAll('=', '');
  return encoded;
}

String buildAuthUrl(AuthLinkData data) {
  final payload = encodeAuthLink(data);
  return 'fladder:///login?authLink=$payload';
}

String? _tgWebAppDataFromUri(Uri payload) {
  final direct = payload.queryParameters['tgWebAppData'];
  if (direct != null && direct.isNotEmpty) return direct;
  if (!payload.hasFragment) return null;
  try {
    return Uri.splitQueryString(payload.fragment)['tgWebAppData'];
  } catch (_) {
    return null;
  }
}

PageRouteInfo? payloadToRoute(Uri? payload) {
  if (payload == null) return null;

  if (payload.path.contains('ox-login')) {
    return OxplayerTelegramLoginRoute(tgWebAppData: _tgWebAppDataFromUri(payload));
  }

  if (payload.path.contains('/login')) {
    if (OxplayerConfig.isEnabled) {
      return OxplayerTelegramLoginRoute(tgWebAppData: _tgWebAppDataFromUri(payload));
    }
    final authLink = payload.queryParameters['authLink'];
    if (authLink != null && authLink.isNotEmpty) {
      log("Parsing auth link from payload: $authLink");
      return LoginRoute(authLink: authLink);
    }
    return LoginRoute(authLink: "sdflkj");
  }

  if (payload.path.contains('/seerr')) {
    final segments = payload.pathSegments;
    if (segments.length >= 3) {
      final mediaType = segments[1];
      final tmdbId = int.tryParse(segments[2]);
      if (tmdbId != null) return SeerrDetailsRoute(mediaType: mediaType, tmdbId: tmdbId);
    }
    return const SeerrRoute();
  }
  if (payload.path.contains('/details')) {
    return DetailsRoute(id: payload.queryParameters['id']!);
  }
  return null;
}

String _oxLoginPath(OxplayerTelegramLoginRouteArgs? args) {
  final tg = args?.tgWebAppData;
  if (tg == null || tg.isEmpty) return '/ox-login';
  return '/ox-login?tgWebAppData=${Uri.encodeQueryComponent(tg)}';
}

String pageRouteInfoToPath(PageRouteInfo route) {
  try {
    return switch (route) {
      DetailsRoute() => '/details?id=${route.queryParams.get('id')}',
      SeerrDetailsRoute() =>
        '/seerr?mediaType=${route.queryParams.get('mediaType')}&tmdbId=${route.queryParams.get('tmdbId')}',
      OxplayerTelegramLoginRoute(:final args) => _oxLoginPath(args),
      LoginRoute() => '/login?authLink=${route.queryParams.get('authLink')}',
      _ => '/',
    };
  } catch (e) {
    log("Failed to convert route to path: $e");
    return route.routeName;
  }
}
