# OXPlayer Client

Flutter client based on [Fladder](https://github.com/DonutWare/fladder), focused on your **Telegram media library** via the OXPlayer API.

## OX build flag

OX-specific hooks and **Telegram-first login** run by default.

Use vanilla Fladder-style startup when you need upstream behavior:

```bash
flutter run --dart-define=OXPLAYER=false
```

Implementation lives in [`lib/oxplayer/`](lib/oxplayer/README.md).

## Upstream updates

See [`docs/UPSTREAM_SYNC.md`](docs/UPSTREAM_SYNC.md).

## API

Point the app at your `oxplayer` API base URL (set in `assets/env/default.env` or `--dart-define`) under `lib/oxplayer/`.

## Sentry (optional)

Set `SENTRY_DSN` in `assets/env/default.env`, `dart_defines.*.json`, or `--dart-define` (same variable names as the `oxplayer` API). When the DSN is empty, the SDK is not loaded. Implementation: `lib/oxplayer/oxplayer_sentry.dart`.
