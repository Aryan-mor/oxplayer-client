import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Web / targets without `dart:io`: native Jellyfin session refresh is unused (see real impl).
Future<bool> oxplayerTryRefreshJellyfinSessionAfter401(Ref ref) async => false;
