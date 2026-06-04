import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/oxplayer_test_account_sign_in.dart';

/// Press and hold [child] (login QR) for [kOxTestAccountQrHoldDuration] to trigger tester sign-in.
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
  bool _holding = false;

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_holding && mounted) {
      setState(() => _holding = false);
    }
  }

  void _startHold() {
    if (!widget.enabled || _holding) return;
    setState(() => _holding = true);
    _holdTimer = Timer(kOxTestAccountQrHoldDuration, () {
      _holdTimer = null;
      if (!mounted) return;
      setState(() => _holding = false);
      widget.onHoldComplete();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _startHold(),
      onPointerUp: (_) => _cancelHold(),
      onPointerCancel: (_) => _cancelHold(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          if (_holding)
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Hold…',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
