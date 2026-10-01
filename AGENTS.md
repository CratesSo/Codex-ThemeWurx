# Project Summary

Codex ThemeWurx is a native macOS menu bar app for managing and applying custom Codex themes. It reads editable theme definitions from `themes/custom-themes.md`, exposes menu bar and manager-window controls, applies themes through Codex's live Chromium debugger bridge or macOS Accessibility, and offers a confirmed restart and appearance-file update when neither live path works.

## Development Reference

- Use [`DEVELOPMENT.md`](DEVELOPMENT.md) as the canonical repo guide. Read it before implementing complex changes, debugging cross-file behavior, changing runtime flows, or refactors.
- Do not read it for straightforward or simple edits/implementation or of already read recently.

## Repo Map

- `App/`: macOS app layer. Contains app startup, menu bar UI, manager/settings windows, live Codex importer, path resolution, soft reload behavior, and hotkey controller wiring.
- `Core/`: shared theme logic. Contains theme models, markdown parsing and rewriting, share-string encoding, global state storage, and file watching.
- `Tests/`: Swift tests for parser, state-store, theme-cycle, duplicate hotkey validation, and hotkey preference behavior.
- `themes/custom-themes.md`: personal, untracked and Git-ignored catalog; never stage or publish it.
- `themes/default-themes.md`: tracked system-font defaults used to seed new personal catalogs.
- `themes/custom-themes.theme-bar.backup.md`: local, Git-ignored backup of the editable theme file.
- `project.yml`: XcodeGen project definition.
- `generate-project.sh`: regenerates `CodexThemeBar.xcodeproj` from `project.yml`.
- `Info.plist`: app bundle metadata.

## Working Notes

- Keep changes narrow and prefer the existing App/Core split.
- `App/AppPaths.swift` is the source of truth for filesystem paths.
- `Core/ThemeMarkdownParser.swift` owns the theme markdown contract; avoid duplicating parser behavior elsewhere.
- `Core/CodexGlobalStateStore.swift` owns Codex state backup, apply, and restore behavior.
- Theme application should flow through `App/ThemeBarModel.swift`; do not bypass it for UI actions.

## Personal Catalog Protection

- Keep `themes/custom-themes.md` and its backup local, untracked, and Git-ignored. Never force-add, commit, push, or include them in release snapshots.
- Preserve the user's existing catalog and fonts. Do not copy personal edits into `themes/default-themes.md`; change the public defaults only when explicitly requested.
- `ThemeBarPaths.prepareThemeFile()` preserves an existing catalog. If missing, it restores the local backup first, otherwise copies `themes/default-themes.md`. Keep this initialization behavior intact.
- Validate shipped themes against `themes/default-themes.md`, not the personal catalog. Before publishing, verify the personal catalog remains untracked and ignored.

## GitHub Push Workflow

- Canonical repository: `https://github.com/CratesSo/Codex-ThemeWurx.git`; publish to `main`.
- Keep the local commit history in this checkout. Never push the local `main` branch or its ancestry to GitHub.
- For each authorized GitHub update, publish the intended source tree as a **single parentless snapshot commit**. Stage only the intended changes, review the staged diff, and verify personal theme files and local-only edits are excluded. Create the commit with `git commit-tree <tree> -m "<snapshot message>"` without any `-p` parent argument.
- Check the current remote `main` SHA immediately before publishing, then push the snapshot commit directly to `main` with `git push --force-with-lease=refs/heads/main:<verified-remote-sha> https://github.com/CratesSo/Codex-ThemeWurx.git <snapshot-sha>:refs/heads/main`. The lease prevents replacing a concurrent remote update.
- Tag releases from the published snapshot commit. Preserve existing release tags and releases unless the user explicitly asks to remove or replace them.
- Before publishing, confirm the target URL and branch, review the snapshot tree, and verify `themes/custom-themes.md` and its backup remain untracked, ignored, and absent from the snapshot.
