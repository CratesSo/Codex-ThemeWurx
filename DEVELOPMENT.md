# Codex ThemeWurx Development

This is the field manual.

Use it to run, debug, and extend the app without rediscovering the same state seams.

## Purpose

Codex ThemeWurx is a native macOS menu bar app that:

- loads custom light and dark chrome themes from `themes/custom-themes.md`
- lets you edit, create, delete, reorder, favorite, and preview themes from a native manager window
- applies selected themes through Codex's Chromium debugger when available, then through macOS Accessibility without relaunching Codex
- exposes a native settings window for first-party global theme hotkeys
- falls back to writing selected themes into Codex's current appearance store if neither live path can apply them
- keeps one backup of that appearance store
- watches both files for changes

The app does not add themes into Codex's built-in picker. It overrides the light or dark chrome slot that Codex already reads.

## Canonical Paths

- Repository and app project root: the checkout directory, embedded at build time through `META_REPO_ROOT = $(SRCROOT)`
- Editable theme file: `themes/custom-themes.md` (untracked and Git-ignored)
- Shipped defaults: [`themes/default-themes.md`](themes/default-themes.md) (tracked, system-font catalog)
- Theme manager backup: `themes/custom-themes.theme-bar.backup.md`
- Current Codex appearance state: `~/.codex/config.toml`, under `[desktop]`
- Current appearance backup: `~/.codex/config.theme-bar.backup.toml`
- Legacy appearance state and backup: `~/.codex/.codex-global-state.json` and `~/.codex/.codex-global-state.theme-bar.backup.json`

`AppPaths.make()` in [`AppPaths.swift`](App/AppPaths.swift) is the source of truth for all of these.

If the editable theme file is missing, Codex ThemeWurx restores it from the managed theme-file backup, or copies the shipped defaults if no backup exists. Existing personal catalogs are never overwritten.

## Architecture

### App Layer

Files in [`App/`](App):

- [`CodexThemeBarApp.swift`](App/CodexThemeBarApp.swift): SwiftUI settings window, theme manager window, and built-in shortcut recorder
- [`AppDelegate.swift`](App/AppDelegate.swift): boots the model and menu controller plus the owned shortcuts and manager windows
- [`CodexAppearanceImporter.swift`](App/CodexAppearanceImporter.swift): targets Codex's main renderer, finds the live query client, and runs Codex's internal appearance actions
- [`ThemeBarModel.swift`](App/ThemeBarModel.swift): main app state, file reloads, apply/restore actions
- [`StatusMenuController.swift`](App/StatusMenuController.swift): menu bar UI
- [`SoftReloadCoordinator.swift`](App/SoftReloadCoordinator.swift): kills Codex, waits, then relaunches it normally or with the live bridge flag
- [`AppPaths.swift`](App/AppPaths.swift): path resolution

### Core Layer

Files in [`Core/`](Core):

- [`ThemeModels.swift`](Core/ThemeModels.swift): shared theme types, favorite flag, managed-theme row models, hotkey models, cycle planner, and hotkey preferences store
- [`ThemeMarkdownParser.swift`](Core/ThemeMarkdownParser.swift): parses, rewrites, deletes, and reorders heading + key-value theme entries
- [`ThemeShareString.swift`](Core/ThemeShareString.swift): encodes Codex `codex-theme-v1:` import strings
- [`CodexGlobalStateStore.swift`](Core/CodexGlobalStateStore.swift): read, apply, and backup
- [`FileWatchdog.swift`](Core/FileWatchdog.swift): filesystem watching

### Tests

Files in [`Tests/`](Tests):

- [`ThemeMarkdownParserTests.swift`](Tests/ThemeMarkdownParserTests.swift)
- [`CodexGlobalStateStoreTests.swift`](Tests/CodexGlobalStateStoreTests.swift)

Current tests cover parser, markdown rewrite behavior, state-store behavior, theme-cycle behavior, duplicate hotkey validation, and hotkey preferences persistence. They do not cover menu wiring, live hotkey delivery, restart behavior, or file-watch timing.

## Runtime Flow

Boot path:

1. [`AppDelegate.swift`](App/AppDelegate.swift) creates `ThemeBarModel` and `StatusMenuController`.
2. `ThemeBarModel.start()` calls `ThemeBarPaths.prepareThemeFile()` to preserve an existing personal catalog, restore a missing one from its local backup, or seed it from the shipped defaults.
3. Launch at Login is controlled from ThemeWurx Settings through `SMAppService.mainApp`; startup does not change the user's choice.
4. `start()` loads the theme markdown and live Codex state.
5. `start()` records whether the live bridge is available, but does not relaunch Codex automatically.
6. `start()` starts watchers on the theme file and Codex global state.
7. `ThemeHotkeyController.start()` loads persisted hotkey preferences, registers global shortcuts, and disables defaults if registration fails.

Theme manager path:

1. The menu opens `Theme Manager…` through an app-owned window in [`AppDelegate.swift`](App/AppDelegate.swift).
2. The manager reads live `ThemeBarModel` rows for light and dark sections.
3. The split editor keeps unsaved drafts in memory; Save, delete, favorite, and move actions rewrite `custom-themes.md`.
4. The first mutation in a manager session writes or replaces `custom-themes.theme-bar.backup.md`.
5. The model reloads the catalog so menu entries, active labels, and hotkey cycling all reflect the new order immediately.

Apply path:

1. Menu click calls `ThemeBarModel.applyTheme(...)`.
2. The model passes the selected `ThemeFilePayload` to [`CodexAppearanceImporter.swift`](App/CodexAppearanceImporter.swift), which builds Codex's custom chrome-theme patch from `codexPatchObject()`.
3. The importer connects to Codex's Chromium debugger on `127.0.0.1:9222`.
4. The importer evaluates renderer JavaScript as a Chrome DevTools Protocol text-frame message.
5. The renderer script walks the React fiber tree to find Codex's live query client.
6. The renderer script resolves Codex's hashed app-action registry module and calls Codex's internal `app.appearance.set_mode` plus `app.appearance.set_theme` actions with that query client.
7. Codex ThemeWurx first applies the selected preset code theme id, then applies the custom chrome-theme patch so the live renderer and stored code-theme id stay aligned.
8. If the live bridge is unavailable, the model starts an asynchronous, latest-wins Accessibility apply using the canonical `ThemeShareString` payload.
9. Accessibility opens Codex Settings, selects Appearance, selects Light or Dark to expose that slot's `Import Light/Dark theme` popup button, imports the theme, and returns to the previous Codex view with the `Back` button, or restores the previous settings section if Settings was already open. Web controls use verified focus and keyboard activation because Chromium can acknowledge AXPress without invoking their handlers. Import completion is checked by the dialog closing, not the mode radio's empty AXValue. User input cancels the operation safely.
10. Missing permission prompts once per Codex ThemeWurx launch and asks the user to reselect after granting access.
11. If Accessibility cannot apply, Codex ThemeWurx asks before using [`CodexGlobalStateStore.swift`](Core/CodexGlobalStateStore.swift) to stop Codex, write the selected slot, and relaunch normally. Renderer action rejections are reported without bypassing Codex validation.
12. Model reloads state and refreshes active menu-item styling.

Hotkey path:

1. A global shortcut fires through the Carbon registrar in [`AppDelegate.swift`](App/AppDelegate.swift).
2. `ThemeHotkeyController` dispatches light-cycle, dark-cycle, or favorite-cycle plus direction, or the separate Swap Colors and Toggle Last Light/Dark actions.
3. `ThemeBarModel.applyHotkey(...)` uses `ThemeCyclePlanner` to pick the next entry in file order, with wrap-around. Favorite hotkeys use one mixed favorites list across both variants. Cycling advances a separate intended selection immediately, even while another theme is loading.
4. The theme-name popup updates immediately on every cycling hotkey press, with foreground/background swatches anchored to its right edge. Holding any of the shortcut's modifiers keeps cycling in selection-only mode. After all shortcut modifiers are released, a 275 ms quiet period applies the final selection; pressing them again resets that period. Current modifier flags are sampled only while a selection is pending, without requiring keyboard-monitoring permission. `ThemeHotkeyApplyQueue` allows one active apply and replaces the pending destination on each press. The live importer runs off the main actor; older completions cannot clear the latest selection or announce it as applied.
5. Hotkey apply tries the live importer first, then uses the same Accessibility importer as menu clicks when the live bridge is unavailable. A new shortcut cancels an active Accessibility operation, and the next apply waits for it to exit. Menu applies, previews, appearance toggles, and bridge relaunches also wait for active work before proceeding. Cycling hotkeys never write fallback state; Swap Colors and Toggle Last Light/Dark use the menu paths and can offer confirmed restart recovery.
6. If Codex is closed or Accessibility is unavailable, cycling reports the failure and leaves persisted Codex state untouched.

## Theme File Contract

The editable file is `custom-themes.md`. Optional `##` headings within each variant group themes into folders; themes before a folder heading are unfiled.

Each entry must be:

1. A `# LIGHT THEMES` or `# DARK THEMES` section heading
2. A `###` theme heading
3. Followed by key-value lines

Example:

```md
# LIGHT THEMES

### Light 01 - Example
variant: `light`
foreground: `#905e7e`
background: `#faf4ed`
accent: `#d7827e`
diff-added: `#56949f`
diff-removed: `#797593`
contrast: `68`
code-font: `Berkeley Mono Trial`
ui-font: `IBM Plex Mono`
content-font: `"IBM Plex Sans"`
content-font-family: `IBM Plex Sans`
content-font-full-name: `IBM Plex Sans Regular Medium`
content-font-postscript-name: `IBMPlexSans-Medium`
opaque-window: `true`
theme-id: `rose-pine`
favorite: `true`

# DARK THEMES
```

Rules:

- `variant` must be `light` or `dark`
- `theme-id` maps to `codeThemeId`, passed to Codex's importer and written by the fallback path
- color fields must be valid Codex theme colors
- Codex requires `semanticColors.skill` in imported themes; Codex ThemeWurx derives it from `accent` and does not store a separate skills color.
- invalid entries are skipped, not fatal
- parse issues are shown in the menu
- Optional `code-font-*`, `ui-font-*`, and `content-font-*` face fields round-trip through drafts, markdown, and Codex exports. Omit the content font fields for themes that inherit the UI font.

The parser is intentionally dumb and strict. See [`ThemeMarkdownParser.swift`](Core/ThemeMarkdownParser.swift).

## Codex State Contract

The current Codex desktop build stores appearance in `~/.codex/config.toml`. The scalar keys below live in `[desktop]`; the chrome themes live in nested `[desktop.appearanceLightChromeTheme]` and `[desktop.appearanceDarkChromeTheme]` tables. Codex ThemeWurx uses this file when present and falls back to the legacy global-state JSON otherwise.

- `appearanceTheme`
- `appearanceLightChromeTheme`
- `appearanceDarkChromeTheme`
- `appearanceLightCodeThemeId`
- `appearanceDarkCodeThemeId`

Behavior:

- applying a light theme mutates `appearanceLightChromeTheme` and `appearanceLightCodeThemeId`
- applying a dark theme mutates `appearanceDarkChromeTheme` and `appearanceDarkCodeThemeId`
- `appearanceTheme` is set to the selected light or dark variant during live apply so the chosen slot becomes visible immediately
- a mode-only fallback changes only the `appearanceTheme` value, preserving both slot tables and code-theme IDs
- TOML edits preserve unrelated lines; legacy JSON edits preserve unrelated keys semantically
- a Rose Pine code-theme ID can be the native preset used to carry a custom chrome patch; Codex ThemeWurx matches saved slots against both the chrome theme and code-theme ID
- Toggle Last Light/Dark uses a matching Codex ThemeWurx theme in the destination slot; if the slot does not match the catalog, it applies the first catalog theme for that appearance

Live bridge behavior:

- `CodexAppearanceImporter` prefers the main `app://-/index.html` renderer, including `hostId=local` builds, and ignores hidden `initialRoute=%2Fhotkey-window` pages
- Chrome DevTools Protocol messages must be sent as WebSocket text frames
- visible repaint comes from Codex's own `app.appearance.set_mode` and `app.appearance.set_theme` actions with the live query client
- Accessibility fallback uses the current English Codex control names and a ten-second total readiness deadline; unresolved controls fail safely
- menu applies, Theme Manager eye-button applies, and hotkeys use Accessibility when the live bridge is unavailable; automatic editor previews require the live bridge, while extraction can fall back to saved appearance state
- Codex relaunch resolves the installed application by bundle id (`com.openai.codex`) instead of assuming an application filename
- browser-level reload is banned for `app://` routes because it can land Codex on `chrome-error://chromewebdata/`
- partial CSS-variable patching is banned because it leaves derived UI colors inconsistent
- cycling hotkeys never use the disk-write fallback path; they use Accessibility when the live bridge is unavailable

Important:

- Codex can flush stale in-memory prefs on shutdown
- because of that, the helper must stop Codex before writing
- writing first and quitting later is the wrong order

That ordering lives in [`SoftReloadCoordinator.swift`](App/SoftReloadCoordinator.swift) and [`ThemeBarModel.swift`](App/ThemeBarModel.swift).

## Build And Run

The generated Xcode project is checked in. Regenerate it only after changing `project.yml` (requires XcodeGen):

```bash
./generate-project.sh
```

Build:

```bash
xcodebuild -project CodexThemeBar.xcodeproj -scheme CodexThemeBar -configuration Debug build
```

Aurora requires the compiled `MenuAurora.metal` shader in the app's `default.metallib`. Use `bash scripts/build-local.sh` for local builds: it restores a missing Metal toolchain from `.build/toolchains`, or downloads and caches it if needed, then builds into `.build/local`. Xcode installs the toolchain system-wide; the exported bundle stays local and Git-ignored. Do not exclude the shader from runnable builds. The menu skips the Aurora overlay when the library or function is unavailable so menu contents remain readable.

Signing:

Builds use ad-hoc signing by default; no Apple Developer account or personal certificate is required. A stable local identity can preserve Accessibility authorization across rebuilds. To opt in, run `scripts/create-local-signing-cert.sh`, then add `CODE_SIGN_IDENTITY="Codex ThemeWurx Local"` to your build command. The helper creates and imports a local signing key into your login keychain; it is optional and is never run by the build.

Test:

```bash
xcodebuild -project CodexThemeBar.xcodeproj -scheme CodexThemeBar -destination 'platform=macOS' test
```

Launch `Codex ThemeWurx.app` from Xcode's Debug build products. `META_REPO_ROOT` resolves to `$(SRCROOT)` at build time; keep the checkout in place while using the app, and rebuild after moving it.

## Day-To-Day Usage

Typical operator loop:

1. Edit `custom-themes.md` or create/edit theme in Theme Manager.
2. ThemeWurx auto-reloads the file
3. Pick a theme from `Light Themes` or `Dark Themes`, or trigger a configured global hotkey
4. Codex ThemeWurx updates Codex through the renderer bridge or Accessibility and updates active menu-item styling

Visible menu:

- Active indicators mark matching saved themes; connection status appears under Live Bridge in Settings
- `Light Themes` and `Dark Themes` contain loaded theme entries grouped by folder; `Favorites` appears when any themes are favorited
- `Parse issues` lists up to eight catalog parsing errors
- `Keyboard Shortcuts…` opens the native settings window for global hotkey editing
- `Theme Manager…` opens the native split-view theme editor and manager window
- `Save Backup`, `Load Backup`, `Show Theme File in Finder`, and `Reload Theme File` live under the manager window's `Theme File` menu
- `Relaunch Codex With Live Bridge` in Settings manually restarts Codex with `--remote-debugging-port=9222` when live theming needs the bridge
- `Quit` and `Settings...` live in the More (ellipsis) submenu, separated by a divider

Model status properties:

- `reloadStatus`
- `refreshStatus` (shown under Live Bridge in Settings)

## Known Debt

- No automated tests cover `FileWatchdog` timing or restart behavior.

## Safe Extension Points

If adding features, keep these seams clean:

- theme parsing logic: [`ThemeMarkdownParser.swift`](Core/ThemeMarkdownParser.swift)
- state mutation contract: [`CodexGlobalStateStore.swift`](Core/CodexGlobalStateStore.swift)
- live import automation: [`CodexAppearanceImporter.swift`](App/CodexAppearanceImporter.swift)
- restart behavior: [`SoftReloadCoordinator.swift`](App/SoftReloadCoordinator.swift)
- menu UX: [`StatusMenuController.swift`](App/StatusMenuController.swift)
- hotkey registration and settings UI: [`AppDelegate.swift`](App/AppDelegate.swift) and [`CodexThemeBarApp.swift`](App/CodexThemeBarApp.swift)

Preferred rules:

- edit only the local `custom-themes.md`; keep the tracked default catalog unchanged during normal app use
- keep one theme-file backup and one appearance-state backup
- keep theme-file management on the markdown file only; do not add a second persistence path
- use Codex's renderer bridge, then Accessibility, before direct state fallback
- keep cycling hotkeys on the live bridge or Accessibility; require confirmation for restart recovery on other actions
- keep repaint correct; do not partially patch CSS variables unless the full Codex theme derivation and internal cache update path are ported
- mutate only the relevant appearance keys in fallback
- do not add parallel config paths
- test parser, share strings, and state writes after every real change

## Common Changes

### Add or edit themes

Edit `custom-themes.md` for personal changes; these are ignored by Git. Edit `themes/default-themes.md` only when intentionally changing the defaults shipped to users. No code change needed.

### Change where files live

Edit [`AppPaths.swift`](App/AppPaths.swift).

### Change what gets written into Codex state

Edit [`CodexGlobalStateStore.swift`](Core/CodexGlobalStateStore.swift) and update [`CodexGlobalStateStoreTests.swift`](Tests/CodexGlobalStateStoreTests.swift).

### Change menu behavior

Edit [`StatusMenuController.swift`](App/StatusMenuController.swift) and usually [`ThemeBarModel.swift`](App/ThemeBarModel.swift).

### Change restart strategy

Edit [`SoftReloadCoordinator.swift`](App/SoftReloadCoordinator.swift).

### Change live import strategy

Edit [`CodexAppearanceImporter.swift`](App/CodexAppearanceImporter.swift). Keep the debugger path pointed at the main renderer plus Codex's own appearance actions. Keep the Accessibility path aligned with Codex's current Appearance controls unless Codex exposes a real public IPC or deeplink.

## Pre-Ship Checklist

- build succeeds
- tests pass
- theme file still parses
- apply light theme imports through Codex or writes only the light fallback keys
- apply dark theme imports through Codex or writes only the dark fallback keys
- live apply targets the main renderer, not hotkey-window pages
- README and this doc still match reality
