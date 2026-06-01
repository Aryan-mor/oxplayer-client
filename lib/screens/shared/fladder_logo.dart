import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/screens/shared/fladder_icon.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/theme_extensions.dart';

class FladderLogo extends ConsumerWidget {
  const FladderLogo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.read(applicationInfoProvider).name;
    return Hero(
      tag: "Fladder_Logo_Tag",
      child: LayoutBuilder(
        builder: (context, constraints) {
          Widget content = Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const FladderIcon(),
              const SizedBox(height: 16),
              Text(
                name,
                style: context.textTheme.displayLarge,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
              ),
            ],
          );
          if (constraints.hasBoundedHeight && constraints.maxHeight.isFinite) {
            content = FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: content,
            );
          }
          return content;
        },
      ),
    );
  }
}
