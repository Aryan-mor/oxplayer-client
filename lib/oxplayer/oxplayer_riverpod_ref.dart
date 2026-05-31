import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Coerces [WidgetRef], [Ref], or a mistaken [ConsumerStatefulElement] for `.read`.
dynamic oxplayerCoerceRef(dynamic ref) {
  if (ref is WidgetRef || ref is Ref) return ref;
  try {
    final dynamic candidate = ref;
    final widgetRef = candidate.ref;
    if (widgetRef is WidgetRef || widgetRef is Ref) return widgetRef;
  } catch (_) {
    /* not a Consumer element */
  }
  throw ArgumentError('Expected Ref or WidgetRef, got ${ref.runtimeType}');
}
