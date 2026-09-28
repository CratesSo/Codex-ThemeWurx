import CodexThemeBarCore
import XCTest

final class ThemeMarkdownParserTests: XCTestCase {
    func testIncludedCatalogParsesAndExports() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let markdown = try String(
            contentsOf: repositoryURL.appendingPathComponent("themes/default-themes.md"),
            encoding: .utf8
        )
        let catalog = ThemeMarkdownParser.parse(markdown)

        XCTAssertTrue(catalog.issues.isEmpty, "\(catalog.issues)")
        for variant in ThemeVariant.allCases {
            XCTAssertFalse(catalog.entries(for: variant).isEmpty)
        }
        for entry in catalog.entries {
            XCTAssertNoThrow(try ThemeShareString.encode(entry.payload), entry.name)
        }
    }

    func testParsesValidEntry() throws {
        let markdown = """
        # LIGHT THEMES

        ### Light 01
        variant: `light`
        foreground: `#4b3a3e`
        background: `#f4e6dc`
        accent: `#c97998`
        diff-added: `#5d8b73`
        diff-removed: `#b75f6f`
        contrast: `68`
        code-font: `"Jetbrains Mono"`
        code-font-family: `Jetbrains Mono`
        code-font-full-name: `Jetbrains Mono Bold`
        code-font-postscript-name: `JetbrainsMono-Bold`
        ui-font: `Avenir`
        ui-font-family: `Avenir`
        ui-font-full-name: `Avenir Medium`
        ui-font-postscript-name: `Avenir-Medium`
        content-font: `"IBM Plex Sans"`
        content-font-family: `IBM Plex Sans`
        content-font-full-name: `IBM Plex Sans Regular Medium`
        content-font-postscript-name: `IBMPlexSans-Medium`
        opaque-window: `true`
        theme-id: `rose-pine`
        favorite: `false`
        """

        let catalog = ThemeMarkdownParser.parse(markdown)

        XCTAssertEqual(catalog.entries.count, 1)
        XCTAssertEqual(catalog.entries.first?.name, "Light 01")
        XCTAssertEqual(catalog.entries.first?.payload.favorite, false)
        XCTAssertTrue(catalog.issues.isEmpty)
        let entry = try XCTUnwrap(catalog.entries.first)
        let fonts = entry.theme.fonts
        XCTAssertEqual(fonts.codeFace?.postscriptName, "JetbrainsMono-Bold")
        XCTAssertEqual(fonts.uiFace?.postscriptName, "Avenir-Medium")
        XCTAssertEqual(fonts.content, "\"IBM Plex Sans\"")
        XCTAssertEqual(fonts.contentFace?.postscriptName, "IBMPlexSans-Medium")
        XCTAssertEqual(ThemeMarkdownParser.parse(ThemeMarkdownParser.serialize(catalog)).entries.first?.theme.fonts, fonts)
        XCTAssertEqual(ThemeEditorDraft(entry: entry).entry()?.theme.fonts, fonts)
        let share = try ThemeShareString.encode(entry.payload)
        let decoded = try JSONDecoder().decode(ThemeFilePayload.self, from: Data(share.dropFirst(ThemeShareString.prefix.count).utf8))
        XCTAssertEqual(decoded.theme.fonts, fonts)
    }

    func testSkipsInvalidMarkdownAndKeepsValidEntry() {
        let markdown = """
        ### Broken
        variant: `light`

        ### Dark 01
        variant: `dark`
        foreground: `#f0ddd7`
        background: `#2b2023`
        accent: `#d17c86`
        diff-added: `#7ac09a`
        diff-removed: `#d96b75`
        contrast: `81`
        code-font: `"Jetbrains Mono"`
        ui-font: `Avenir`
        opaque-window: `true`
        theme-id: `rose-pine`
        favorite: `false`
        """

        let catalog = ThemeMarkdownParser.parse(markdown)

        XCTAssertEqual(catalog.entries.map(\.name), ["Dark 01"])
        XCTAssertEqual(catalog.issues.count, 1)
    }

    func testSerializeRoundTripsCatalog() {
        let catalog = ThemeCatalog(entries: [
            CustomThemeEntry(name: "Light 01", payload: samplePayload(variant: .light, codeThemeId: "rose-pine", accent: "#aaaaaa", background: "#fefefe", favorite: true)),
            CustomThemeEntry(name: "Dark 01", payload: samplePayload(variant: .dark, codeThemeId: "vesper", accent: "#222222", background: "#111111"))
        ], issues: [])

        let markdown = ThemeMarkdownParser.serialize(catalog)
        let reparsed = ThemeMarkdownParser.parse(markdown)

        XCTAssertTrue(markdown.contains("# LIGHT THEMES"))
        XCTAssertTrue(markdown.contains("# DARK THEMES"))
        XCTAssertFalse(markdown.contains("skills:"))
        XCTAssertEqual(reparsed.entries, catalog.entries)
        XCTAssertTrue(reparsed.issues.isEmpty)
    }

    func testLegacySkillsFieldIsDroppedWhenSaved() {
        let entry = CustomThemeEntry(
            name: "Light 01",
            payload: samplePayload(variant: .light, codeThemeId: "rose-pine", accent: "#aaaaaa", background: "#fefefe")
        )
        let markdown = """
        # LIGHT THEMES
        ### Light 01
        variant: `light`
        foreground: `#4b3a3e`
        background: `#fefefe`
        accent: `#aaaaaa`
        skills: `#123456`
        diff-added: `#5d8b73`
        diff-removed: `#b75f6f`
        contrast: `68`
        code-font: `Berkeley Mono Trial`
        ui-font: `IBM Plex Mono`
        opaque-window: `true`
        theme-id: `rose-pine`
        favorite: `false`
        """

        let parsed = ThemeMarkdownParser.parse(markdown)

        XCTAssertEqual(parsed.entries, [entry])
        XCTAssertTrue(parsed.issues.isEmpty)
        XCTAssertFalse(ThemeMarkdownParser.serialize(parsed).contains("skills:"))
    }

    func testBlankFontsRoundTripAsSystemDefaults() {
        let markdown = """
        # LIGHT THEMES

        ### System Font Theme
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
        favorite: `false`

        # DARK THEMES
        """

        let catalog = ThemeMarkdownParser.parse(markdown)
        let serialized = ThemeMarkdownParser.serialize(catalog)
        let reparsed = ThemeMarkdownParser.parse(serialized)

        XCTAssertEqual(reparsed.entries.first?.theme.fonts.code, "")
        XCTAssertEqual(reparsed.entries.first?.theme.fonts.ui, "")
        XCTAssertTrue(reparsed.issues.isEmpty)
    }

    func testFlatMarkdownParsesAsImplicitUnfiledFolder() {
        let markdown = """
        # LIGHT THEMES

        ### Light 01
        variant: `light`
        foreground: `#4b3a3e`
        background: `#f4e6dc`
        accent: `#c97998`
        diff-added: `#5d8b73`
        diff-removed: `#b75f6f`
        contrast: `68`
        code-font: `Berkeley Mono Trial`
        ui-font: `IBM Plex Mono`
        opaque-window: `true`
        theme-id: `rose-pine`
        favorite: `false`
        """

        let catalog = ThemeMarkdownParser.parse(markdown)
        let folders = catalog.folders(for: .light)

        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.name, ThemeFolder.unfiledName)
        XCTAssertEqual(folders.first?.isImplicitUnfiled, true)
        XCTAssertEqual(folders.first?.entries.map(\.name), ["Light 01"])
    }

    func testFolderHeadingsRoundTripIncludingEmptyFolders() {
        let catalog = ThemeCatalog(folders: [
            ThemeFolder(variant: .light, name: "Warm", entries: [
                CustomThemeEntry(name: "Light 01", payload: samplePayload(variant: .light, codeThemeId: "rose-pine", accent: "#aaaaaa", background: "#fefefe"))
            ]),
            ThemeFolder(variant: .light, name: "Empty", entries: []),
            ThemeFolder(variant: .dark, name: "Dim", entries: [
                CustomThemeEntry(name: "Dark 01", payload: samplePayload(variant: .dark, codeThemeId: "vesper", accent: "#222222", background: "#111111"))
            ])
        ], issues: [])

        let markdown = ThemeMarkdownParser.serialize(catalog)
        let reparsed = ThemeMarkdownParser.parse(markdown)

        XCTAssertTrue(markdown.contains("## Warm"))
        XCTAssertTrue(markdown.contains("## Empty"))
        XCTAssertEqual(reparsed.folders, catalog.folders)
        XCTAssertTrue(reparsed.issues.isEmpty)
    }

    func testDuplicateFolderHeadingsReportIssue() {
        let markdown = """
        # LIGHT THEMES

        ## Warm

        ## Warm
        """

        let catalog = ThemeMarkdownParser.parse(markdown)

        XCTAssertEqual(catalog.issues.count, 1)
        XCTAssertTrue(catalog.issues.first?.message.contains("Duplicate folder") == true)
    }

    func testThemesAfterInvalidFolderHeadingDoNotInheritPreviousFolder() {
        let markdown = """
        # DARK THEMES

        ## Valid

        ### Dark 01
        variant: `dark`
        foreground: `#4b3a3e`
        background: `#222222`
        accent: `#111111`
        diff-added: `#5d8b73`
        diff-removed: `#b75f6f`
        contrast: `68`
        code-font: `Berkeley Mono Trial`
        ui-font: `IBM Plex Mono`
        opaque-window: `true`
        theme-id: `rose-pine`
        favorite: `false`

        ## Unfiled

        ### Dark 02
        variant: `dark`
        foreground: `#4b3a3e`
        background: `#333333`
        accent: `#222222`
        diff-added: `#5d8b73`
        diff-removed: `#b75f6f`
        contrast: `68`
        code-font: `Berkeley Mono Trial`
        ui-font: `IBM Plex Mono`
        opaque-window: `true`
        theme-id: `rose-pine`
        favorite: `false`
        """

        let catalog = ThemeMarkdownParser.parse(markdown)

        XCTAssertEqual(catalog.issues.count, 1)
        XCTAssertEqual(catalog.folders(for: .dark).map(\.name), ["Valid", ThemeFolder.unfiledName])
        XCTAssertEqual(catalog.folders(for: .dark).map { $0.entries.map(\.name) }, [["Dark 01"], ["Dark 02"]])
    }

    func testDeleteFolderMovesThemesToUnfiled() throws {
        let catalog = ThemeCatalog(folders: [
            ThemeFolder(variant: .dark, name: "Grouped", entries: [
                CustomThemeEntry(name: "Dark 01", payload: samplePayload(variant: .dark, codeThemeId: "rose-pine", accent: "#111111", background: "#222222")),
                CustomThemeEntry(name: "Dark 02", payload: samplePayload(variant: .dark, codeThemeId: "vesper", accent: "#333333", background: "#444444"))
            ])
        ], issues: [])

        let deleted = try ThemeMarkdownParser.deletingFolder(
            in: catalog,
            variant: .dark,
            folderID: ThemeFolder.id(for: .dark, name: "Grouped")
        )

        XCTAssertEqual(deleted.folders(for: .dark).map(\.name), [ThemeFolder.unfiledName])
        XCTAssertEqual(deleted.entries(for: .dark).map(\.name), ["Dark 01", "Dark 02"])
    }

    func testFolderReorderingPreservesContentsAndRejectsMovingUnfiled() throws {
        let folders = ["A", "B", "C"].map { name in
            ThemeFolder(variant: .dark, name: name, entries: [
                CustomThemeEntry(name: "Theme \(name)", payload: samplePayload(variant: .dark, codeThemeId: "rose-pine", accent: "#111111", background: "#222222"))
            ])
        }
        let unfiled = ThemeFolder(variant: .dark, name: ThemeFolder.unfiledName, isImplicitUnfiled: true, entries: [
            CustomThemeEntry(name: "Loose theme", payload: samplePayload(variant: .dark, codeThemeId: "vesper", accent: "#333333", background: "#444444"))
        ])
        let catalog = ThemeCatalog(folders: [unfiled] + folders, issues: [])
        let cases: [(String, Int, [String])] = [
            ("A", 3, ["B", "C", "A"]),
            ("C", 0, ["C", "A", "B"]),
            ("B", 0, ["B", "A", "C"]),
            ("B", 3, ["A", "C", "B"]),
            ("B", 1, ["A", "B", "C"]),
            ("B", 2, ["A", "B", "C"])
        ]
        for (name, destination, expected) in cases {
            let moved = try ThemeMarkdownParser.movingFolder(in: catalog, variant: .dark, folderID: ThemeFolder.id(for: .dark, name: name), toOffset: destination)
            let reloaded = ThemeMarkdownParser.parse(ThemeMarkdownParser.serialize(moved))
            XCTAssertTrue(reloaded.issues.isEmpty)
            XCTAssertEqual(reloaded.folders(for: .dark).filter { !$0.isImplicitUnfiled }.map(\.name), expected)
            for folder in folders + [unfiled] {
                XCTAssertEqual(reloaded.folders(for: .dark).first { $0.id == folder.id }?.entries, folder.entries)
            }
        }
        XCTAssertThrowsError(try ThemeMarkdownParser.movingFolder(in: catalog, variant: .dark, folderID: unfiled.id, toOffset: 0))
        XCTAssertThrowsError(try ThemeMarkdownParser.movingFolder(in: catalog, variant: .dark, folderID: folders[0].id, toOffset: 4))
    }

    func testMoveEntryBetweenFoldersPreservesGroupedOrder() throws {
        let first = CustomThemeEntry(name: "Dark 01", payload: samplePayload(variant: .dark, codeThemeId: "rose-pine", accent: "#111111", background: "#222222"))
        let second = CustomThemeEntry(name: "Dark 02", payload: samplePayload(variant: .dark, codeThemeId: "vesper", accent: "#333333", background: "#444444"))
        let catalog = ThemeCatalog(folders: [
            ThemeFolder(variant: .dark, name: "A", entries: [first]),
            ThemeFolder(variant: .dark, name: "B", entries: [second])
        ], issues: [])

        let moved = try ThemeMarkdownParser.movingEntry(
            in: catalog,
            variant: .dark,
            entryID: first.id,
            toFolderID: ThemeFolder.id(for: .dark, name: "B"),
            insertionIndex: 1
        )

        XCTAssertEqual(moved.folders(for: .dark).map { $0.entries.map(\.name) }, [[], ["Dark 02", "Dark 01"]])
        XCTAssertEqual(moved.entries(for: .dark).map(\.name), ["Dark 02", "Dark 01"])
    }

    func testMoveEntryDownWithinSameFolderAdjustsPreRemovalInsertionIndex() throws {
        let first = CustomThemeEntry(name: "Dark 01", payload: samplePayload(variant: .dark, codeThemeId: "rose-pine", accent: "#111111", background: "#222222"))
        let second = CustomThemeEntry(name: "Dark 02", payload: samplePayload(variant: .dark, codeThemeId: "vesper", accent: "#333333", background: "#444444"))
        let third = CustomThemeEntry(name: "Dark 03", payload: samplePayload(variant: .dark, codeThemeId: "dracula", accent: "#555555", background: "#666666"))
        let catalog = ThemeCatalog(folders: [
            ThemeFolder(variant: .dark, name: "A", entries: [first, second, third])
        ], issues: [])

        let moved = try ThemeMarkdownParser.movingEntry(
            in: catalog,
            variant: .dark,
            entryID: first.id,
            toFolderID: ThemeFolder.id(for: .dark, name: "A"),
            insertionIndex: 2
        )

        XCTAssertEqual(moved.entries(for: .dark).map(\.name), ["Dark 02", "Dark 01", "Dark 03"])
    }

    func testMoveEntryUpWithinSameFolderKeepsInsertionIndex() throws {
        let first = CustomThemeEntry(name: "Dark 01", payload: samplePayload(variant: .dark, codeThemeId: "rose-pine", accent: "#111111", background: "#222222"))
        let second = CustomThemeEntry(name: "Dark 02", payload: samplePayload(variant: .dark, codeThemeId: "vesper", accent: "#333333", background: "#444444"))
        let third = CustomThemeEntry(name: "Dark 03", payload: samplePayload(variant: .dark, codeThemeId: "dracula", accent: "#555555", background: "#666666"))
        let catalog = ThemeCatalog(folders: [
            ThemeFolder(variant: .dark, name: "A", entries: [first, second, third])
        ], issues: [])

        let moved = try ThemeMarkdownParser.movingEntry(
            in: catalog,
            variant: .dark,
            entryID: third.id,
            toFolderID: ThemeFolder.id(for: .dark, name: "A"),
            insertionIndex: 1
        )

        XCTAssertEqual(moved.entries(for: .dark).map(\.name), ["Dark 01", "Dark 03", "Dark 02"])
    }

    func testThemeEditorDraftValidationBlocksMalformedImportantFields() {
        let valid = ThemeEditorDraft(entry: CustomThemeEntry(
            name: "Valid",
            payload: samplePayload(variant: .light, codeThemeId: "rose-pine", accent: "#111111", background: "#ffffff")
        ))
        XCTAssertTrue(valid.isValid)
        let cases: [(WritableKeyPath<ThemeEditorDraft, String>, String)] = [
            (\.name, " \n"), (\.foreground, "red"), (\.background, "#12345"),
            (\.accent, "123456"), (\.diffAdded, "#gg0000"), (\.diffRemoved, "#1234567")
        ]
        for (field, value) in cases {
            var draft = valid
            draft[keyPath: field] = value
            XCTAssertFalse(draft.isValid, "Accepted invalid \(field): \(value)")
        }
    }

    func testDraftContrastAcceptsBoundariesAndRejectsInvalidValues() {
        var draft = ThemeEditorDraft(entry: CustomThemeEntry(
            name: "Contrast",
            payload: samplePayload(variant: .dark, codeThemeId: "vesper", accent: "#111111", background: "#222222")
        ))
        for (value, expected) in [("0", 0), ("100", 100), (" 68 ", 68)] {
            draft.contrast = value
            XCTAssertTrue(draft.isValid, value)
            XCTAssertEqual(draft.entry()?.theme.contrast, expected)
        }
        for value in ["-1", "101", "high", "68.5", ""] {
            draft.contrast = value
            XCTAssertFalse(draft.isValid, value)
            XCTAssertNil(draft.entry(), value)
        }
    }

    func testDeleteRemovesOnlyTargetVariantEntry() throws {
        let catalog = ThemeCatalog(entries: [
            CustomThemeEntry(name: "Light 01", payload: samplePayload(variant: .light, codeThemeId: "rose-pine", accent: "#aaaaaa", background: "#fefefe")),
            CustomThemeEntry(name: "Dark 01", payload: samplePayload(variant: .dark, codeThemeId: "rose-pine", accent: "#111111", background: "#222222")),
            CustomThemeEntry(name: "Light 02", payload: samplePayload(variant: .light, codeThemeId: "vesper", accent: "#bbbbbb", background: "#ededed"))
        ], issues: [])

        let deleted = try ThemeMarkdownParser.deletingEntry(in: catalog, variant: .light, variantIndex: 0)

        XCTAssertEqual(deleted.entries.map(\.name), ["Light 02", "Dark 01"])
    }

    func testMoveReordersWithinVariantAndPreservesOtherVariantSlots() throws {
        let catalog = ThemeCatalog(entries: [
            CustomThemeEntry(name: "Light 01", payload: samplePayload(variant: .light, codeThemeId: "rose-pine", accent: "#aaaaaa", background: "#fefefe", favorite: true)),
            CustomThemeEntry(name: "Dark 01", payload: samplePayload(variant: .dark, codeThemeId: "rose-pine", accent: "#111111", background: "#222222")),
            CustomThemeEntry(name: "Light 02", payload: samplePayload(variant: .light, codeThemeId: "vesper", accent: "#bbbbbb", background: "#ededed")),
            CustomThemeEntry(name: "Dark 02", payload: samplePayload(variant: .dark, codeThemeId: "vesper", accent: "#333333", background: "#444444"))
        ], issues: [])

        let moved = try ThemeMarkdownParser.movingEntry(
            in: catalog,
            variant: .light,
            entryID: catalog.entries(for: .light)[1].id,
            toFolderID: ThemeFolder.unfiledID(for: .light),
            insertionIndex: 0
        )

        XCTAssertEqual(moved.entries.map(\.name), ["Light 02", "Light 01", "Dark 01", "Dark 02"])
        XCTAssertEqual(moved.entries.first?.payload.favorite, false)
        XCTAssertEqual(moved.entries[1].payload.favorite, true)
    }

    func testSavingEditedDraftPreservesLockedThemeMetadata() throws {
        let entry = CustomThemeEntry(
            name: "Vesper Dark",
            payload: samplePayload(
                variant: .dark,
                codeThemeId: "vesper",
                accent: "#333333",
                background: "#444444",
                opaqueWindows: false
            )
        )

        var draft = ThemeEditorDraft(entry: entry)
        draft.accent = "#abcdef"
        let edited = try XCTUnwrap(draft.entry())
        let catalog = ThemeCatalog(entries: [entry], issues: [])
        let updated = try ThemeMarkdownParser.replacingEntry(in: catalog, variant: .dark, variantIndex: 0, with: edited)
        let saved = try XCTUnwrap(ThemeMarkdownParser.parse(ThemeMarkdownParser.serialize(updated)).entries.first)

        XCTAssertEqual(saved.theme.accent, "#abcdef")
        XCTAssertEqual(saved.payload.codeThemeId, "vesper")
        XCTAssertFalse(saved.theme.opaqueWindows)
    }

    func testHotkeyDebounceWaitsForModifierReleaseBeforeStartingDelay() {
        var debounce = ThemeHotkeyDebounce()
        let start = ContinuousClock.now
        XCTAssertFalse(debounce.isReady(at: start, modifiersHeld: true))
        XCTAssertFalse(debounce.isReady(at: start + .seconds(10), modifiersHeld: true))

        let release = start + .seconds(11)
        XCTAssertFalse(debounce.isReady(at: release, modifiersHeld: false))
        XCTAssertFalse(debounce.isReady(at: release + .milliseconds(274), modifiersHeld: false))
        XCTAssertTrue(debounce.isReady(at: release + .milliseconds(275), modifiersHeld: false))
    }

    func testHotkeyDebounceRestartsWhenModifiersArePressedAgain() {
        var debounce = ThemeHotkeyDebounce()
        let start = ContinuousClock.now
        XCTAssertFalse(debounce.isReady(at: start, modifiersHeld: false))
        XCTAssertFalse(debounce.isReady(at: start + .milliseconds(200), modifiersHeld: true))
        XCTAssertFalse(debounce.isReady(at: start + .seconds(1), modifiersHeld: true))

        let release = start + .seconds(2)
        XCTAssertFalse(debounce.isReady(at: release, modifiersHeld: false))
        XCTAssertFalse(debounce.isReady(at: release + .milliseconds(274), modifiersHeld: false))
        XCTAssertTrue(debounce.isReady(at: release + .milliseconds(275), modifiersHeld: false))
    }

    func testHotkeyDebounceRechecksModifiersAfterWaitingForAnotherApply() {
        var debounce = ThemeHotkeyDebounce()
        let start = ContinuousClock.now
        XCTAssertFalse(debounce.isReady(at: start, modifiersHeld: false))
        XCTAssertTrue(debounce.isReady(at: start + .milliseconds(275), modifiersHeld: false))
        XCTAssertFalse(debounce.isReady(at: start + .seconds(1), modifiersHeld: true))
        XCTAssertFalse(debounce.isReady(at: start + .seconds(2), modifiersHeld: false))
        XCTAssertTrue(debounce.isReady(at: start + .seconds(2) + .milliseconds(275), modifiersHeld: false))
    }

    func testHotkeyBurstOnlyAppliesLatestDebouncedSelection() {
        var queue = ThemeHotkeyApplyQueue()
        let entries = hotkeyQueueEntries()
        let first = queue.enqueue(entries[0])
        queue.markReady(first)
        let latest = queue.enqueue(entries[1])

        queue.markReady(first)
        XCTAssertNil(queue.takeReady(), "An old debounce must not dispatch the newest selection early.")
        queue.markReady(latest)
        XCTAssertEqual(queue.takeReady()?.id, latest.id)
        XCTAssertNil(queue.takeReady(), "Only one apply may run at a time.")
    }

    func testHotkeysAdvanceAndReverseWhileApplyIsRunning() throws {
        var queue = ThemeHotkeyApplyQueue()
        let entries = hotkeyQueueEntries()
        let active = queue.enqueue(entries[0])
        queue.markReady(active)
        XCTAssertEqual(queue.takeReady()?.id, active.id)

        var selected = active.entry
        var latest = active
        for direction: ThemeCycleDirection in [.next, .next, .next, .previous] {
            selected = try XCTUnwrap(ThemeCyclePlanner.nextEntry(
                in: entries,
                currentTheme: selected.theme,
                currentCodeThemeId: selected.codeThemeId,
                direction: direction
            ))
            latest = queue.enqueue(selected)
            queue.markReady(latest)
            XCTAssertNil(queue.takeReady())
        }
        XCTAssertEqual(latest.entry.id, entries[2].id)
        XCTAssertFalse(queue.isCurrent(active))
        queue.finish(active)
        XCTAssertTrue(queue.isCurrent(latest), "An old completion must preserve the latest selection.")
        XCTAssertEqual(queue.takeReady()?.id, latest.id)
        queue.finish(latest)
        XCTAssertNil(queue.takeReady(), "Intermediate selections must not be replayed.")
    }

    func testHotkeyCompletionStillWaitsForNewestDebounce() {
        var queue = ThemeHotkeyApplyQueue()
        let entries = hotkeyQueueEntries()
        let active = queue.enqueue(entries[0])
        queue.markReady(active)
        XCTAssertEqual(queue.takeReady()?.id, active.id)
        let latest = queue.enqueue(entries[1])

        queue.finish(active)
        XCTAssertNil(queue.takeReady())
        queue.markReady(latest)
        XCTAssertEqual(queue.takeReady()?.id, latest.id)
    }

    func testCancellingHotkeysDoesNotReleaseRunningApplyEarly() {
        var queue = ThemeHotkeyApplyQueue()
        let entries = hotkeyQueueEntries()
        let active = queue.enqueue(entries[0])
        queue.markReady(active)
        XCTAssertEqual(queue.takeReady()?.id, active.id)
        queue.cancelPending()
        XCTAssertFalse(queue.isCurrent(active))

        let latest = queue.enqueue(entries[1])
        queue.markReady(latest)
        XCTAssertNil(queue.takeReady(), "Cancellation cannot undo a dispatched bridge or Accessibility call.")
        queue.finish(active)
        XCTAssertEqual(queue.takeReady()?.id, latest.id)
        queue.finish(active)
        XCTAssertNil(queue.takeReady(), "A stale completion cannot release the newer active call.")
        queue.finish(latest)
        XCTAssertFalse(queue.isCurrent(latest))
    }

    private func hotkeyQueueEntries() -> [CustomThemeEntry] {
        ["#111111", "#222222", "#333333"].enumerated().map { index, accent in
            CustomThemeEntry(name: "Theme \(index)", payload: samplePayload(
                variant: .dark, codeThemeId: "vesper", accent: accent, background: "#000000"
            ))
        }
    }

    private func samplePayload(
        variant: ThemeVariant,
        codeThemeId: String,
        accent: String,
        background: String,
        favorite: Bool = false,
        opaqueWindows: Bool = true
    ) -> ThemeFilePayload {
        ThemeFilePayload(
            variant: variant,
            codeThemeId: codeThemeId,
            favorite: favorite,
            theme: ChromeTheme(
                accent: accent,
                contrast: 68,
                fonts: ThemeFonts(code: "Berkeley Mono Trial", ui: "IBM Plex Mono"),
                foreground: "#4b3a3e",
                opaqueWindows: opaqueWindows,
                semanticColors: ThemeSemanticColors(diffAdded: "#5d8b73", diffRemoved: "#b75f6f"),
                background: background
            )
        )
    }
}
