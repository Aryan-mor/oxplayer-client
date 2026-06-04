import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/oxplayer_test_account_sign_in.dart';

/// Press and hold [child] (login QR) for [kOxTestAccountQrHoldDuration] to trigger tester sign-in.
/// No visible feedback — the gesture is intentionally hidden.
class OxplayerTestAccountQrHold extends StatefulWidget {
  const OxplayerTestAccountQrHold({
    required this.child,
    required this.onHoldComplete,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onHoldComplete;
  final bool enabled;

  @override
  State<OxplayerTestAccountQrHold> createState() => _OxplayerTestAccountQrHoldState();
}

class _OxplayerTestAccountQrHoldState extends State<OxplayerTestAccountQrHold> {
  Timer? _holdTimer;

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _startHold() {
    if (!widget.enabled || _holdTimer != null) return;
    _holdTimer = Timer(kOxTestAccountQrHoldDuration, () {
      _holdTimer = null;
      if (!mounted) return;
      widget.onHoldComplete();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _startHold(),
      onPointerUp: (_) => _cancelHold(),
      onPointerCancel: (_) => _cancelHold(),
      child: widget.child,
    );
  }
}
