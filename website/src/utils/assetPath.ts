/**
 * Prefix public asset paths for GitHub Pages project sites (/oxplayer-client).
 * Set via next.config env (NEXT_PUBLIC_BASE_PATH).
 */
export function assetPath(path: string): string {
  const base = process.env.NEXT_PUBLIC_BASE_PATH ?? "";
  const normalized = path.startsWith("/") ? path : `/${path}`;
  return `${base}${normalized}`;
}
