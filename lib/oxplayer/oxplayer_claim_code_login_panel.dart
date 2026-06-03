import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_jellyfin_auth.dart';
import 'package:fladder/oxplayer/oxplayer_login_bot_actions.dart';

class OxplayerClaimCodeLoginPanel extends ConsumerStatefulWidget {
  const OxplayerClaimCodeLoginPanel({
    required this.onSuccess,
    this.onBack,
    super.key,
  });

  final Future<void> Function() onSuccess;
  final VoidCallback? onBack;

  @override
  ConsumerState<OxplayerClaimCodeLoginPanel> createState() => _OxplayerClaimCodeLoginPanelState();
}

class _OxplayerClaimCodeLoginPanelState extends ConsumerState<OxplayerClaimCodeLoginPanel> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-character code from the bot.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await oxplayerAuthenticateWithClaimCode(ref, code);
      if (!mounted) return;
      if (response?.isSuccessful != true || response?.body == null) {
        setState(() => _error = 'Login failed. Check the code and try again.');
        return;
      }
      await widget.onSuccess();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onBack != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          'Login code',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Get a 6-character code from the Telegram bot, then enter it here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Code', counterText: ''),
          onSubmitted: (_) => _loading ? null : _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
        const SizedBox(height: 12),
        const OxplayerLoginBotActions(),
      ],
    );
  }
}
