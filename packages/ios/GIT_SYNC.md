# Git Sync Guide

This file is the source of truth for how this fork follows official OpenCode while preserving the iOS integration work.

If a future session needs to sync upstream, rebase the fork, or push updates, read this file first and follow it exactly.

## Model

- `upstream/dev`
  Official OpenCode source of truth
- `origin/dev`
  Your published integration branch
- local `upstream-dev`
  Local mirror of `upstream/dev`
- local `dev`
  Local working branch for this fork

Rules:

- Never develop on `upstream-dev`
- Never push to `upstream`
- Keep fork-specific work on `dev`
- Keep iOS work in `packages/ios` whenever possible
- Keep shared-app glue minimal and easy to review

## What is already configured

This repo is intended to use:

- `dev -> origin/dev`
- `upstream-dev -> upstream/dev`
- `remote.pushDefault = origin`
- `branch.dev.pushRemote = origin`
- `push.default = simple`
- `rerere.enabled = true`

Check with:

```bash
git branch -vv
git remote -v
git config --get-regexp '^(remote\.pushDefault|branch\.dev\.pushRemote|push\.default|rerere\.enabled|branch\.upstream-dev\.remote|branch\.upstream-dev\.merge|branch\.dev\.remote|branch\.dev\.merge)$'
```

## Standard flow

### 1. Save current work first

If there are uncommitted changes, do not sync upstream yet.

Either:

```bash
git status --short
git add -A
git commit -m "feat(ios): ... "
```

Or create a temporary backup branch before doing any history changes:

```bash
git branch backup/pre-sync-YYYYMMDD-N
```

If there are unrelated untracked directories, exclude them intentionally from the commit.

## 2. Refresh the official mirror

```bash
git fetch upstream
git switch upstream-dev
git merge --ff-only upstream/dev
```

Result:

- local `upstream-dev` becomes an exact mirror of current official `upstream/dev`

## 3. Move the fork branch onto latest upstream

```bash
git switch dev
git rebase upstream-dev
```

This keeps history clean:

- official commits first
- fork commit(s) on top

## 4. Resolve conflicts carefully

If rebase stops on conflicts:

```bash
git status
```

Then:

- Prefer upstream behavior by default
- Re-apply only the smallest iOS-specific patch needed
- Keep changes inside `packages/ios` where possible

Continue with:

```bash
git add <resolved-files>
git rebase --continue
```

If the rebase is clearly wrong:

```bash
git rebase --abort
```

## 5. Verify after rebase

Run:

```bash
bun run --cwd packages/app typecheck
bun run --cwd packages/ios typecheck
```

Optionally inspect branch relationship:

```bash
git rev-list --left-right --count dev...upstream/dev
git rev-list --left-right --count dev...origin/dev
git log --oneline --max-count=10 dev
```

Healthy result usually looks like:

- `dev` is ahead of `upstream/dev` by your fork commit count
- `dev` is ahead of `origin/dev` until you push

## 6. Publish

```bash
git push origin dev
```

Do not push `upstream-dev`.

That branch is only a local reference line. Your real backup is `origin/dev`, because that is where the fork changes live.

## Common pitfall: rebase to origin instead of upstream

**CRITICAL: Always rebase onto `upstream/dev` or `upstream-dev`, NEVER onto `origin/dev`.**

### What went wrong (March 2026)

A session accidentally ran:

```bash
git fetch origin
git rebase origin/dev
```

This **DOES NOT** sync with official OpenCode. It only syncs with your own fork.

**Result:**

- Local `dev` became aligned with `origin/dev` (your fork)
- But `origin/dev` was **already forked** from `upstream/dev`
- GitHub showed: `82 commits ahead and 82 commits behind anomalyco/opencode:dev`
- History had diverged, not converged

### Why this happens

Your fork (`origin/dev`) can drift from official (`upstream/dev`) over time. If you rebase onto `origin/dev`:

- You're stacking your new work on top of **your old fork history**
- You never pull in the latest official commits
- The fork continues to diverge from upstream

### Correct approach

```bash
# WRONG - rebase onto your own fork
git rebase origin/dev    # ❌ NEVER DO THIS

# CORRECT - rebase onto official upstream
git fetch upstream       # ✅ Get latest official state first
git rebase upstream/dev  # ✅ Stack your work on official commits
```

### How to fix if you've already rebased onto origin

If you accidentally rebased onto `origin/dev` and created a diverged history:

```bash
# 1. Reset to the state before the wrong rebase (use git reflog if needed)

# 2. Rebase onto the CORRECT base
git fetch upstream
git rebase upstream/dev

# 3. Resolve conflicts (if any)
git add <resolved-files>
git rebase --continue

# 4. Force push to origin
git push origin dev --force-with-lease
```

### Visual comparison

```
WRONG (rebase onto origin/dev):
  upstream/dev: A -- B -- C -- D -- E
  origin/dev:   A -- B -- X -- Y -- Z (forked at B)
  local/dev:    A -- B -- X -- Y -- Z -- M -- N (stacked on fork)

  Result: diverged from upstream, still has old fork history


CORRECT (rebase onto upstream/dev):
  upstream/dev: A -- B -- C -- D -- E
  local/dev:    A -- B -- C -- D -- E -- M -- N (stacked on upstream)

  Result: clean linear history on top of latest official
```

### Checklist before pushing

Before pushing to `origin/dev`, verify:

```bash
# Check you're actually on top of upstream
git log --oneline upstream/dev..HEAD
git rev-list --left-right --count upstream/dev...dev
```

Should show:

- `0 ahead, N behind` or just commits ahead
- **NOT** `N ahead, M behind` with both N and M > 0

If you see both ahead and behind counts > 0, you have diverged. Rebase onto `upstream/dev` first.

## Recovery notes

If local files are lost but `origin/dev` exists, your fork work is not lost.

Recovery is:

```bash
git clone <your-fork>
cd opencode
git remote add upstream https://github.com/anomalyco/opencode.git
git fetch upstream
git branch --track upstream-dev upstream/dev
```

Your integration work comes from `origin/dev`, not from `upstream-dev`.

## Practical policy for this fork

When in doubt:

- upstream behavior wins
- keep the fork patch layer small
- prefer one clear fork commit or a small number of focused commits
- document branch and sync logic here instead of scattering it across root docs

## Must-keep iOS UI patches (Shared-app invariants)

The bullets below are iOS-facing UI behaviors implemented in the shared `packages/app` UI.
During any sync/rebase/merge from `upstream/dev`, treat these as invariants:
upstream may change the underlying code structure, but the user-visible behavior must remain the same.

Re-apply only the thinnest iOS-specific adapter needed to preserve each invariant.
Prefer upstream code by default, then layer the smallest iOS-only logic on top.

1. iOS session header: "Reload" (full page refresh) button
   - What must remain: on `platform.platform === "ios"`, the session header shows a refresh/reset button next to the status control.
   - What it must do: clicking the button triggers a full reload (not just a silent data refresh).
   - Current touchpoint: `packages/app/src/components/session/session-header.tsx` (`reload()` uses `platform.restart()` and is rendered in an iOS-only block).
   - How to preserve after upstream changes:
     - Keep the iOS-only conditional rendering.
     - Keep the action wired to a full reload (`platform.restart()` / equivalent).
     - If upstream refactors the header component, re-locate the iOS-only button into the new structure instead of removing it.

2. Agent picker in prompt input: trim parenthesis text for compact width
   - What must remain: on iOS, the agent selector label shown in the prompt UI removes the bracketed/parenthesis part (and keeps only the agent name).
   - Why it matters: the width is intentionally reduced; parentheses + content must not consume horizontal space.
   - Current touchpoint: `packages/app/src/components/prompt-input.tsx` (`compact()` removes `(...)` content, and the agent select `label()` uses `platform.platform === "ios" ? compact(value) : value`).
   - How to preserve after upstream changes:
     - Preserve the iOS-only label transformation behavior (exact regex can change, but the rendered result must stay equivalent).
     - Keep the transformation limited to the displayed label (do not alter the underlying agent identity/config).
     - If upstream changes how the agent select renders its label, re-apply the iOS-only transformation at the new rendering boundary.

3. Settings dialog tabs: horizontal + icon-only on narrow/mobile layout
   - What must remain: the settings dialog uses horizontal tab triggers (not a vertical list) and the triggers are icon-only to save width on narrow layouts (including iOS webview).
   - Current touchpoints:
     - `packages/app/src/components/dialog-settings.tsx` (tabs `orientation` switches to `"horizontal"` on mobile and the mobile trigger renders `<Icon />` without text).
     - `packages/ui/src/components/tabs.css` (settings variant styles for `[data-orientation="horizontal"]`).
   - How to preserve after upstream changes:
     - Preserve the mobile/narrow orientation decision.
     - Preserve the icon-only trigger rendering (no text labels in the trigger row).
     - If upstream refactors the tabs implementation, ensure the same visual/behavioral end state using the smallest possible adapter (rather than copying large upstream blocks).

4. iOS notifications: bridge + app icon badge sync
   - What must remain: native notifications triggered through the iOS shell continue to work, and app-side viewed/unseen state stays synchronized with the iOS app icon badge.
   - Why it matters: the fork now has explicit iOS notification support; upstream sync must not silently keep notifications working while leaving stale badge state behind.
   - Current touchpoints:
     - `packages/app/src/context/platform.tsx` (`setNotificationBadge` bridge method in the shared platform contract).
     - `packages/app/src/context/notification.tsx` (shared unseen/viewed state drives iOS badge updates).
     - `packages/ios/src/entry-ios.tsx` (iOS platform implementation wires `setNotificationBadge` into the native bridge).
     - `packages/ios/OpenCode/OpenCode/Bridge/PlatformBridge.swift` (`setNotificationBadge` handler).
     - `packages/ios/OpenCode/OpenCode/Bridge/PushBridge.swift` (`setBadge(_:)`).
     - `packages/ios/OpenCode/OpenCode/App/OpenCodeApp.swift` (notification tap path clears badge before opening content).
   - How to preserve after upstream changes:
     - Keep native notification delivery and native notification-open handling intact.
     - Keep shared unseen/viewed state capable of driving badge updates through the platform bridge.
     - Do not fall back to clearing badge only on app foreground; opening or viewing the related content must also clear stale badge state.

5. iOS Settings dialog: fullscreen dialog only
   - What must remain: the Settings dialog itself becomes fullscreen on iOS, while the main shell remains under normal top safe-area constraints.
   - Why it matters: making the root shell fullscreen causes overlap with the iPhone status area / Dynamic Island region and can make top controls hard to tap.
   - Current touchpoints:
     - `packages/app/src/components/dialog-settings.tsx` (applies the iOS fullscreen dialog class).
     - `packages/app/src/index.css` (iOS fullscreen dialog rules target the outer dialog, container, and content).
     - `packages/ui/src/components/dialog.tsx` (must propagate the dialog class to the root `[data-component="dialog"]` wrapper, not only the inner content node).
     - `packages/ios/OpenCode/OpenCode/App/ContentView.swift` (must keep normal top safe-area behavior for the main shell).
   - How to preserve after upstream changes:
     - Keep fullscreen styling scoped to the Settings dialog path only.
     - Preserve the class propagation path from `DialogSettings` into the root dialog wrapper.
     - Do not reintroduce root-shell fullscreen as a workaround.

After any sync, verify the five invariants manually in the running app:

- open a session on iOS and confirm the reload button exists and reloads
- open prompt input and confirm the agent selector label is trimmed (parenthesis text removed)
- open settings and confirm tab triggers are horizontal and icon-only on the narrow layout
- trigger an iOS notification, open or view the related content, and confirm the app icon badge clears correctly
- open Settings on iOS and confirm the dialog itself is fullscreen while the main shell still respects the top safe area
