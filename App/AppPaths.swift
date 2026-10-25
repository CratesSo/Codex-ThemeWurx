import AppKit
import CodexThemeBarCore
import Foundation

enum AppPaths {
    static func make() -> ThemeBarPaths {
        guard let repoPath = infoValue(named: "MetaRepoRoot"), repoPath.hasPrefix("/") else {
            preconditionFailure("MetaRepoRoot must contain the build's absolute source directory.")
        }
        let repoRoot = URL(fileURLWithPath: repoPath)
        let themeFileURL = repoRoot
            .appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent("custom-themes.md")
        let themeBackupURL = themeFileURL.deletingLastPathComponent()
            .appendingPathComponent("custom-themes.theme-bar.backup.md")
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let configURL = codexDirectory.appendingPathComponent("config.toml")
        let usesDesktopConfig = FileManager.default.fileExists(atPath: configURL.path)
        let globalStateURL = usesDesktopConfig
            ? configURL
            : codexDirectory.appendingPathComponent(".codex-global-state.json")
        let backupURL = codexDirectory.appendingPathComponent(
            usesDesktopConfig ? "config.theme-bar.backup.toml" : ".codex-global-state.theme-bar.backup.json"
        )

        return ThemeBarPaths(
            themeFileURL: themeFileURL,
            themeBackupURL: themeBackupURL,
            themeDefaultsURL: themeFileURL.deletingLastPathComponent().appendingPathComponent("default-themes.md"),
            globalStateURL: globalStateURL,
            backupURL: backupURL
        )
    }

    private static func infoValue(named key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
