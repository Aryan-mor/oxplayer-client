# TDLib for web (`tdweb`)

OXPlayer Flutter **web** loads Telegram TDLib via the official prebuilt
[`tdweb`](https://www.npmjs.com/package/tdweb) package (WebAssembly + workers).

## One-time setup

1. Install the pinned npm package (version is fixed in `oxplayer-client/package.json`):

   ```bash
   cd oxplayer-client && npm install
   ```

   (Legacy: `pnpm add -w tdweb@1.8.0` at the monorepo root also works if `node_modules/tdweb` resolves there.)

2. Copy binaries into `web/tdweb/`:

   ```bash
   node scripts/sync-tdweb.mjs
   ```

   Optional: set `TDLIB_WEB_DIST` to an explicit `tdweb` **dist** directory.

3. Ensure `web/index.html` loads `tdweb/tdweb.js` before `oxplayer_tdweb_bridge.js`
   (already wired in the repo).

`pnpm flutter:web` from the `oxplayer` package runs `sync-tdweb` automatically when
the `tdweb` package is present.

## Git

Large `.wasm` / worker chunks are gitignored; each clone needs `sync-tdweb`
(or CI step) before `flutter build web`.
