# OXPlayer Client

Flutter client based on [Fladder](https://github.com/DonutWare/fladder), wired for the OXPlayer Jellyfin-compatible API.

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

Point the app at your `oxplayer` API base URL (Jellyfin-shaped routes) once OX auth and server selection are implemented under `lib/oxplayer/`.
