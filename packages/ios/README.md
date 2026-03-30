# OpenCode iOS

Native `WKWebView` shell around the shared `@opencode-ai/app` UI.

## Attribution

This iOS package is forked from [whispercode](https://github.com/DNGriffin/whispercode) by [@DNGriffin](https://github.com/DNGriffin), with adjustments made for personal use.

The restoration of the original "OpenCode" name and icon is a personal preference, while still respecting the creative adaptation by the whispercode author. If the whispercode author finds this inappropriate, we are open to making adjustments.

---

This fork should stay close to official OpenCode. Treat the iOS work here as:

- iOS packaging, signing, and native bridge code in `packages/ios`
- the minimum shared-app glue needed to let the shell work
- everything else following official `anomalyco/opencode`

## Source of truth

- Official upstream: `upstream/dev`
- Your integration branch: `origin/dev`
- Keep this fork as `official + a small iOS patch layer`

Before doing any upstream sync, rebase, or publish work, read:

- [GIT_SYNC.md](/Volumes/External/GitHub/Opencode/packages/ios/GIT_SYNC.md)

## Branch model

Use two long-lived local branches:

- `upstream-dev`
  Tracks `upstream/dev`
  Read-only mirror of official OpenCode
- `dev`
  Tracks `origin/dev`
  Your actual integration branch for iOS work

Rules:

- Do not develop on `upstream-dev`
- Rebase or merge `dev` on top of `upstream-dev`
- Push only to `origin`

## Local git config

This clone is configured with:

- `dev -> origin/dev`
- `upstream-dev -> upstream/dev`
- `remote.pushDefault = origin`
- `branch.dev.pushRemote = origin`
- `push.default = simple`
- `rerere.enabled = true`

That means:

- plain `git push` from `dev` goes to your fork
- repeated conflict resolutions are remembered

## Daily sync flow

The short version is below. The full operational guide, safety checks, and conflict handling live in:

- [GIT_SYNC.md](/Volumes/External/GitHub/Opencode/packages/ios/GIT_SYNC.md)

Refresh official mirror:

```bash
git fetch upstream
git switch upstream-dev
git merge --ff-only upstream/dev
```

Move your integration branch forward:

```bash
git switch dev
git rebase upstream-dev
```

Publish your updated integration branch:

```bash
git push origin dev
```

If you prefer merge commits instead of rebasing:

```bash
git switch dev
git merge upstream-dev
git push origin dev
```

## Conflict policy

When upstream changes collide with this fork:

- prefer upstream behavior by default
- keep iOS-only work in `packages/ios`
- keep shared-app diffs small and isolated
- if a shared-app change is still required, make it obvious and minimal

After pulling upstream changes, run:

```bash
bun run --cwd packages/app typecheck
bun run --cwd packages/ios typecheck
```

## Where changes belong

Use `packages/ios` for:

- Swift code
- Xcode project changes
- native bridge methods
- iOS entry and shell-specific web glue

Touch `packages/app` only when the shared UI needs a thin bridge-aware adjustment.

Avoid expanding the fork into general product behavior changes.

## Current shared-app delta

Keep this fork-specific surface small. At the moment the intended shared-app delta is limited to:

- `context/platform.tsx`
- `context/notification.tsx`
- `utils/persist.ts`
- `context/global-sync.tsx`
- `pages/session.tsx`
- `components/prompt-input.tsx`
- `components/session-header.tsx`
- `components/dialog-settings.tsx`
- `index.css`
- `app.tsx`
- `packages/ui/src/components/dialog.tsx`

If this list grows, stop and reconsider whether the change really belongs outside `packages/ios`.

## Must-keep iOS-facing behavior during upstream sync

This fork now has five shared-UI behaviors that must survive any sync from `upstream/dev`.
If upstream refactors the surrounding code, preserve the behavior with the thinnest possible iOS-specific adapter instead of carrying large fork diffs.

1. iOS session header reload button
   - Keep the iOS-only full reload button in the session header.
   - The action must continue to trigger a full app reload via `platform.restart()` or an equivalent full refresh path.

2. iOS prompt agent label compaction
   - Keep the iOS-only compact label rendering in the prompt agent picker.
   - Parenthesis content may be removed differently after refactors, but the rendered label must stay short and width-efficient.

3. Narrow-layout settings tabs stay horizontal and icon-only
   - Keep the settings tab row horizontal on narrow/mobile layout.
   - Keep trigger labels icon-only in that narrow layout.

4. iOS notifications remain bridged and badge-synced
   - Keep native iOS notification delivery working through the bridge layer in `packages/ios`.
   - Keep shared-app viewed/unseen state synchronized back to the iOS app icon badge.
   - Viewing a notification target or opening a notification from iOS must not leave a stale badge behind.

5. iOS settings dialog stays fullscreen without making the main shell fullscreen
   - Keep fullscreen behavior scoped to the Settings dialog only.
   - Do not make the root iOS webview ignore the top safe area just to enlarge Settings.
   - Preserve the iOS fullscreen dialog class path across the shared app and UI wrapper so the dialog fills the screen while the main shell keeps normal safe-area behavior.

## Develop

From repo root:

```bash
bun install
bun run --cwd packages/ios dev
```

Run the OpenCode server separately and point the iOS shell at it during onboarding.

## Build web assets

```bash
bun run --cwd packages/ios build
```

This writes `packages/ios/WebAssets/`.

The Xcode project expects `packages/ios/OpenCode/OpenCode/WebAssets` to exist as a symlink to that directory. Run the build once before the first Xcode build, or after cleaning `WebAssets`.

Optional check:

```bash
./packages/ios/script/ensure-web-assets.sh
```

## Xcode

Open:

- `packages/ios/OpenCode/OpenCode.xcodeproj`

Keep `PRODUCT_BUNDLE_IDENTIFIER`, signing, `MARKETING_VERSION`, and `CURRENT_PROJECT_VERSION` aligned with how you ship the app.

## Versions

- In-app version comes from `packages/ios/package.json`
- App icon / Xcode-visible version comes from the Xcode project settings

Keep them in sync when you want one visible version everywhere.
