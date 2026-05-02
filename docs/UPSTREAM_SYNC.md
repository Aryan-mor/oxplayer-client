# Syncing with upstream Fladder

This repo is a **fork-style** copy of [Fladder](https://github.com/DonutWare/fladder) (see `../refs/Fladder` in the monorepo as a read-only reference snapshot).

**Note:** This tree was imported with **separate Git history** from Fladder, so `git merge upstream/...` often errors with *unrelated histories*. Use **commit-by-commit porting** (see `.cursor/rules/fladder-upstream-sync.mdc` and `git show upstream/develop` / `upstream/main`).

## Remote setup

Upstream (read-only reference for merges):

```bash
git remote add upstream https://github.com/DonutWare/fladder.git
git fetch upstream
```

Your own repository (push target for this project):

```bash
git remote add origin https://github.com/Aryan-mor/oxplayer-client.git
git push -u origin main
```

If `origin` already exists but points to the wrong URL: `git remote set-url origin <new-url>`.

## Merge or rebase

Prefer **merge** if you want fewer forced history edits:

```bash
git checkout main
git fetch upstream
git merge upstream/main
```

Resolve conflicts by **keeping upstream behavior** and re-applying OX changes only under `lib/oxplayer/` and minimal hook sites (e.g. `lib/main.dart`).

## OX guard rule

OX-only code must stay behind `OxplayerConfig.isEnabled` (on by default; `--dart-define=OXPLAYER=false` to turn off) and live in `lib/oxplayer/`. That keeps conflict surface small when merging.

## Reference tree

The workspace may keep `refs/Fladder` as a **non-git** snapshot for diffing APIs; the shipping app is this `oxplayer-client` tree.
