# TDLib `td_api` Dart generator (vendored + adapted)

The files `generate.dart`, `*.tmpl`, and this README were **vendored from**
[i-Naji/tdlib](https://github.com/i-Naji/tdlib) (`generator/`, BSD-3-Clause) and adapted for **official**
`td_api.tl` from [tdlib/td](https://github.com/tdlib/td).

## Usage

From `oxplayer-client/`:

```bash
dart run tool/generator/generate.dart --fetch
```

- Downloads `td_api.tl` from `td_api_tl_raw_url` in [`tool/tdlib/TD_VERSION.json`](../tdlib/TD_VERSION.json) (unless `tool/generator/data/td_api.tl` already exists — use `--fetch` to refresh).
- Writes **`lib/td_api_generated/`** (`tdapi.dart`, `td_api.dart` export barrel, `object.dart`, `function.dart`, and all `objects/` / `functions/` parts).

Bump the git pin in `TD_VERSION.json`, then re-run with `--fetch`, then `dart run tool/tdlib/fetch_artifacts.dart` for matching native/WASM artifacts.

## Implementation notes

- Official TL uses a leading builtin block, then types, then `---functions---`; the parser’s default section is `types` until that marker (same as upstream layout in practice).
- TL type identifiers are **lowerCamelCase**; Dart class names use a small **camelCase → PascalCase** transform (`authenticationCodeTypeSms` → `AuthenticationCodeTypeSms`).
- JSON `@type` strings use `lowerFirstChar` of the Dart class name (e.g. `TdError` → `error`).
