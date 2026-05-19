/**
 * Copies the prebuilt `tdweb` npm package (WASM + workers) into web/tdweb/
 * so Flutter web can load TDLib in the browser.
 *
 * Legacy / dev fallback: prefer `dart run tool/tdlib/fetch_artifacts.dart` with
 * artifacts matching `tool/tdlib/TD_VERSION.json` (see docs/tdlib-official-build.md).
 *
 * Resolve order for source:
 *   1) TDLIB_WEB_DIST — explicit directory containing tdweb.js
 *   2) oxplayer-client/node_modules/tdweb/dist
 *   3) repo-root/node_modules/tdweb/dist (pnpm hoisted)
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const clientRoot = path.join(__dirname, "..");
const destDir = path.join(clientRoot, "web", "tdweb");
const fetchArtifactsMarker = path.join(destDir, ".from_fetch_artifacts");

const candidates = [
  process.env.TDLIB_WEB_DIST,
  path.join(clientRoot, "node_modules", "tdweb", "dist"),
  path.join(clientRoot, "..", "node_modules", "tdweb", "dist"),
  path.join(clientRoot, "..", "..", "node_modules", "tdweb", "dist"),
].filter(Boolean);

function findSrc() {
  for (const c of candidates) {
    const js = path.join(c, "tdweb.js");
    if (fs.existsSync(js)) return c;
  }
  return null;
}

function copyRecursive(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const name of fs.readdirSync(src)) {
    const from = path.join(src, name);
    const to = path.join(dst, name);
    const st = fs.statSync(from);
    if (st.isDirectory()) copyRecursive(from, to);
    else fs.copyFileSync(from, to);
  }
}

/**
 * tdweb ships with `__webpack_require__.p = ""`, so Worker + WASM URLs resolve
 * against the **document** path (e.g. `/worker.js`) instead of `/tdweb/…`.
 * Flutter serves assets under `web/tdweb/` → 404, worker never starts, `send` hangs.
 *
 * Main bundle: use `document.currentScript` (set for dynamically inserted scripts).
 * Worker bundle: use `self.location` (worker script URL under `/tdweb/`).
 * Fallback: `new URL('tdweb/', document.baseURI)`.
 */
// Prefer global set in web/index.html before tdweb.js loads (dynamic scripts have null currentScript).
const WEBPACK_P_PATCH =
  '__webpack_require__.p = (function(){try{var g=typeof __OXPLAYER_TDWEB_PUBLIC_PATH__!="undefined"&&__OXPLAYER_TDWEB_PUBLIC_PATH__;if(g){g=String(g);return g.charAt(g.length-1)==="/"?g:g+"/";}}catch(e0){}try{if(typeof document!="undefined"&&document.currentScript&&document.currentScript.src){var u=document.currentScript.src;return u.slice(0,u.lastIndexOf("/")+1);}}catch(e){}try{if(typeof importScripts=="function"&&typeof self!="undefined"&&self.location&&self.location.href){var w=self.location.href;return w.slice(0,w.lastIndexOf("/")+1);}}catch(e2){}try{if(typeof document!="undefined"&&document.baseURI)return new URL("tdweb/",document.baseURI).href;}catch(e3){}return"tdweb/";})();';

const WEBPACK_P_RE = /__webpack_require__\.p\s*=\s*""\s*;/g;

function patchTdwebWebpackPublicPath(dir) {
  let total = 0;
  for (const name of fs.readdirSync(dir)) {
    if (!name.endsWith(".js")) continue;
    const fp = path.join(dir, name);
    if (!fs.statSync(fp).isFile()) continue;
    let text = fs.readFileSync(fp, "utf8");
    if (!WEBPACK_P_RE.test(text)) continue;
    WEBPACK_P_RE.lastIndex = 0;
    const next = text.replace(WEBPACK_P_RE, WEBPACK_P_PATCH);
    if (next === text) continue;
    fs.writeFileSync(fp, next, "utf8");
    total += 1;
    console.log("[sync-tdweb] patched __webpack_require__.p in " + name);
  }
  if (total === 0) {
    console.warn(
      "[sync-tdweb] no __webpack_require__.p = \"\" assignments found to patch (unexpected tdweb build?)",
    );
  }
}

if (fs.existsSync(fetchArtifactsMarker)) {
  console.log(
    "[sync-tdweb] skipping npm copy — web/tdweb is managed by fetch_artifacts " +
      "(.from_fetch_artifacts present). Patching public path only.",
  );
  patchTdwebWebpackPublicPath(destDir);
  process.exit(0);
}

const src = findSrc();
if (!src) {
  console.warn(
    "[sync-tdweb] tdweb dist not found. Install with:\n" +
      "  pnpm add -w tdweb   OR   cd oxplayer-client && npm install tdweb\n" +
      "Then re-run this script (or set TDLIB_WEB_DIST to the dist folder).",
  );
  process.exit(0);
}

copyRecursive(src, destDir);
console.log("[sync-tdweb] copied tdweb from\n  " + src + "\nto\n  " + destDir);
patchTdwebWebpackPublicPath(destDir);
