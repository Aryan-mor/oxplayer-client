# OXPlayer layer

All OX-specific behavior lives under `lib/oxplayer/`. Upstream Fladder code should stay unchanged except for **thin hooks** (e.g. `main.dart`) that call into this folder behind `OxplayerConfig.isEnabled`.

- `oxplayer_config.dart` — OX mode is **on by default**; use `--dart-define=OXPLAYER=false` for vanilla Fladder login.
- `oxplayer_bootstrap.dart` — startup hooks before/after `bootstrapApplication`.

Do **not** add OX business logic across `lib/**` outside this directory; extend `OxplayerBootstrap` or add new files here.
