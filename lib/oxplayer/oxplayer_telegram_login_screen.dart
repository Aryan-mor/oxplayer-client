import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_debug.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_init_data.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/login/lock_screen.dart';
import 'package:fladder/screens/shared/fladder_logo.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/fladder_config.dart';

enum _OxLoginPane { hub, qr, phone }

@RoutePage()
class OxplayerTelegramLoginScreen extends ConsumerStatefulWidget {
  const OxplayerTelegramLoginScreen({
    @QueryParam('tgWebAppData') this.tgWebAppData,
    super.key,
  });

  /// Legacy Mini App deep link (optional). TDLib login ignores this when unused.
  final String? tgWebAppData;

  @override
  ConsumerState<OxplayerTelegramLoginScreen> createState() =>
      _OxplayerTelegramLoginScreenState();
}

class _OxplayerTelegramLoginScreenState
    extends ConsumerState<OxplayerTelegramLoginScreen> {
  _OxLoginPane _pane = _OxLoginPane.hub;
  bool _bootstrapping = true;
  String? _bootstrapError;
  bool _busy = false;
  bool _handledRouteInitData = false;
  bool _backendBridgeDone = false;
  bool _tdListenersStarted = false;

  OxplayerTelegramTdSession? _tdSession;
  Future<void>? _authorizationAttempt;

  StreamSubscription<String?>? _qrSub;
  StreamSubscription<TdlibCloudPasswordChallenge?>? _cloudPasswordSub;
  StreamSubscription<TdlibSmsCodeChallenge?>? _smsCodeSub;
  StreamSubscription<bool>? _waitPhoneSub;
  StreamSubscription<int>? _authenticatedUserSub;
  StreamSubscription<String?>? _functionErrorSub;

  String? _qrPayload;
  TdlibCloudPasswordChallenge? _cloudPasswordChallenge;
  TdlibSmsCodeChallenge? _smsCodeChallenge;
  bool _authorizationWaitPhoneNumber = false;
  String? _flowError;

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _passwordSubmitting = false;
  bool _phoneSubmitting = false;
  bool _codeSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _tdSession = OxplayerTelegramTdSession();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    unawaited(_qrSub?.cancel());
    unawaited(_cloudPasswordSub?.cancel());
    unawaited(_smsCodeSub?.cancel());
    unawaited(_waitPhoneSub?.cancel());
    unawaited(_authenticatedUserSub?.cancel());
    unawaited(_functionErrorSub?.cancel());
    // Do not dispose [OxplayerTelegramTdSession]: it uses the process-wide TDLib
    // ([OxplayerTelegramTdRuntime.facade]). Disposing here ran after navigate to
    // [DashboardRoute] and closed TDLib, breaking Telegram media playback.
    _passwordController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startTdListenersOnce() {
    if (kIsWeb || _tdListenersStarted || _tdSession == null) return;
    _tdListenersStarted = true;
    final s = _tdSession!;
    _qrSub = s.qrLoginPayload.listen((payload) {
      if (!mounted) return;
      setState(() => _qrPayload = payload);
    });
    _cloudPasswordSub = s.cloudPasswordChallenge.listen((c) {
      if (!mounted) return;
      setState(() => _cloudPasswordChallenge = c);
    });
    _smsCodeSub = s.smsCodeChallenge.listen((c) {
      if (!mounted) return;
      setState(() => _smsCodeChallenge = c);
    });
    _waitPhoneSub = s.authorizationWaitPhoneNumber.listen((waiting) {
      if (!mounted) return;
      setState(() => _authorizationWaitPhoneNumber = waiting);
    });
    _authenticatedUserSub = s.authenticatedUserId.listen((id) {
      if (!mounted || id == 0 || _backendBridgeDone) return;
      unawaited(_bridgeTdToBackend());
    });
    _functionErrorSub = s.functionErrors.listen((message) {
      if (!mounted || message == null || message.isEmpty) return;
      FladderSnack.show(message, context: context);
    });
  }

  Future<void> _bridgeTdToBackend() async {
    if (_backendBridgeDone || !mounted || kIsWeb || _tdSession == null) return;
    setState(() => _busy = true);
    try {
      final app = ref.read(applicationInfoProvider);
      final deviceName =
          '${app.name} / ${defaultTargetPlatform.name}';
      final exchanged =
          await _tdSession!.authenticateWithOxApi(deviceName: deviceName);
      await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);
      ref.read(lockScreenActiveProvider.notifier).update((s) => false);
      _backendBridgeDone = true;
      if (mounted) {
        await context.router.replaceAll([const DashboardRoute()]);
      }
    } catch (e) {
      if (mounted) {
        FladderSnack.show('$e', context: context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _bootstrapError = null;
    });

    OxplayerEnv.debugLogApiResolution();
    final api = OxplayerEnv.apiBaseUrl;
    final media = OxplayerEnv.effectiveMediaServerUrl;
    if (api == null || media == null) {
      oxEnvLog(
        'OxplayerTelegramLoginScreen._bootstrap: MISSING api or media '
        '(api=$api media=$media).',
      );
      setState(() {
        _bootstrapping = false;
        _bootstrapError =
            'Build is missing API configuration. Set OXPLAYER_API_BASE or OXPLAYER_API_BASE_URL.';
      });
      return;
    }

    FladderConfig.baseUrl = media;

    try {
      await ref.read(authProvider.notifier).initModel(clearUserState: false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _bootstrapping = false;
          _bootstrapError = '$e';
        });
      }
      return;
    }

    if (!mounted) return;

    final err = ref.read(authProvider).errorMessage;
    if (err != null) {
      setState(() {
        _bootstrapping = false;
        _bootstrapError = err;
      });
      return;
    }

    if (!kIsWeb && _tdSession != null) {
      _startTdListenersOnce();
      try {
        await OxplayerTelegramTdSession.initPlugin();
        await _tdSession!.initClient();
        if (await _tdSession!.trySilentRestore()) {
          if (!mounted) return;
          setState(() => _bootstrapping = false);
          await _bridgeTdToBackend();
          return;
        }
      } catch (e) {
        oxEnvLog('OxplayerTelegramLoginScreen TDLib silent restore: $e');
      }
    }

    setState(() => _bootstrapping = false);

    final fromRoute = widget.tgWebAppData?.trim();
    if (!_handledRouteInitData &&
        fromRoute != null &&
        fromRoute.isNotEmpty) {
      _handledRouteInitData = true;
      await _completeSignInWithInitData(fromRoute);
    }
  }

  /// Optional path: raw WebApp initData from a deep link (same backend exchange).
  Future<void> _completeSignInWithInitData(String rawInitData) async {
    final apiBase = OxplayerEnv.apiBaseUrl;
    if (apiBase == null) {
      FladderSnack.show('Missing API configuration', context: context);
      return;
    }

    final initData = oxplayerNormalizeTelegramInitDataInput(rawInitData);
    if (initData.isEmpty) {
      FladderSnack.show('Telegram session not ready yet', context: context);
      return;
    }

    if (ref.read(authProvider).serverLoginModel == null) {
      FladderSnack.show('Connecting to server… try again in a moment.',
          context: context);
      await _bootstrap();
      return;
    }

    setState(() => _busy = true);
    try {
      final app = ref.read(applicationInfoProvider);
      final deviceName = kIsWeb
          ? 'OXPlayer Web'
          : '${app.name} / ${defaultTargetPlatform.name}';

      final client = OxplayerTelegramAuthClient(apiBase: apiBase);
      final exchanged = await client.exchangeInitData(
        initData: initData,
        deviceName: deviceName,
      );

      await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);

      ref.read(lockScreenActiveProvider.notifier).update((s) => false);

      if (mounted) {
        await context.router.replaceAll([const DashboardRoute()]);
      }
    } on OxplayerTelegramAuthException catch (e) {
      if (mounted) FladderSnack.show(e.message, context: context);
    } catch (e) {
      if (mounted) FladderSnack.show('$e', context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ensureAuthorizationStarted() async {
    final session = _tdSession;
    if (session == null || kIsWeb || _authorizationAttempt != null) return;

    setState(() {
      _busy = true;
      _flowError = null;
    });

    final attempt = session.beginTelegramAuthorization();
    _authorizationAttempt = attempt;
    attempt.catchError((Object error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _authorizationAttempt = null;
        _flowError = error.toString();
      });
    });
  }

  Future<void> _startQrAuthentication() async {
    if (kIsWeb || _tdSession == null) {
      FladderSnack.show(
        'Telegram client login requires Android (TDLib + jniLibs).',
        context: context,
      );
      return;
    }
    setState(() {
      _pane = _OxLoginPane.qr;
      _flowError = null;
    });
    try {
      await _ensureAuthorizationStarted();
      await _tdSession!.startQrLogin();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _authorizationAttempt = null;
        _flowError = error.toString();
      });
    }
  }

  Future<void> _startPhoneAuthentication() async {
    if (kIsWeb || _tdSession == null) {
      FladderSnack.show(
        'Telegram client login requires Android (TDLib + jniLibs).',
        context: context,
      );
      return;
    }
    setState(() {
      _pane = _OxLoginPane.phone;
      _flowError = null;
    });
    try {
      await _ensureAuthorizationStarted();
    } catch (error) {
      if (!mounted) return;
      setState(() => _flowError = error.toString());
    }
  }

  Future<void> _submitPhoneNumber() async {
    final session = _tdSession;
    final phoneNumber = _phoneController.text.trim();
    if (session == null || phoneNumber.isEmpty || _phoneSubmitting) return;

    setState(() => _phoneSubmitting = true);
    try {
      await session.submitAuthenticationPhoneNumber(phoneNumber);
    } catch (e) {
      if (mounted) {
        FladderSnack.show('Telegram: $e', context: context);
      }
    } finally {
      if (mounted) setState(() => _phoneSubmitting = false);
    }
  }

  Future<void> _submitCode() async {
    final session = _tdSession;
    final code = _codeController.text.trim();
    if (session == null || code.isEmpty || _codeSubmitting) return;

    setState(() => _codeSubmitting = true);
    try {
      await session.submitAuthenticationCode(code);
    } catch (e) {
      if (mounted) {
        FladderSnack.show('Telegram: $e', context: context);
      }
    } finally {
      if (mounted) setState(() => _codeSubmitting = false);
    }
  }

  Future<void> _submitPassword() async {
    final session = _tdSession;
    final password = _passwordController.text;
    if (session == null || password.isEmpty || _passwordSubmitting) return;

    setState(() => _passwordSubmitting = true);
    try {
      await session.submitCloudPassword(password);
    } catch (e) {
      if (mounted) {
        FladderSnack.show('Telegram: $e', context: context);
      }
    } finally {
      if (mounted) setState(() => _passwordSubmitting = false);
    }
  }

  Future<void> _resetTelegramFlow() async {
    final session = _tdSession;
    if (session == null) return;

    _passwordController.clear();
    _phoneController.clear();
    _codeController.clear();

    setState(() {
      _busy = false;
      _authorizationAttempt = null;
      _backendBridgeDone = false;
      _flowError = null;
      _qrPayload = null;
      _cloudPasswordChallenge = null;
      _smsCodeChallenge = null;
      _authorizationWaitPhoneNumber = false;
      _pane = _OxLoginPane.hub;
    });

    await session.resetLocalSessionForQrLogin();
  }

  Widget _buildHub(BuildContext context) {
    if (kIsWeb) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'OXPlayer Telegram sign-in uses TDLib on Android. '
            'Use the Android build with libtdjson.so in jniLibs.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final missingTdKeys = (OxplayerEnv.telegramApiId ?? '').trim().isEmpty ||
        (OxplayerEnv.telegramApiHash ?? '').trim().isEmpty;
    if (missingTdKeys) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Set TELEGRAM_API_ID and TELEGRAM_API_HASH in assets/env/default.env.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    final buttons = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in with Telegram',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Uses TDLib (same flow as OXPlayer Android): scan QR or enter your phone number in international format.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: (_busy || _bootstrapping) ? null : _startQrAuthentication,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Login with QR code'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: (_busy || _bootstrapping) ? null : _startPhoneAuthentication,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.phone_iphone),
          label: const Text('Login with number'),
        ),
        if (_flowError != null) ...[
          const SizedBox(height: 16),
          Text(
            _flowError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );

    const brandColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 120,
          child: FractionallySizedBox(
            widthFactor: 0.85,
            child: FittedBox(
              fit: BoxFit.contain,
              child: FladderLogo(),
            ),
          ),
        ),
      ],
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(child: Center(child: brandColumn)),
          const SizedBox(width: 48),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: buttons,
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          brandColumn,
          const SizedBox(height: 40),
          buttons,
        ],
      ),
    );
  }

  Widget _buildQrPane(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide * 0.55;
    final qrSize = side.clamp(160.0, 280.0);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Scan this QR code with Telegram (Settings → Devices → Link Desktop Device) to sign in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        if (_qrPayload != null && _qrPayload!.isNotEmpty)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: QrImageView(
                data: _qrPayload!,
                size: qrSize,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
          )
        else
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _busy ? null : _resetTelegramFlow,
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter your mobile number in international format.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Phone number',
          ),
          onSubmitted: (_) => unawaited(_submitPhoneNumber()),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _phoneSubmitting ? null : _submitPhoneNumber,
          child: _phoneSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send code'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _resetTelegramFlow,
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    final challenge = _smsCodeChallenge;
    final instruction = challenge == null || challenge.phoneNumber.isEmpty
        ? 'Enter the login code Telegram sent to your phone.'
        : 'Enter the login code Telegram sent to ${challenge.phoneNumber}.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          instruction,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Login code',
          ),
          onSubmitted: (_) => unawaited(_submitCode()),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _codeSubmitting ? null : _submitCode,
          child: _codeSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm code'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _resetTelegramFlow,
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'This account uses two-step verification. Enter your Telegram password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        if (_cloudPasswordChallenge != null &&
            _cloudPasswordChallenge!.hint.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Hint: ${_cloudPasswordChallenge!.hint}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _passwordController,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Password',
          ),
          onSubmitted: (_) => unawaited(_submitPassword()),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _passwordSubmitting ? null : _submitPassword,
          child: _passwordSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _resetTelegramFlow,
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildProgressState() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text(
          'Waiting for Telegram authentication…',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildAuthContent(BuildContext context, {required double qrSize}) {
    final showQr = _cloudPasswordChallenge == null &&
        _smsCodeChallenge == null &&
        _qrPayload != null &&
        _qrPayload!.isNotEmpty &&
        _pane == _OxLoginPane.qr;
    final showCode =
        _cloudPasswordChallenge == null && _smsCodeChallenge != null;
    final showPhone = _cloudPasswordChallenge == null &&
        _smsCodeChallenge == null &&
        !showQr &&
        _authorizationWaitPhoneNumber &&
        _pane == _OxLoginPane.phone;
    final showProgress = _busy &&
        !showQr &&
        !showCode &&
        !showPhone &&
        _cloudPasswordChallenge == null;

    if (_cloudPasswordChallenge != null) {
      return _buildPasswordStep();
    }
    if (showQr) {
      return _buildQrPane(context);
    }
    if (showCode) {
      return _buildCodeStep();
    }
    if (showPhone) {
      return _buildPhoneStep();
    }
    if (showProgress) {
      return _buildProgressState();
    }
    return _buildHub(context);
  }

  @override
  Widget build(BuildContext context) {
    final authLoading = ref.watch(authProvider.select((s) => s.loading));

    Widget body;
    if (_bootstrapping || authLoading) {
      body = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Connecting…',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    } else if (_bootstrapError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _bootstrapError!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _bootstrap(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else {
      final isDesktop = MediaQuery.sizeOf(context).width > 700;
      final qrSize = isDesktop ? 300.0 : 220.0;
      body = _buildAuthContent(context, qrSize: qrSize);
    }

    final showBack = !_bootstrapping &&
        _bootstrapError == null &&
        (_pane != _OxLoginPane.hub || _flowError != null);

    return NotificationManagerInitializer(
      child: Scaffold(
        appBar: showBack
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _busy
                      ? null
                      : () {
                          if (_pane != _OxLoginPane.hub) {
                            unawaited(_resetTelegramFlow());
                          } else {
                            setState(() => _flowError = null);
                          }
                        },
                ),
              )
            : null,
        body: AbsorbPointer(
          absorbing: _busy,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.all(24),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
