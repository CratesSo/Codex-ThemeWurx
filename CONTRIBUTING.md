# Contributing

Bug reports and focused pull requests are welcome. Include your macOS, Xcode, and Codex versions, steps to reproduce, and whether you used the live bridge or Accessibility. Remove account data and unrelated Codex configuration from logs and screenshots.

Read [DEVELOPMENT.md](DEVELOPMENT.md) for architecture and build instructions. Keep theme parsing in Core and UI actions routed through `ThemeBarModel`. If you change `project.yml`, regenerate and commit the Xcode project. Run the existing tests and add a focused regression test for behavior changes where practical.

The automated suite covers parsing, theme editing, hotkey planning, share strings, and appearance-file updates. Changes to menu interactions, Accessibility, file watching, or relaunch behavior also need manual checks with Codex. Describe what you tested in your pull request.

Do not commit `themes/custom-themes.md`, personal signing keys, Codex state, local backups, build output, or editor-specific settings. The app edits the ignored personal catalog; `themes/default-themes.md` contains the public defaults. Contributions are licensed under the project's [MIT license](LICENSE).
