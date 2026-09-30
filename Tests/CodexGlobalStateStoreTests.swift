import Carbon
import CodexThemeBarCore
import XCTest

final class CodexGlobalStateStoreTests: XCTestCase {
    func testThemeFilePreparationPreservesPersonalCatalog() throws {
        let paths = try makeThemePaths()
        try Data("personal fonts and themes".utf8).write(to: paths.themeFileURL)
        try Data("public defaults".utf8).write(to: paths.themeDefaultsURL)
        try Data("older personal backup".utf8).write(to: paths.themeBackupURL)

        try paths.prepareThemeFile()

        XCTAssertEqual(try String(contentsOf: paths.themeFileURL, encoding: .utf8), "personal fonts and themes")
    }

    func testMissingPersonalCatalogUsesBackupBeforeDefaults() throws {
        let paths = try makeThemePaths()
        try Data("public defaults".utf8).write(to: paths.themeDefaultsURL)
        try Data("personal backup".utf8).write(to: paths.themeBackupURL)

        try paths.prepareThemeFile()

        XCTAssertEqual(try String(contentsOf: paths.themeFileURL, encoding: .utf8), "personal backup")
        XCTAssertEqual(try String(contentsOf: paths.themeBackupURL, encoding: .utf8), "personal backup")
    }

    func testFreshCheckoutSeedsIndependentPersonalCatalog() throws {
        let paths = try makeThemePaths()
        try Data("public defaults".utf8).write(to: paths.themeDefaultsURL)

        try paths.prepareThemeFile()
        XCTAssertEqual(try String(contentsOf: paths.themeFileURL, encoding: .utf8), "public defaults")
        try Data("personal edit".utf8).write(to: paths.themeFileURL)
        try paths.prepareThemeFile()

        XCTAssertEqual(try String(contentsOf: paths.themeFileURL, encoding: .utf8), "personal edit")
        XCTAssertEqual(try String(contentsOf: paths.themeDefaultsURL, encoding: .utf8), "public defaults")
    }

    func testMissingDefaultsDoesNotCreateEmptyPersonalCatalog() throws {
        let paths = try makeThemePaths()

        XCTAssertThrowsError(try paths.prepareThemeFile())
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.themeFileURL.path))
    }

    private func makeThemePaths() throws -> ThemeBarPaths {
        let directory = try makeTemporaryDirectory()
        return ThemeBarPaths(
            themeFileURL: directory.appendingPathComponent("custom-themes.md"),
            themeBackupURL: directory.appendingPathComponent("custom-themes.theme-bar.backup.md"),
            themeDefaultsURL: directory.appendingPathComponent("default-themes.md"),
            globalStateURL: directory.appendingPathComponent("config.toml"),
            backupURL: directory.appendingPathComponent("config.theme-bar.backup.toml")
        )
    }

    func testDesktopConfigLoadsSlotsAndModeOnlyChangePreservesEverythingElse() throws {
        let directory = try makeTemporaryDirectory()
        let stateURL = directory.appendingPathComponent("config.toml")
        let backupURL = directory.appendingPathComponent("config.backup.toml")
        let original = """
        [desktop]
        appearanceTheme = "dark" # keep this comment
        appearanceLightCodeThemeId = "rose-pine"
        appearanceDarkCodeThemeId = "rose-pine"
        unrelated = "leave me alone"

        [desktop.appearanceLightChromeTheme]
        accent = "#b65a73"
        contrast = 100
        ink = "#70435a"
        opaqueWindows = true
        surface = "#efe3d8"
        [desktop.appearanceLightChromeTheme.fonts]
        code = '\"Berkeley Mono Trial\"'
        ui = '\"Berkeley Mono Trial\"'
        [desktop.appearanceLightChromeTheme.semanticColors]
        diffAdded = "#328640"
        diffRemoved = "#952a23"
        skill = "#8f5686"

        [desktop.appearanceDarkChromeTheme]
        accent = "#bd74a5"
        contrast = 80
        ink = "#ead7e4"
        opaqueWindows = true
        surface = "#241b25"
        [desktop.appearanceDarkChromeTheme.fonts]
        code = '\"Berkeley Mono Trial\"'
        ui = '\"Berkeley Mono Trial\"'
        [desktop.appearanceDarkChromeTheme.semanticColors]
        diffAdded = "#9edba8"
        diffRemoved = "#e69994"
        skill = "#ad78c8"

        [other]
        value = "untouched"
        """
        try original.write(to: stateURL, atomically: true, encoding: .utf8)
        let store = CodexGlobalStateStore(stateURL: stateURL, backupURL: backupURL)

        let before = try store.loadSnapshot()
        let after = try store.setAppearanceMode(.light)
        let updated = try String(contentsOf: stateURL, encoding: .utf8)

        XCTAssertEqual(before.appearanceTheme, "dark")
        XCTAssertNotNil(before.lightChromeTheme)
        XCTAssertNotNil(before.darkChromeTheme)
        XCTAssertEqual(after.appearanceTheme, "light")
        XCTAssertEqual(after.lightChromeTheme, before.lightChromeTheme)
        XCTAssertEqual(after.darkChromeTheme, before.darkChromeTheme)
        XCTAssertEqual(after.lightCodeThemeId, "rose-pine")
        XCTAssertEqual(after.darkCodeThemeId, "rose-pine")
        XCTAssertEqual(updated, original.replacingOccurrences(of: "appearanceTheme = \"dark\"", with: "appearanceTheme = \"light\""))
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: backupURL.path)[.posixPermissions] as? Int, 0o600)

        let payload = samplePayload(variant: .light, codeThemeId: "solarized", accent: "#abcdef", background: "#fefefe")
        let applied = try store.apply(payload: payload)
        XCTAssertEqual(applied.lightChromeTheme, payload.theme)
        XCTAssertEqual(applied.lightCodeThemeId, "solarized")
        XCTAssertEqual(applied.darkChromeTheme, before.darkChromeTheme)
        XCTAssertEqual(applied.darkCodeThemeId, "rose-pine")
        XCTAssertTrue(try String(contentsOf: stateURL, encoding: .utf8).contains("value = \"untouched\""))
    }

    func testModeOnlyMutationPreservesBothSavedSlotsAndCodeThemeIDs() throws {
        let sandbox = try makeSandbox()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sandbox.stateURL)) as? [String: Any])

        let store = CodexGlobalStateStore(stateURL: sandbox.stateURL, backupURL: sandbox.backupURL)
        let snapshot = try store.setAppearanceMode(.dark)
        let updated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sandbox.stateURL)) as? [String: Any])

        XCTAssertEqual(snapshot.appearanceTheme, "dark")
        var expected = original
        expected["appearanceTheme"] = "dark"
        XCTAssertEqual(updated as NSDictionary, expected as NSDictionary)
    }

    func testLegacyHotkeyPreferencesDecodeWithoutToggleBinding() throws {
        let data = Data(#"{"hotkeysEnabled":false,"bindings":{"lightNext":{"keyCode":30,"key":"]","modifiers":5}}}"#.utf8)

        let decoded = try JSONDecoder().decode(ThemeHotkeyPreferences.self, from: data)

        XCTAssertNil(decoded.bindings.toggleAppearance)
        XCTAssertNil(decoded.bindings.invertCurrent)
        XCTAssertFalse(decoded.hotkeysEnabled)
        XCTAssertEqual(decoded.bindings.lightNext, ThemeHotkeyShortcut(keyCode: 30, key: "]", modifiers: [.command, .control]))
    }

    func testApplyLightThemeMutatesOnlyLightSlot() throws {
        let sandbox = try makeSandbox()
        let store = CodexGlobalStateStore(stateURL: sandbox.stateURL, backupURL: sandbox.backupURL)
        let originalData = try Data(contentsOf: sandbox.stateURL)
        let originalSnapshot = try store.loadSnapshot()
        let payload = samplePayload(variant: .light, codeThemeId: "solarized", accent: "#ffffff", background: "#eeeeee")

        let snapshot = try store.apply(payload: payload)
        let data = try Data(contentsOf: sandbox.stateURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(snapshot.lightChromeTheme, payload.theme)
        XCTAssertEqual(snapshot.darkChromeTheme, originalSnapshot.darkChromeTheme)
        XCTAssertEqual(root["appearanceTheme"] as? String, "light")
        XCTAssertEqual(root["appearanceLightCodeThemeId"] as? String, "solarized")
        XCTAssertEqual(root["appearanceDarkCodeThemeId"] as? String, "rose-pine")
        XCTAssertEqual(root["untouched"] as? String, "value")
        let lightTheme = try XCTUnwrap(root["appearanceLightChromeTheme"] as? [String: Any])
        let semanticColors = try XCTUnwrap(lightTheme["semanticColors"] as? [String: String])
        XCTAssertEqual(semanticColors["skill"], payload.theme.accent)
        XCTAssertEqual(try Data(contentsOf: sandbox.backupURL), originalData)
    }

    func testApplyDarkThemeSwitchesAppearanceThemeFromLightState() throws {
        let sandbox = try makeSandbox()
        let store = CodexGlobalStateStore(stateURL: sandbox.stateURL, backupURL: sandbox.backupURL)
        let originalSnapshot = try store.loadSnapshot()
        let payload = samplePayload(variant: .dark, codeThemeId: "rose-pine-moon", accent: "#abcdef", background: "#101010")

        let snapshot = try store.apply(payload: payload)
        let data = try Data(contentsOf: sandbox.stateURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(snapshot.appearanceTheme, "dark")
        XCTAssertEqual(snapshot.darkChromeTheme, payload.theme)
        XCTAssertEqual(snapshot.lightChromeTheme, originalSnapshot.lightChromeTheme)
        XCTAssertEqual(root["appearanceTheme"] as? String, "dark")
        XCTAssertEqual(root["appearanceDarkCodeThemeId"] as? String, "rose-pine-moon")
        XCTAssertEqual(root["appearanceLightCodeThemeId"] as? String, "rose-pine")
    }

    func testThemeShareStringMatchesCodexImportSchema() throws {
        let payload = samplePayload(variant: .dark, codeThemeId: "rose-pine", accent: "#abcdef", background: "#111111")

        let shareString = try ThemeShareString.encode(payload)

        XCTAssertTrue(shareString.hasPrefix("codex-theme-v1:"))
        let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(shareString.dropFirst("codex-theme-v1:".count).utf8)) as? NSDictionary)
        let expected: NSDictionary = [
            "variant": "dark", "codeThemeId": "rose-pine", "favorite": false,
            "theme": [
                "accent": "#abcdef", "contrast": 68,
                "fonts": ["code": "\"Jetbrains Mono\"", "ui": "Avenir"],
                "ink": "#4b3a3e", "surface": "#111111", "opaqueWindows": true,
                "semanticColors": ["diffAdded": "#5d8b73", "diffRemoved": "#b75f6f", "skill": "#abcdef"]
            ]
        ]
        XCTAssertEqual(actual, expected)
    }

    func testMalformedStateDoesNotOverwriteExistingBackup() throws {
        let sandbox = try makeSandbox()
        let store = CodexGlobalStateStore(stateURL: sandbox.stateURL, backupURL: sandbox.backupURL)
        _ = try store.apply(payload: samplePayload(variant: .light, codeThemeId: "rose-pine", accent: "#abcdef", background: "#fedcba"))
        let originalBackup = try Data(contentsOf: sandbox.backupURL)

        try "{ bad json".write(to: sandbox.stateURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.apply(payload: samplePayload(variant: .dark, codeThemeId: "rose-pine", accent: "#ffffff", background: "#000000")))

        XCTAssertEqual(try Data(contentsOf: sandbox.backupURL), originalBackup)
        XCTAssertEqual(try String(contentsOf: sandbox.stateURL, encoding: .utf8), "{ bad json")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            let trash = Process()
            trash.executableURL = URL(fileURLWithPath: "/usr/bin/trash")
            trash.arguments = [root.path]
            try trash.run()
            trash.waitUntilExit()
            XCTAssertEqual(trash.terminationStatus, 0)
        }
        return root
    }

    private func makeSandbox() throws -> (stateURL: URL, backupURL: URL) {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent(".codex-global-state.json")
        let backupURL = root.appendingPathComponent(".codex-global-state.backup.json")
        let initial = """
        {
          "appearanceTheme" : "light",
          "appearanceLightChromeTheme" : {
            "accent" : "#111111",
            "contrast" : 70,
            "fonts" : {
              "code" : "\\"Jetbrains Mono\\"",
              "ui" : "Avenir"
            },
            "foreground" : "#aaaaaa",
            "opaqueWindows" : true,
            "semanticColors" : {
              "diffAdded" : "#00ff00",
              "diffRemoved" : "#ff0000",
              "skill" : "#0000ff"
            },
            "background" : "#f0f0f0"
          },
          "appearanceDarkChromeTheme" : {
            "accent" : "#222222",
            "contrast" : 80,
            "fonts" : {
              "code" : "\\"Jetbrains Mono\\"",
              "ui" : "Avenir"
            },
            "foreground" : "#bbbbbb",
            "opaqueWindows" : true,
            "semanticColors" : {
              "diffAdded" : "#00ee00",
              "diffRemoved" : "#ee0000",
              "skill" : "#0000ee"
            },
            "background" : "#202020"
          },
          "appearanceLightCodeThemeId" : "rose-pine",
          "appearanceDarkCodeThemeId" : "rose-pine",
          "untouched" : "value",
          "top" : "still here"
        }
        """
        try initial.write(to: stateURL, atomically: true, encoding: .utf8)
        return (stateURL, backupURL)
    }

    private func sampleTheme(accent: String, background: String) -> ChromeTheme {
        ChromeTheme(
            accent: accent,
            contrast: 68,
            fonts: ThemeFonts(code: "\"Jetbrains Mono\"", ui: "Avenir"),
            foreground: "#4b3a3e",
            opaqueWindows: true,
            semanticColors: ThemeSemanticColors(diffAdded: "#5d8b73", diffRemoved: "#b75f6f"),
            background: background
        )
    }

    private func samplePayload(variant: ThemeVariant, codeThemeId: String, accent: String, background: String) -> ThemeFilePayload {
        ThemeFilePayload(variant: variant, codeThemeId: codeThemeId, favorite: false, theme: sampleTheme(accent: accent, background: background))
    }
}

final class ThemeHotkeySupportTests: XCTestCase {
    func testCycleNextWrapsAtEndOfLightThemes() {
        let entries = [
            sampleEntry(name: "One", variant: .light, accent: "#111111"),
            sampleEntry(name: "Two", variant: .light, accent: "#222222"),
            sampleEntry(name: "Three", variant: .light, accent: "#333333"),
        ]

        let next = ThemeCyclePlanner.nextEntry(
            in: entries,
            currentTheme: entries[2].theme,
            direction: .next
        )

        XCTAssertEqual(next?.id, entries[0].id)
    }

    func testCyclePreviousWrapsAtBeginningOfDarkThemes() {
        let entries = [
            sampleEntry(name: "One", variant: .dark, accent: "#111111"),
            sampleEntry(name: "Two", variant: .dark, accent: "#222222"),
            sampleEntry(name: "Three", variant: .dark, accent: "#333333"),
        ]

        let previous = ThemeCyclePlanner.nextEntry(
            in: entries,
            currentTheme: entries[0].theme,
            direction: .previous
        )

        XCTAssertEqual(previous?.id, entries[2].id)
    }

    func testCycleFallsBackToFirstEntryWhenCurrentThemeIsUnmanaged() {
        let entries = [
            sampleEntry(name: "One", variant: .light, accent: "#111111"),
            sampleEntry(name: "Two", variant: .light, accent: "#222222"),
        ]

        let next = ThemeCyclePlanner.nextEntry(
            in: entries,
            currentTheme: sampleEntry(name: "Other", variant: .light, accent: "#abcdef").theme,
            direction: .next
        )

        XCTAssertEqual(next?.id, entries[0].id)
    }

    func testCycleFallsBackToLastEntryWhenCurrentThemeIsMissingAndDirectionIsPrevious() {
        let entries = [
            sampleEntry(name: "One", variant: .dark, accent: "#111111"),
            sampleEntry(name: "Two", variant: .dark, accent: "#222222"),
        ]

        let previous = ThemeCyclePlanner.nextEntry(
            in: entries,
            currentTheme: nil,
            direction: .previous
        )

        XCTAssertEqual(previous?.id, entries[1].id)
    }

    func testCycleUsesExactCodeThemeIdentityWhenChromeThemeDuplicatesExist() {
        let theme = ChromeTheme(
            accent: "#111111",
            contrast: 70,
            fonts: ThemeFonts(code: "Berkeley Mono Trial", ui: "IBM Plex Mono"),
            foreground: "#cccccc",
            opaqueWindows: true,
            semanticColors: ThemeSemanticColors(diffAdded: "#00ff00", diffRemoved: "#ff0000"),
            background: "#111111"
        )
        let entries = [
            CustomThemeEntry(
                name: "First",
                payload: ThemeFilePayload(variant: .light, codeThemeId: "rose-pine", theme: theme)
            ),
            CustomThemeEntry(
                name: "Second",
                payload: ThemeFilePayload(variant: .light, codeThemeId: "solarized", theme: theme)
            ),
            sampleEntry(name: "Third", variant: .light, accent: "#222222", codeThemeId: "gruvbox")
        ]

        let next = ThemeCyclePlanner.nextEntry(
            in: entries,
            currentTheme: theme,
            currentCodeThemeId: "solarized",
            direction: .next
        )

        XCTAssertEqual(next?.id, entries[2].id)
    }

    func testDuplicateOwnerFindsExistingBinding() {
        let duplicate = ThemeHotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_LeftBracket),
            key: "[",
            modifiers: [.command, .option]
        )
        let bindings = ThemeHotkeyBindings(
            lightPrevious: duplicate,
            lightNext: ThemeHotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_RightBracket),
                key: "]",
                modifiers: [.command, .option]
            ),
            darkPrevious: nil,
            darkNext: nil,
            favoritePrevious: nil,
            favoriteNext: nil
        )

        let owner = bindings.duplicateOwner(for: duplicate, excluding: .darkPrevious)

        XCTAssertEqual(owner, .lightPrevious)
        XCTAssertNil(bindings.duplicateOwner(for: duplicate, excluding: .lightPrevious), "Keeping a shortcut on its current action must not conflict with itself.")
        let differentModifiers = ThemeHotkeyShortcut(keyCode: duplicate.keyCode, key: duplicate.key, modifiers: [.control])
        XCTAssertNil(bindings.duplicateOwner(for: differentModifiers, excluding: .darkPrevious))
    }

    func testPreferencesStoreRoundTripsEnabledFlagAndShortcuts() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = ThemeHotkeyPreferencesStore(defaults: defaults)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = ThemeHotkeyPreferences(
            hotkeysEnabled: false,
            bindings: ThemeHotkeyBindings(
                lightPrevious: ThemeHotkeyShortcut(
                    keyCode: UInt32(kVK_ANSI_LeftBracket),
                    key: "[",
                    modifiers: [.control, .option, .command]
                ),
                lightNext: ThemeHotkeyShortcut(
                    keyCode: UInt32(kVK_ANSI_RightBracket),
                    key: "]",
                    modifiers: [.control, .option, .command]
                ),
                darkPrevious: ThemeHotkeyShortcut(
                    keyCode: UInt32(kVK_ANSI_LeftBracket),
                    key: "[",
                    modifiers: [.control, .option, .shift, .command]
                ),
                darkNext: ThemeHotkeyShortcut(
                    keyCode: UInt32(kVK_ANSI_RightBracket),
                    key: "]",
                    modifiers: [.control, .option, .shift, .command]
                ),
                favoritePrevious: ThemeHotkeyShortcut(
                    keyCode: UInt32(kVK_ANSI_LeftBracket),
                    key: "[",
                    modifiers: [.control, .command]
                ),
                favoriteNext: ThemeHotkeyShortcut(
                    keyCode: UInt32(kVK_ANSI_RightBracket),
                    key: "]",
                    modifiers: [.control, .command]
                )
            )
        )

        try store.save(preferences)
        let loaded = try ThemeHotkeyPreferencesStore(defaults: defaults).load()

        XCTAssertEqual(loaded, preferences)
    }

    func testFavoriteCycleUsesGroupedCatalogOrderAcrossVariants() throws {
        let entries = [
            sampleEntry(name: "Light One", variant: .light, accent: "#111111"),
            sampleEntry(name: "Dark One", variant: .dark, accent: "#222222", favorite: true),
            sampleEntry(name: "Light Two", variant: .light, accent: "#333333", favorite: true),
            sampleEntry(name: "Dark Two", variant: .dark, accent: "#444444", favorite: true),
        ]

        let favorites = ThemeCatalog(entries: entries, issues: []).favoriteEntries
        var selected = entries[2]
        for expected in ["Dark One", "Dark Two", "Light Two"] {
            selected = try XCTUnwrap(ThemeCyclePlanner.nextEntry(in: favorites, currentTheme: selected.theme, direction: .next))
            XCTAssertEqual(selected.name, expected)
        }
    }

    private func sampleEntry(name: String, variant: ThemeVariant, accent: String, codeThemeId: String = "rose-pine", favorite: Bool = false) -> CustomThemeEntry {
        CustomThemeEntry(
            name: name,
            payload: ThemeFilePayload(
                variant: variant,
                codeThemeId: codeThemeId,
                favorite: favorite,
                theme: ChromeTheme(
                    accent: accent,
                    contrast: 70,
                    fonts: ThemeFonts(code: "Berkeley Mono Trial", ui: "IBM Plex Mono"),
                    foreground: "#cccccc",
                    opaqueWindows: true,
                    semanticColors: ThemeSemanticColors(
                        diffAdded: "#00ff00",
                        diffRemoved: "#ff0000"
                    ),
                    background: accent
                )
            )
        )
    }
}
