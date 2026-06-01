# OXPlayer (`lib/oxplayer/`)

OX-only code on top of [Fladder](https://github.com/DonutWare/fladder). Upstream screens/providers stay Fladder-shaped; hook with `OxplayerConfig.isEnabled` only where required.

## Kept (product)

- **Auth:** claim-code login (`oxplayer_login_screen`, `oxplayer_telegram_auth_client` — HTTP only, no TDLib). After login, **Fladder** owns session + all Jellyfin API calls (`userProvider`, `JellyRequest`, `NavigationScaffold` → `fetchViews`, etc.).
- **Help:** `oxplayer_help_*`, `OxplayerHelpRoute`
- **Brand:** `oxplayer_brand.dart`
- **Session:** splash gate, `POST /auth/refresh`, 401 refresh interceptor, navigation to `/ox-login`

Do **not** add OX helpers that prefetch home/library or patch Fladder providers — fix **oxplayer-be** Jellyfin responses instead.

## Kept (infra)

- `oxplayer_config`, `oxplayer_env`, `oxplayer_dotenv`, `oxplayer_bootstrap`, `oxplayer_sentry`
- `oxplayer_online_status` (API session / banner; no Telegram TDLib)
- URL sync prefs (`oxplayer_persisted_url_sync` + `sync/`)

## Removed (2026 Fladder alignment)

- TDLib: `telegram/`, `lib/td_api_generated/`, `tool/tdlib/`, My Telegram routes/UI
- Catalog UX overlays: search landing, TMDB row, home banner
- Telegram playback: `oxplayer://telegram/`, sync-from-chat
- **Playback verified streams** (`lib/oxplayer/playback/`): after Exo/mpv mux discovery, POST manifest to `MediaVariants/{id}/PlayerVerifiedStreams` on oxplayer-be. Wired via `OXPLAYER_HOOK` in `media_control_wrapper.dart` only.

## Merging Fladder updates

See [`docs/UPSTREAM_SYNC.md`](../../docs/UPSTREAM_SYNC.md). Re-apply thin hooks in `main.dart`, `auto_router.dart` (`AuthGuard`, `OxplayerLoginRoute`), `splash_screen`, `login_screen`, help nav buttons.
