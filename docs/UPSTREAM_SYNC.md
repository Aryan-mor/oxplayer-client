# Syncing with upstream Fladder

This repo is a **fork-style** copy of [Fladder](https://github.com/DonutWare/fladder) (see `../refs/Fladder` in the monorepo as a read-only reference snapshot).

## Remote setup

Add the upstream remote once:

```bash
git remote add upstream https://github.com/DonutWare/fladder.git
git fetch upstream
```

## Merge or rebase

Prefer **merge** if you want fewer forced history edits:

```bash
git checkout main
git fetch upstream
git merge upstream/main
```

Resolve conflicts by **keeping upstream behavior** and re-applying OX changes only under `lib/oxplayer/` and minimal hook sites (e.g. `lib/main.dart`).

## OX guard rule

OX-only code must stay behind `OxplayerConfig.isEnabled` (`--dart-define=OXPLAYER=true`) and live in `lib/oxplayer/`. That keeps conflict surface small when merging.

## Reference tree

The workspace may keep `refs/Fladder` as a **non-git** snapshot for diffing APIs; the shipping app is this `oxplayer-client` tree.
