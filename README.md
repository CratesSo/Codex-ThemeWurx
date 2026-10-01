# Codex ThemeWurx

A native macOS menu bar app for managing and applying custom themes in Codex. Organize themes in folders, edit colors and fonts, save favorites, and cycle through them with global keyboard shortcuts.

The integration uses Codex's internal appearance controls and can need updates when Codex changes.

## Requirements

- macOS 26 or later
- Xcode 26 or later, including the Metal toolchain
- Codex desktop installed and launched at least once

No third-party runtime dependencies. XcodeGen is only needed when regenerating the checked-in Xcode project.

## Build and run

Clone this repository, then run these commands from its root:

```bash
xcodebuild -project CodexThemeBar.xcodeproj -scheme CodexThemeBar \
  -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Codex ThemeWurx.app"
```

Alternatively, open `CodexThemeBar.xcodeproj` in Xcode and run the `CodexThemeBar` scheme. Builds use ad-hoc signing; an Apple Developer account is not required. If Xcode reports that the Metal compiler is missing, install the Metal Toolchain component in Xcode Settings or run `xcodebuild -downloadComponent MetalToolchain`.

The app appears in the menu bar, without a Dock icon. **Keep the source checkout in place:** the app edits `themes/custom-themes.md` in the directory it was built from. This personal catalog is untracked and Git-ignored. On first launch, the app copies the tracked `themes/default-themes.md` into it; existing personal themes are never overwritten. Rebuild after moving the checkout. This release provides source for local builds, not a notarized installer.

## Apply a theme

1. Open Codex, then choose a theme from the ThemeWurx menu.
2. If requested, grant ThemeWurx access in **System Settings → Privacy & Security → Accessibility**, then retry. This lets it import the theme through Codex's Appearance settings.
3. For live editor previews and theme extraction, use **Relaunch Codex With Live Bridge** in ThemeWurx Settings. This restarts Codex with its Chromium debugger on `127.0.0.1:9222`. Theme extraction can also read the saved appearance state when live extraction is unavailable.

The live bridge exposes debugging access to Codex. Enable it only on a trusted machine and do not expose its port to a network. Quit Codex and reopen it normally to disable the bridge. ThemeWurx does not enable it automatically.

When neither live apply nor Accessibility works, menu actions can offer a confirmed restart and appearance-file update. That path backs up the existing state before changing it. Cycling shortcuts never use this disk-write fallback; Swap Colors and Toggle Last Light/Dark can offer the same confirmed recovery as menu actions. Accessibility integration currently expects English Codex control names.

## Manage themes and shortcuts

**Theme Manager…** opens the color and font editor. Create, duplicate, rename, delete, favorite, and organize themes in light/dark folders; preview changes and save them to the markdown catalog. The first edit in each manager session creates a replaceable `themes/custom-themes.theme-bar.backup.md`. Backups are local and ignored by Git.

**Keyboard Shortcuts…** configures global actions for cycling light, dark, or favorite themes, swapping the current theme’s foreground/background colors, and toggling the last light/dark appearance. While cycling, hold the shortcut modifiers to select a destination; releasing them applies the final selection after a short delay. Favorite cycling combines both appearances in catalog order.

The manager's **Theme File** menu reveals the catalog in Finder, reloads it, and saves or loads a backup. ThemeWurx Settings contains Launch at Login, the live bridge control, and Accessibility status. Rebuilding with ad-hoc signing can require granting Accessibility access again; an optional stable local signing identity is documented in [DEVELOPMENT.md](DEVELOPMENT.md#build-and-run).

## Theme format

All custom themes live in a single Markdown file.

Use `###` headings under `# LIGHT THEMES` or `# DARK THEMES`. Optional `##` headings group them into folders.

```md
# LIGHT THEMES

## Favorites

### Warm Paper
variant: `light`
foreground: `#4b3a3e`
background: `#f4e6dc`
accent: `#c97998`
diff-added: `#5d8b73`
diff-removed: `#b75f6f`
contrast: `68`
code-font: ``
ui-font: ``
opaque-window: `true`
theme-id: `rose-pine`
favorite: `true`

# DARK THEMES
```

Blank font fields use system defaults. Choose installed fonts in the editor if needed. `theme-id` selects Codex's syntax-color preset; the other colors customize its interface. See the [theme contract](DEVELOPMENT.md#theme-file-contract) for optional font-face fields.

## Development

```bash
xcodebuild -project CodexThemeBar.xcodeproj -scheme CodexThemeBar \
  -destination 'platform=macOS' -derivedDataPath build test
```

After editing `project.yml`, install XcodeGen and run `./generate-project.sh`. The generated project is committed so a normal checkout can build directly in Xcode.

[DEVELOPMENT.md](DEVELOPMENT.md) describes the App/Core architecture, theme format, Codex state handling, and validation limits. [CONTRIBUTING.md](CONTRIBUTING.md) covers changes and bug reports.

## License

[MIT](LICENSE) © 2026 CratesSo.
