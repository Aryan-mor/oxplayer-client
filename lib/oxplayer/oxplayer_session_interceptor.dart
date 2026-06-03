import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:fladder/providers/user_provider.dart';

/// On 401, tries refresh once; otherwise clears the local session and routes to login.
class OxplayerSessionInterceptor implements Interceptor {
  OxplayerSessionInterceptor(this.ref);

  final Ref ref;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    final response = await chain.proceed(chain.request);

    if (response.statusCode != 401) return response;

    final path = chain.request.url.path.toLowerCase();
    if (path.contains('authenticatebyname')) return response;

    if (ref.read(userProvider) == null) return response;

    final refreshed = await oxplayerTryRefreshSession(ref.read);
    if (refreshed) {
      return chain.proceed(chain.request);
    }

    ref.read(oxplayerSessionRevokedProvider.notifier).state++;
    return response;
  }
}
