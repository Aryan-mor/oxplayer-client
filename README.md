# OXPlayer Client

Flutter client based on [Fladder](https://github.com/DonutWare/fladder), wired for the OXPlayer Jellyfin-compatible API.

## OX build flag

OX-specific hooks run only when:

```bash
flutter run --dart-define=OXPLAYER=true
```

Implementation lives in [`lib/oxplayer/`](lib/oxplayer/README.md). Default (`OXPLAYER` unset/false) matches upstream startup behavior.

## Upstream updates

See [`docs/UPSTREAM_SYNC.md`](docs/UPSTREAM_SYNC.md).

## API

Point the app at your `oxplayer` API base URL (Jellyfin-shaped routes) once OX auth and server selection are implemented under `lib/oxplayer/`.
