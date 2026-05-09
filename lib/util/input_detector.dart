import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/settings/arguments_model.dart';
import 'package:fladder/oxplayer/oxplayer_hotkey_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_helper.dart';

class InputDetector extends ConsumerStatefulWidget {
  final bool isDesktop;
  final bool htpcMode;
  final Widget Function(InputDevice input) child;

  const InputDetector({
    super.key,
    required this.isDesktop,
    required this.htpcMode,
    required this.child,
  });

  @override
  ConsumerState<InputDetector> createState() => _InputDetectorState();
}

class _InputDetectorState extends ConsumerState<InputDetector> {
  late InputDevice _currentInput = widget.htpcMode
      ? InputDevice.dPad
      : (widget.isDesktop || kIsWeb)
          ? InputDevice.pointer
          : InputDevice.touch;

  @override
  void initState() {
    super.initState();
    _startListeningToKeyboard();
  }

  void _startListeningToKeyboard() {
    ServicesBinding.instance.keyboard.addHandler(_handleKeyPress);
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_handleKeyPress);
    super.dispose();
  }

  bool _handleKeyPress(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (isEditableTextFocused() &&
          (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight)) {
        return false;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.select) {
        _updateInputDevice(InputDevice.dPad);
      }
    }
    return false;
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (event.kind == PointerDeviceKind.touch) {
        _updateInputDevice(InputDevice.touch);
      } else if (event.kind == PointerDeviceKind.mouse) {
        _updateInputDevice(InputDevice.pointer);
      }
    }
  }

  void _updateInputDevice(InputDevice device) {
    if (_currentInput != device) {
      if (device == InputDevice.dPad &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          !androidTvRemoteStyleShortcuts) {
        androidTvRemoteStyleShortcuts = true;
        ref.read(hotkeyLayoutEpochProvider.notifier).state =
            ref.read(hotkeyLayoutEpochProvider) + 1;
      }
      if (device != InputDevice.dPad) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      setState(() {
        _currentInput = device;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerEvent,
      behavior: HitTestBehavior.translucent,
      child: IgnorePointer(
        ignoring: _currentInput == InputDevice.dPad,
        child: Builder(
          builder: (context) => widget.child(_currentInput),
        ),
      ),
    );
  }
}
