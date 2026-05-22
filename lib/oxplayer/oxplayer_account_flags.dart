import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set after OX auth when the server marks the account as non-deletable (Google Play review user).
final oxplayerAccountDeleteDisabledProvider = StateProvider<bool>((ref) => false);
