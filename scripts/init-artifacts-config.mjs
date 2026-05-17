#!/usr/bin/env node
/**
 * Creates `tool/tdlib/artifact_config.yaml` from the example template when missing,
 * so `dart run tool/tdlib/fetch_artifacts.dart` does not fail-fast on a fresh clone.
 *
 * Defaults (no TDLIB_ARTIFACT_BASE_URL):
 *   - Resolves GitHub `owner/repo` from `TDLIB_ARTIFACT_GITHUB_REPO`, else `git remote origin`, else placeholder.
 *   - Reads `commit_sha` from `tool/tdlib/TD_VERSION.json`.
 *   - Writes base_url `https://github.com/<owner>/<repo>/releases/download/tdlib-artifacts-<commit_sha>/`
 *   - Sets `url_layout: github_release` (asset names: libtdjson-<abi>.so, dist.tar.gz).
 *
 * Override object storage: set `TDLIB_ARTIFACT_BASE_URL` (optional `TDLIB_ARTIFACT_URL_LAYOUT` =
 * `nested_commit` | `github_release`, default nested_commit).
 *
 * Cross-platform (Windows / Unix); no shell `cp`.
 */
import { execSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import process from "node:process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const clientRoot = path.join(__dirname, "..");
const tdlibDir = path.join(clientRoot, "tool", "tdlib");
const targetPath = path.join(tdlibDir, "artifact_config.yaml");
const examplePath = path.join(tdlibDir, "artifact_config.example.yaml");
const versionPath = path.join(tdlibDir, "TD_VERSION.json");

const PLACEHOLDER_REPO = "YOUR_ORGANIZATION/YOUR_REPO_NAME";

function normalizeBaseUrl(raw) {
  const trimmed = String(raw).trim();
  if (!trimmed) return "";
  return trimmed.endsWith("/") ? trimmed : `${trimmed}/`;
}

function readCommitShaSync() {
  const raw = JSON.parse(readFileSync(versionPath, "utf8"));
  const sha = typeof raw.commit_sha === "string" ? raw.commit_sha.trim() : "";
  if (sha.length < 7) {
    throw new Error(`Invalid or missing commit_sha in ${versionPath}`);
  }
  return sha;
}

function detectGithubRepo() {
  const fromEnv = process.env.TDLIB_ARTIFACT_GITHUB_REPO?.trim();
  if (fromEnv) return fromEnv;
  try {
    const out = execSync("git config --get remote.origin.url", {
      encoding: "utf8",
      cwd: clientRoot,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const m = out.match(/github\.com[:/]([^/]+\/[^/.]+?)(?:\.git)?$/i);
    if (m) return m[1];
  } catch {
    /* no git or no remote */
  }
  return PLACEHOLDER_REPO;
}

function resolveBootstrapConfig() {
  const envBase = process.env.TDLIB_ARTIFACT_BASE_URL?.trim();
  if (envBase) {
    const layoutEnv = process.env.TDLIB_ARTIFACT_URL_LAYOUT?.trim();
    const layout =
      layoutEnv === "github_release" || layoutEnv === "nested_commit"
        ? layoutEnv
        : "nested_commit";
    return { baseUrl: normalizeBaseUrl(envBase), urlLayout: layout };
  }
  const commit = readCommitShaSync();
  const repo = detectGithubRepo();
  const tag = `tdlib-artifacts-${commit}`;
  const baseUrl = normalizeBaseUrl(
    `https://github.com/${repo}/releases/download/${tag}`,
  );
  return { baseUrl, urlLayout: "github_release" };
}

async function main() {
  if (existsSync(targetPath)) {
    console.log(
      `[tdlib:bootstrap] ${path.relative(clientRoot, targetPath)} already exists — leaving unchanged.`,
    );
    process.exit(0);
  }

  if (!existsSync(examplePath)) {
    console.error(`[tdlib:bootstrap] Missing template: ${examplePath}`);
    process.exit(1);
  }

  if (!existsSync(versionPath)) {
    console.error(`[tdlib:bootstrap] Missing ${versionPath}`);
    process.exit(1);
  }

  const template = await readFile(examplePath, "utf8");
  const { baseUrl, urlLayout } = resolveBootstrapConfig();
  const quotedBase = JSON.stringify(baseUrl);

  let body = template.replace(/^base_url:\s*.+$/m, `base_url: ${quotedBase}`);
  body = body.replace(/^url_layout:\s*\S+$/m, `url_layout: ${urlLayout}`);

  if (body === template) {
    console.error(
      "[tdlib:bootstrap] Could not patch base_url / url_layout in artifact_config.example.yaml",
    );
    process.exit(1);
  }

  await writeFile(targetPath, body, "utf8");
  const repo = detectGithubRepo();
  console.log(
    `[tdlib:bootstrap] Wrote ${path.relative(clientRoot, targetPath)} (url_layout=${urlLayout}, base_url=${quotedBase}).`,
  );
  if (!process.env.TDLIB_ARTIFACT_BASE_URL) {
    console.log(
      "[tdlib:bootstrap] Defaulting to GitHub Releases URL pattern; override with TDLIB_ARTIFACT_BASE_URL or set TDLIB_ARTIFACT_GITHUB_REPO if origin is not github.com.",
    );
  }
  if (repo === PLACEHOLDER_REPO && !process.env.TDLIB_ARTIFACT_GITHUB_REPO) {
    console.log(
      `[tdlib:bootstrap] Using placeholder repo ${PLACEHOLDER_REPO}; set TDLIB_ARTIFACT_GITHUB_REPO or add a GitHub remote.`,
    );
  }
}

main().catch((err) => {
  console.error("[tdlib:bootstrap]", err);
  process.exit(1);
});
