import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';

extension RouterExtension on StackRouter {
  Future<bool> popBack() async {
    return maybePop();
  }

  Widget? backButton() {
    if (canPop()) {
      return IconButton(
        onPressed: maybePop,
        icon: const BackButtonIcon(),
      );
    }
    return null;
  }
}
