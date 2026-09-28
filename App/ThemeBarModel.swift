import AppKit
import CodexThemeBarCore
import Combine
import Foundation

@MainActor
final class ThemeBarModel: ObservableObject {
    @Published private(set) var catalog = ThemeCatalog(entries: [], issues: [])
    @Published private(set) var snapshot = CodexGlobalStateSnapshot(
        appearanceTheme: nil,
        lightChromeTheme: nil,
        darkChromeTheme: nil,
        lightCodeThemeId: nil,
        darkCodeThemeId: nil
    )
    @Published private(set) var reloadStatus = "Waiting for theme file."
    @Published private(set) var refreshStatus = "No refresh attempted yet."

    private let paths: ThemeBarPaths
    private let fileManager: FileManager
    private let stateStore: CodexGlobalStateStore
    private var themeWatchdog: FileWatchdog?
    private var stateWatchdog: FileWatchdog?
    private var hasThemeBackupForCurrentSession = false
    private var pendingHotkeyApplyTask: Task<Void, Never>?
    private var hotkeyDebounceTask: Task<Void, Never>?
    private var deferredThemeAction: Task<Void, Never>?
    private var hotkeyQueue = ThemeHotkeyApplyQueue()
    private var hotkeySelectionSnapshot: CodexGlobalStateSnapshot?
    private var pendingAccessibilityApplyTask: Task<Void, Never>?
    private var pendingAccessibilityOperation: CodexAccessibilityOperation?
    private var didRequestAccessibilityPermission = false

    var onChange: (() -> Void)?
    var onHotkeyThemeSelected: ((CustomThemeEntry) -> Void)?
    var onThemeApplied: ((String, ThemeVariant) -> Void)?
    var onAppearanceToggleUnavailable: ((String) -> Void)?

    var hasPendingHotkeySelection: Bool { hotkeySelectionSnapshot != nil }

    init(paths: ThemeBarPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.stateStore = CodexGlobalStateStore(stateURL: paths.globalStateURL, backupURL: paths.backupURL, fileManager: fileManager)
    }

    func start() {
        ensureThemeFileExists()
        reloadThemeFile()
        reloadGlobalState()
        refreshStatus = SoftReloadCoordinator.startupLiveBridgeStatus()
        startWatchdogs()
        publish()
    }

    var lightEntries: [CustomThemeEntry] {
        catalog.entries(for: .light)
    }

    var darkEntries: [CustomThemeEntry] {
        catalog.entries(for: .dark)
    }

    var lightRows: [ManagedThemeRow] {
        catalog.managedRows(for: .light)
    }

    var darkRows: [ManagedThemeRow] {
        catalog.managedRows(for: .dark)
    }

    var parseIssues: [ThemeParseIssue] {
        catalog.issues
    }

    var canRestoreThemeBackup: Bool {
        fileManager.fileExists(atPath: paths.themeBackupURL.path)
    }

    func beginThemeManagementSession() {
        hasThemeBackupForCurrentSession = false
        reloadGlobalState()
    }

    func deleteTheme(_ row: ManagedThemeRow) {
        mutateThemeFile { catalog in
            try ThemeMarkdownParser.deletingEntry(
                in: catalog,
                variant: row.variant,
                variantIndex: row.variantIndex
            )
        }
    }

    func toggleFavorite(_ row: ManagedThemeRow) {
        mutateThemeFile { catalog in
            let entry = row.entry
            let replacement = CustomThemeEntry(
                name: entry.name,
                payload: ThemeFilePayload(
                    variant: entry.payload.variant,
                    codeThemeId: entry.payload.codeThemeId,
                    favorite: !entry.payload.favorite,
                    theme: entry.payload.theme
                )
            )
            return try ThemeMarkdownParser.replacingEntry(
                in: catalog,
                variant: row.variant,
                variantIndex: row.variantIndex,
                with: replacement
            )
        }
    }

    func moveTheme(_ row: ManagedThemeRow, toFolderID folderID: String, insertionIndex: Int) {
        mutateThemeFile { catalog in
            try ThemeMarkdownParser.movingEntry(
                in: catalog,
                variant: row.variant,
                entryID: row.entry.id,
                toFolderID: folderID,
                insertionIndex: insertionIndex
            )
        }
    }

    func createFolder(variant: ThemeVariant, name: String) {
        mutateThemeFile { catalog in
            try ThemeMarkdownParser.creatingFolder(in: catalog, variant: variant, name: name)
        }
    }

    func renameFolder(variant: ThemeVariant, folderID: String, name: String) {
        mutateThemeFile { catalog in
            try ThemeMarkdownParser.renamingFolder(in: catalog, variant: variant, folderID: folderID, name: name)
        }
    }

    func deleteFolder(variant: ThemeVariant, folderID: String) {
        mutateThemeFile { catalog in
            try ThemeMarkdownParser.deletingFolder(in: catalog, variant: variant, folderID: folderID)
        }
    }

    func moveFolder(variant: ThemeVariant, folderID: String, toOffset destination: Int) {
        mutateThemeFile { catalog in
            try ThemeMarkdownParser.movingFolder(in: catalog, variant: variant, folderID: folderID, toOffset: destination)
        }
    }

    func isActiveTheme(_ row: ManagedThemeRow) -> Bool {
        matches(row.entry.payload, to: ApplyTarget(row.variant)) || isInvertedTheme(row)
    }

    func isInvertedTheme(_ row: ManagedThemeRow) -> Bool {
        matches(invertedPayload(row.entry.payload), to: ApplyTarget(row.variant))
    }

    func displayName(for row: ManagedThemeRow) -> String {
        displayName(for: row.entry, inverted: isInvertedTheme(row))
    }

    func appearance(for row: ManagedThemeRow) -> (name: String, theme: ChromeTheme) {
        let inverted = isInvertedTheme(row)
        return (
            displayName(for: row.entry, inverted: inverted),
            inverted ? invertedPayload(row.entry.payload).theme : row.entry.theme
        )
    }

    func previewTheme(_ row: ManagedThemeRow) {
        applyTheme(entry: row.entry, to: ApplyTarget(row.variant))
    }

    @discardableResult
    func saveThemeDraft(_ draft: ThemeEditorDraft, replacing row: ManagedThemeRow) -> CustomThemeEntry? {
        var replacementEntry: CustomThemeEntry?
        guard draft.isValid else {
            reloadStatus = draft.validationErrors.joined(separator: " ")
            publish()
            return nil
        }
        let didSave = mutateThemeFile { catalog in
            guard let replacement = draft.entry(named: self.uniqueThemeName(
                draft.name,
                in: catalog.entries(for: draft.variant),
                excluding: draft.variant == row.variant ? row.variantIndex : nil
            )) else {
                throw ThemeCatalogMutationError.emptyName
            }
            if draft.variant == row.variant {
                replacementEntry = replacement
                return try ThemeMarkdownParser.replacingEntry(
                    in: catalog,
                    variant: row.variant,
                    variantIndex: row.variantIndex,
                    with: replacement
                )
            }
            var updatedCatalog = try ThemeMarkdownParser.deletingEntry(
                in: catalog,
                variant: row.variant,
                variantIndex: row.variantIndex
            )
            updatedCatalog = try ThemeMarkdownParser.addingEntry(
                in: updatedCatalog,
                variant: replacement.variant,
                entry: replacement
            )
            replacementEntry = replacement
            return updatedCatalog
        }
        return didSave ? replacementEntry : nil
    }

    @discardableResult
    func createTheme(from draft: ThemeEditorDraft, toFolderID folderID: String? = nil) -> CustomThemeEntry? {
        var createdEntry: CustomThemeEntry?
        guard draft.isValid else {
            reloadStatus = draft.validationErrors.joined(separator: " ")
            publish()
            return nil
        }
        let didSave = mutateThemeFile { catalog in
            let name = self.uniqueThemeName(draft.name, in: catalog.entries(for: draft.variant), excluding: nil)
            guard let entry = draft.entry(named: name) else {
                throw ThemeCatalogMutationError.emptyName
            }
            createdEntry = entry
            return try ThemeMarkdownParser.addingEntry(in: catalog, variant: draft.variant, entry: entry, toFolderID: folderID)
        }
        return didSave ? createdEntry : nil
    }

    func previewDraft(_ draft: ThemeEditorDraft) {
        guard draft.isValid, let entry = draft.entry() else {
            return
        }
        if deferUntilApplyFinishes({ [weak self] in self?.previewDraft(draft) }) { return }
        do {
            try CodexAppearanceImporter.importTheme(entry.payload, variant: entry.variant)
            snapshot = snapshot(applying: entry.payload)
            refreshStatus = "Live Codex preview requested."
            publish()
            return
        } catch CodexAppearanceImporterError.debugBridgeUnavailable {
            refreshStatus = "Local preview only. Relaunch Codex with the live bridge to preview in Codex."
        } catch {
            refreshStatus = "Local preview remains available."
        }
        reloadGlobalState()
        publish()
    }

    func applyTheme(entry: CustomThemeEntry, to target: ApplyTarget) {
        guard entry.variant.rawValue == target.rawValue else {
            return
        }
        let payload: ThemeFilePayload
        let isInverted: Bool
        if isInvertedTheme(entry, to: target) {
            payload = entry.payload
            isInverted = false
        } else if isActiveTheme(entry, to: target) {
            payload = invertedPayload(entry.payload)
            isInverted = true
        } else {
            payload = entry.payload
            isInverted = false
        }
        let themeName = displayName(for: entry, inverted: isInverted)
        applyTheme(payload: payload, themeName: themeName)
    }

    private func applyTheme(payload: ThemeFilePayload, themeName: String) {
        if deferUntilApplyFinishes({ [weak self] in self?.applyTheme(payload: payload, themeName: themeName) }) { return }
        do {
            try CodexAppearanceImporter.importTheme(payload, variant: payload.variant)
            snapshot = snapshot(applying: payload)
            refreshStatus = "Live Codex apply requested."
            onThemeApplied?(themeName, payload.variant)
            publish()
            return
        } catch CodexAppearanceImporterError.debugBridgeUnavailable {
            handleUnavailableLiveBridge(payload: payload, themeName: themeName)
            return
        } catch {
            refreshStatus = "Live Codex apply failed."
            reloadGlobalState()
            publish()
            return
        }
    }

    func applyHotkey(_ action: ThemeHotkeyAction, modifiers: ThemeHotkeyModifiers) {
        if action == .toggleAppearance {
            toggleAppearance()
            return
        }
        if action == .invertCurrent {
            if deferUntilApplyFinishes({ [weak self] in self?.applyHotkey(action, modifiers: modifiers) }) { return }
            guard let target = snapshot.appearanceTheme.flatMap(ApplyTarget.init(rawValue:)),
                  let entry = selectedEntry(for: target) else {
                refreshStatus = "Invert hotkey skipped."
                publish()
                return
            }
            applyTheme(entry: entry, to: target)
            return
        }

        guard let direction = action.direction else { return }
        let selectionSnapshot = hotkeySelectionSnapshot ?? snapshot

        if let target = action.target {
            let entries = target == .light ? lightEntries : darkEntries
            let currentTheme = target == .light ? selectionSnapshot.lightChromeTheme : selectionSnapshot.darkChromeTheme
            let currentCodeThemeId = target == .light ? selectionSnapshot.lightCodeThemeId : selectionSnapshot.darkCodeThemeId

            guard let entry = ThemeCyclePlanner.nextEntry(
                in: entries,
                currentTheme: currentTheme,
                currentCodeThemeId: currentCodeThemeId,
                direction: direction
            ) else {
                refreshStatus = "Hotkey apply skipped."
                publish()
                return
            }

            scheduleHotkeyApply(entry: entry, modifiers: modifiers)
            return
        }

        let currentFavorite = currentFavoriteSelection(in: selectionSnapshot)
        guard let entry = ThemeCyclePlanner.nextEntry(
            in: catalog.favoriteEntries,
            currentTheme: currentFavorite.theme,
            currentCodeThemeId: currentFavorite.codeThemeId,
            direction: direction
        ) else {
            refreshStatus = "Favorite hotkey skipped."
            publish()
            return
        }

        scheduleHotkeyApply(entry: entry, modifiers: modifiers)
    }

    func toggleAppearance() {
        if deferUntilApplyFinishes({ [weak self] in self?.toggleAppearance() }) { return }
        guard let latest = try? stateStore.loadSnapshot() else {
            refreshStatus = "Codex appearance could not be read."
            onAppearanceToggleUnavailable?(refreshStatus)
            publish()
            return
        }
        snapshot = latest
        let destination: ApplyTarget = snapshot.appearanceTheme == ApplyTarget.light.rawValue ? .dark : .light
        if selectedEntry(for: destination) == nil {
            guard let entry = (destination == .light ? lightEntries : darkEntries).first else {
                refreshStatus = "Add a \(destination == .light ? "Light" : "Dark") Codex ThemeWurx theme to toggle appearance."
                onAppearanceToggleUnavailable?(refreshStatus)
                publish()
                return
            }
            applyTheme(entry: entry, to: destination)
            return
        }
        do {
            try CodexAppearanceImporter.setAppearanceMode(destination)
            completeAppearanceToggle(destination, status: "Codex appearance changed.")
        } catch {
            toggleAppearanceThroughAccessibility(destination, bridgeFailure: error.localizedDescription)
        }
    }

    private func toggleAppearanceThroughAccessibility(_ destination: ApplyTarget, bridgeFailure: String) {
        guard let runningCodex = CodexAccessibilityImporter.runningCodex() else {
            recoverAppearanceToggle(destination, reason: bridgeFailure)
            return
        }
        let isTrusted = CodexAccessibilityImporter.isTrusted()
        guard isTrusted, runningCodex.activate(options: []) else {
            if !isTrusted, !didRequestAccessibilityPermission {
                didRequestAccessibilityPermission = true
                CodexAccessibilityImporter.requestPermission()
                refreshStatus = "Enable Accessibility control, then toggle again."
                publish()
                return
            }
            recoverAppearanceToggle(destination, reason: bridgeFailure)
            return
        }
        let operation = CodexAccessibilityOperation()
        pendingAccessibilityOperation = operation
        refreshStatus = "Switching Codex appearance…"
        publish()
        pendingAccessibilityApplyTask = Task { [weak self] in
            guard let self else { return }
            let result = await CodexAccessibilityImporter.setAppearanceMode(
                destination,
                processIdentifier: runningCodex.processIdentifier,
                stateURL: paths.globalStateURL,
                backupURL: paths.backupURL,
                operation: operation
            )
            guard clearPendingAccessibilityApply(operation) else { return }
            switch result {
            case .applied(let warning):
                completeAppearanceToggle(destination, status: warning ?? "Codex appearance changed.")
            case .cancelled(.superseded):
                break
            case .cancelled(.userInterrupted):
                refreshStatus = "Appearance switch cancelled."
                reloadGlobalState()
            case .failed(let message):
                recoverAppearanceToggle(destination, reason: message)
            }
        }
    }

    private func recoverAppearanceToggle(_ destination: ApplyTarget, reason: String) {
        guard confirmAppearanceRestart(reason: reason) else {
            refreshStatus = "Restart recovery cancelled."
            publish()
            return
        }
        guard let original = snapshot.appearanceTheme.flatMap(ApplyTarget.init(rawValue:)) else {
            refreshStatus = "Codex appearance is unknown."
            publish()
            return
        }
        let context = SoftReloadCoordinator.prepareForMutation(launchIfClosed: true)
        guard context.applicationURL != nil else {
            refreshStatus = "Codex installation could not be found."
            publish()
            return
        }
        do {
            snapshot = try stateStore.setAppearanceMode(destination)
        } catch {
            refreshStatus = "Appearance recovery failed: \(error.localizedDescription) " + SoftReloadCoordinator.finishMutation(context, globalStateURL: paths.globalStateURL)
            publish()
            return
        }
        let result = SoftReloadCoordinator.finishMutation(context, globalStateURL: paths.globalStateURL)
        guard result == "State written. Codex restarted." else {
            do {
                snapshot = try stateStore.setAppearanceMode(original)
                refreshStatus = "Codex did not relaunch. Saved appearance was restored."
            } catch {
                refreshStatus = "Codex did not relaunch. Could not restore saved appearance: \(error.localizedDescription)"
            }
            publish()
            return
        }
        completeAppearanceToggle(destination, status: result)
    }

    private func confirmAppearanceRestart(reason: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restart Codex to switch appearance?"
        alert.informativeText = reason
        alert.addButton(withTitle: "Restart Codex")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if !confirmed { CodexAccessibilityImporter.runningCodex()?.activate(options: []) }
        return confirmed
    }

    private func completeAppearanceToggle(_ destination: ApplyTarget, status: String) {
        guard let latest = try? stateStore.loadSnapshot(), latest.appearanceTheme == destination.rawValue else {
            refreshStatus = "Codex appearance change could not be confirmed."
            reloadGlobalState()
            return
        }
        snapshot = mergedSnapshot(from: latest)
        let name: String
        if let entry = selectedEntry(for: destination) {
            name = displayName(for: entry, inverted: isInvertedTheme(entry, to: destination))
        } else {
            name = destination == .light ? "Light appearance" : "Dark appearance"
        }
        refreshStatus = status
        onThemeApplied?(name, ThemeVariant(rawValue: destination.rawValue)!)
        publish()
    }

    private func cancelPendingHotkeyApply() {
        hotkeyDebounceTask?.cancel()
        hotkeyDebounceTask = nil
        hotkeyQueue.cancelPending()
        hotkeySelectionSnapshot = nil
    }

    private func deferUntilApplyFinishes(_ action: @escaping @MainActor () -> Void) -> Bool {
        deferredThemeAction?.cancel()
        cancelPendingHotkeyApply()
        cancelPendingAccessibilityApply(reason: .superseded)
        guard let activeTask = pendingHotkeyApplyTask ?? pendingAccessibilityApplyTask else { return false }
        deferredThemeAction = Task {
            await activeTask.value
            guard !Task.isCancelled else { return }
            deferredThemeAction = nil
            action()
        }
        return true
    }

    private func scheduleHotkeyApply(entry: CustomThemeEntry, modifiers: ThemeHotkeyModifiers) {
        deferredThemeAction?.cancel()
        deferredThemeAction = nil
        hotkeyDebounceTask?.cancel()
        // Accessibility observes physical input, so a new shortcut ends that UI operation.
        // Keep its task until it exits; the next apply must not overlap its cleanup.
        cancelPendingAccessibilityApply(reason: .superseded)
        let request = hotkeyQueue.enqueue(entry)
        hotkeySelectionSnapshot = snapshot(applying: entry.payload, to: hotkeySelectionSnapshot ?? snapshot)
        let themeName = displayName(for: entry, inverted: false)
        refreshStatus = "Selected \(themeName)…"
        onHotkeyThemeSelected?(entry)
        publish()

        hotkeyDebounceTask = Task { [weak self] in
            guard let self else { return }
            var debounce = ThemeHotkeyDebounce()
            do {
                // Reading current flags avoids requiring global keyboard-monitoring permission.
                // Keep checking until dispatch so a re-press also resets the quiet period.
                while !debounce.isReady(
                    at: .now,
                    modifiersHeld: !ThemeHotkeyModifiers(eventModifiers: NSEvent.modifierFlags)
                        .intersection(modifiers).isEmpty
                ) || pendingHotkeyApplyTask != nil || pendingAccessibilityApplyTask != nil {
                    try await Task.sleep(for: .milliseconds(10))
                }
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            hotkeyDebounceTask = nil
            hotkeyQueue.markReady(request)
            startNextHotkeyApply()
        }
    }

    private func startNextHotkeyApply() {
        guard let request = hotkeyQueue.takeReady() else { return }
        let payload = request.entry.payload
        let themeName = displayName(for: request.entry, inverted: false)
        let previousAccessibilityTask = pendingAccessibilityApplyTask
        pendingHotkeyApplyTask = Task { [weak self] in
            await previousAccessibilityTask?.value
            guard let self else { return }
            if hotkeyQueue.isCurrent(request) {
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try CodexAppearanceImporter.importTheme(payload, variant: payload.variant) }
                }.value
                switch result {
                case .success:
                    snapshot = snapshot(applying: payload)
                    if hotkeyQueue.isCurrent(request) {
                        refreshStatus = "Hotkey apply requested."
                        onThemeApplied?(themeName, payload.variant)
                    }
                case .failure(let error):
                    if hotkeyQueue.isCurrent(request) {
                        if case CodexAppearanceImporterError.debugBridgeUnavailable = error {
                            let accessibilityTask = handleUnavailableLiveBridge(
                                payload: payload,
                                themeName: themeName,
                                allowStateRecovery: false,
                                hotkeyRequest: request
                            )
                            await accessibilityTask?.value
                        } else {
                            refreshStatus = "Hotkey apply failed."
                            reloadGlobalState()
                        }
                    }
                }
            }
            if hotkeyQueue.isCurrent(request) {
                hotkeySelectionSnapshot = nil
            }
            hotkeyQueue.finish(request)
            pendingHotkeyApplyTask = nil
            publish()
        }
    }

    func restoreThemeBackup() {
        cancelPendingHotkeyApply()
        do {
            let data = try Data(contentsOf: paths.themeBackupURL)
            try data.write(to: paths.themeFileURL, options: .atomic)
            reloadThemeFile()
            if !reloadStatus.hasPrefix("Theme file read failed:") {
                reloadStatus = "Restored theme backup and loaded \(catalog.entries.count) themes from \(paths.themeFileURL.lastPathComponent)."
            }
        } catch {
            reloadStatus = "Theme backup restore failed: \(error.localizedDescription)"
        }
        publish()
    }

    func saveThemeBackup() {
        do {
            try writeThemeBackup()
            hasThemeBackupForCurrentSession = true
            reloadStatus = "Saved theme backup to \(paths.themeBackupURL.lastPathComponent)."
        } catch {
            reloadStatus = "Theme backup save failed: \(error.localizedDescription)"
        }
        publish()
    }

    @discardableResult
    func extractLiveCodexTheme() -> CustomThemeEntry? {
        do {
            let payload = try CodexAppearanceImporter.extractLiveTheme()
            return saveExtractedTheme(payload, status: "Extracted live Codex theme.")
        } catch {
            do {
                let payload = try fallbackExtractedThemePayload()
                return saveExtractedTheme(payload, status: "Extracted Codex theme from saved state.")
            } catch {
                reloadStatus = "Live Codex theme extraction failed: \(error.localizedDescription)"
                publish()
                return nil
            }
        }
    }

    func openThemeFile() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.themeFileURL])
    }

    func reloadThemeFile() {
        do {
            let markdown = try String(contentsOf: paths.themeFileURL, encoding: .utf8)
            catalog = ThemeMarkdownParser.parse(markdown)
            reloadStatus = "Loaded \(catalog.entries.count) themes from \(paths.themeFileURL.lastPathComponent)."
        } catch {
            catalog = ThemeCatalog(entries: [], issues: [])
            reloadStatus = "Theme file read failed: \(error.localizedDescription)"
        }
        publish()
    }

    func reloadGlobalState() {
        if let loadedSnapshot = try? stateStore.loadSnapshot() {
            snapshot = mergedSnapshot(from: loadedSnapshot)
        } else {
            snapshot = CodexGlobalStateSnapshot(appearanceTheme: nil, lightChromeTheme: nil, darkChromeTheme: nil, lightCodeThemeId: nil, darkCodeThemeId: nil)
        }
        publish()
    }

    func relaunchCodexWithLiveBridge() {
        if deferUntilApplyFinishes({ [weak self] in self?.relaunchCodexWithLiveBridge() }) { return }
        refreshStatus = SoftReloadCoordinator.relaunchWithLiveBridge()
        reloadGlobalState()
        publish()
    }

    private func publish() {
        onChange?()
    }

    @discardableResult
    private func handleUnavailableLiveBridge(
        payload: ThemeFilePayload,
        themeName: String,
        allowStateRecovery: Bool = true,
        hotkeyRequest: ThemeHotkeyApplyQueue.Request? = nil
    ) -> Task<Void, Never>? {
        guard let runningCodex = CodexAccessibilityImporter.runningCodex() else {
            if allowStateRecovery {
                applyThroughStateRecovery(
                    payload: payload,
                    themeName: themeName,
                    failureReason: nil,
                    requiresConfirmation: false
                )
            } else {
                refreshStatus = "Hotkeys require Codex to be running."
                publish()
            }
            return nil
        }

        guard CodexAccessibilityImporter.isTrusted() else {
            if !didRequestAccessibilityPermission {
                didRequestAccessibilityPermission = true
                CodexAccessibilityImporter.requestPermission()
                refreshStatus = "Enable Accessibility control for Codex ThemeWurx, then retry the action."
                publish()
                return nil
            }
            guard allowStateRecovery else {
                refreshStatus = "Enable Accessibility control for Codex ThemeWurx to use hotkeys without the live bridge."
                publish()
                return nil
            }
            applyThroughStateRecovery(
                payload: payload,
                themeName: themeName,
                failureReason: "Accessibility permission is unavailable.",
                requiresConfirmation: true
            )
            return nil
        }

        guard runningCodex.activate(options: []) else {
            guard allowStateRecovery else {
                refreshStatus = "Codex could not be activated for Accessibility hotkey apply."
                publish()
                return nil
            }
            applyThroughStateRecovery(
                payload: payload,
                themeName: themeName,
                failureReason: "Codex could not be activated for Accessibility apply.",
                requiresConfirmation: true
            )
            return nil
        }

        let operation = CodexAccessibilityOperation()
        pendingAccessibilityOperation = operation
        let processIdentifier = runningCodex.processIdentifier
        refreshStatus = "Applying through Codex Accessibility…"
        publish()
        pendingAccessibilityApplyTask = Task { [weak self] in
            let result = await CodexAccessibilityImporter.importTheme(
                payload,
                processIdentifier: processIdentifier,
                operation: operation
            )
            guard let self, clearPendingAccessibilityApply(operation) else {
                return
            }
            if let hotkeyRequest, !hotkeyQueue.isCurrent(hotkeyRequest) {
                if case .applied = result { snapshot = snapshot(applying: payload) }
                return
            }
            handleAccessibilityResult(
                result,
                payload: payload,
                themeName: themeName,
                allowStateRecovery: allowStateRecovery
            )
        }
        return pendingAccessibilityApplyTask
    }

    private func handleAccessibilityResult(
        _ result: CodexAccessibilityImportResult,
        payload: ThemeFilePayload,
        themeName: String,
        allowStateRecovery: Bool = true
    ) {
        switch result {
        case .applied(let restoreWarning):
            snapshot = snapshot(applying: payload)
            refreshStatus = restoreWarning ?? "Currently using Accessibility instead of bridge."
            onThemeApplied?(themeName, payload.variant)
            publish()
        case .cancelled(.superseded):
            break
        case .cancelled(.userInterrupted):
            refreshStatus = "Accessibility apply cancelled after keyboard, mouse, or scroll input."
            reloadGlobalState()
        case .failed(let message):
            refreshStatus = message
            publish()
            guard allowStateRecovery else { return }
            applyThroughStateRecovery(
                payload: payload,
                themeName: themeName,
                failureReason: message,
                requiresConfirmation: true
            )
        }
    }

    private func applyThroughStateRecovery(
        payload: ThemeFilePayload,
        themeName: String,
        failureReason: String?,
        requiresConfirmation: Bool
    ) {
        let codexIsRunning = CodexAccessibilityImporter.runningCodex() != nil
        if requiresConfirmation, codexIsRunning, !confirmStateRecovery(reason: failureReason) {
            refreshStatus = "Restart recovery cancelled."
            publish()
            return
        }

        let relaunchContext = SoftReloadCoordinator.prepareForMutation()
        do {
            snapshot = try stateStore.apply(payload: payload)
        } catch {
            let restartStatus = SoftReloadCoordinator.finishMutation(
                relaunchContext,
                globalStateURL: paths.globalStateURL
            )
            refreshStatus = "State fallback apply failed: \(error.localizedDescription) \(restartStatus)"
            reloadGlobalState()
            return
        }
        refreshStatus = SoftReloadCoordinator.finishMutation(
            relaunchContext,
            globalStateURL: paths.globalStateURL
        )
        onThemeApplied?(themeName, payload.variant)
        publish()
    }

    private func confirmStateRecovery(reason: String?) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restart Codex to apply this theme?"
        alert.informativeText = [
            reason,
            "Codex ThemeWurx can stop Codex, update its saved appearance, and relaunch it normally."
        ].compactMap { $0 }.joined(separator: "\n\n")
        alert.addButton(withTitle: "Restart and Apply")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response != .alertFirstButtonReturn {
            CodexAccessibilityImporter.runningCodex()?.activate(options: [])
        }
        return response == .alertFirstButtonReturn
    }

    private func cancelPendingAccessibilityApply(reason: CodexAccessibilityCancellationReason) {
        pendingAccessibilityOperation?.cancel(reason)
        pendingAccessibilityApplyTask?.cancel()
    }

    private func clearPendingAccessibilityApply(_ operation: CodexAccessibilityOperation) -> Bool {
        guard pendingAccessibilityOperation === operation else {
            return false
        }
        pendingAccessibilityApplyTask = nil
        pendingAccessibilityOperation = nil
        return true
    }

    private func snapshot(applying payload: ThemeFilePayload, to base: CodexGlobalStateSnapshot? = nil) -> CodexGlobalStateSnapshot {
        let snapshot = base ?? self.snapshot
        switch payload.variant {
        case .light:
            return CodexGlobalStateSnapshot(
                appearanceTheme: ApplyTarget.light.rawValue,
                lightChromeTheme: payload.theme,
                darkChromeTheme: snapshot.darkChromeTheme,
                lightCodeThemeId: payload.codeThemeId,
                darkCodeThemeId: snapshot.darkCodeThemeId
            )
        case .dark:
            return CodexGlobalStateSnapshot(
                appearanceTheme: ApplyTarget.dark.rawValue,
                lightChromeTheme: snapshot.lightChromeTheme,
                darkChromeTheme: payload.theme,
                lightCodeThemeId: snapshot.lightCodeThemeId,
                darkCodeThemeId: payload.codeThemeId
            )
        }
    }

    private func mergedSnapshot(from loadedSnapshot: CodexGlobalStateSnapshot) -> CodexGlobalStateSnapshot {
        let light = mergedSlot(
            currentTheme: snapshot.lightChromeTheme,
            currentCodeThemeId: snapshot.lightCodeThemeId,
            loadedTheme: loadedSnapshot.lightChromeTheme,
            loadedCodeThemeId: loadedSnapshot.lightCodeThemeId
        )
        let dark = mergedSlot(
            currentTheme: snapshot.darkChromeTheme,
            currentCodeThemeId: snapshot.darkCodeThemeId,
            loadedTheme: loadedSnapshot.darkChromeTheme,
            loadedCodeThemeId: loadedSnapshot.darkCodeThemeId
        )
        return CodexGlobalStateSnapshot(
            appearanceTheme: loadedSnapshot.appearanceTheme,
            lightChromeTheme: light.theme,
            darkChromeTheme: dark.theme,
            lightCodeThemeId: light.codeThemeId,
            darkCodeThemeId: dark.codeThemeId
        )
    }

    private func mergedSlot(
        currentTheme: ChromeTheme?,
        currentCodeThemeId: String?,
        loadedTheme: ChromeTheme?,
        loadedCodeThemeId: String?
    ) -> (theme: ChromeTheme?, codeThemeId: String?) {
        guard let loadedTheme else {
            return (nil, nil)
        }
        if let currentTheme,
           currentCodeThemeId == loadedCodeThemeId,
           currentTheme == invertedTheme(loadedTheme) {
            return (currentTheme, currentCodeThemeId)
        }
        return (loadedTheme, loadedCodeThemeId)
    }

    private func saveExtractedTheme(_ payload: ThemeFilePayload, status: String) -> CustomThemeEntry? {
        let entry = CustomThemeEntry(name: "Live Codex Theme", payload: payload)
        let draft = ThemeEditorDraft(entry: entry)
        guard let saved = createTheme(from: draft) else { return nil }
        reloadStatus = status
        publish()
        return saved
    }

    private func fallbackExtractedThemePayload() throws -> ThemeFilePayload {
        let snapshot = try stateStore.loadSnapshot()
        let variant = snapshot.appearanceTheme == "dark" ? ThemeVariant.dark : ThemeVariant.light
        let theme: ChromeTheme?
        let codeThemeId: String?
        switch variant {
        case .light:
            theme = snapshot.lightChromeTheme
            codeThemeId = snapshot.lightCodeThemeId
        case .dark:
            theme = snapshot.darkChromeTheme
            codeThemeId = snapshot.darkCodeThemeId
        }
        guard let theme else {
            throw ThemeExtractionError.missingTheme
        }
        return ThemeFilePayload(
            variant: variant,
            codeThemeId: codeThemeId ?? ThemeEditorDraft.defaultCodeThemeId,
            favorite: false,
            theme: theme
        )
    }

    @discardableResult
    private func mutateThemeFile(_ mutation: (ThemeCatalog) throws -> ThemeCatalog) -> Bool {
        do {
            try backupThemeFileIfNeeded()
            let updatedCatalog = try mutation(catalog)
            let markdown = ThemeMarkdownParser.serialize(updatedCatalog)
            try fileManager.createDirectory(at: paths.themeFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: paths.themeFileURL, atomically: true, encoding: .utf8)
            reloadThemeFile()
            reloadGlobalState()
            return true
        } catch {
            reloadStatus = "Theme file update failed: \(error.localizedDescription)"
            publish()
            return false
        }
    }

    private func backupThemeFileIfNeeded() throws {
        guard !hasThemeBackupForCurrentSession else { return }
        guard fileManager.fileExists(atPath: paths.themeFileURL.path) else { return }
        try writeThemeBackup()
        hasThemeBackupForCurrentSession = true
    }

    private func writeThemeBackup() throws {
        let data = try Data(contentsOf: paths.themeFileURL)
        try fileManager.createDirectory(at: paths.themeBackupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: paths.themeBackupURL, options: .atomic)
    }

    private func uniqueThemeName(_ proposedName: String, in entries: [CustomThemeEntry], excluding excludedIndex: Int?) -> String {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? "Untitled Theme" : trimmedName
        let existingNames = Set(entries.enumerated().compactMap { index, entry in
            index == excludedIndex ? nil : entry.name
        })
        guard existingNames.contains(baseName) else { return baseName }
        var suffix = 2
        while true {
            let candidate = "\(baseName) (\(suffix))"
            if !existingNames.contains(candidate) {
                return candidate
            }
            suffix += 1
        }
    }

    private func ensureThemeFileExists() {
        do {
            try paths.prepareThemeFile(fileManager: fileManager)
        } catch {
            reloadStatus = "Theme file recovery failed: \(error.localizedDescription)"
        }
    }

    private func startWatchdogs() {
        themeWatchdog = FileWatchdog(url: paths.themeFileURL) { [weak self] in
            Task { @MainActor in
                self?.reloadThemeFile()
            }
        }
        stateWatchdog = FileWatchdog(url: paths.globalStateURL) { [weak self] in
            Task { @MainActor in
                self?.reloadGlobalState()
            }
        }
        themeWatchdog?.start()
        stateWatchdog?.start()
    }

    private func selectedEntry(for target: ApplyTarget) -> CustomThemeEntry? {
        switch target {
        case .light:
            guard let liveTheme = snapshot.lightChromeTheme else { return nil }
            return lightEntries.first { entry in
                entry.codeThemeId == snapshot.lightCodeThemeId &&
                    (entry.theme == liveTheme || invertedPayload(entry.payload).theme == liveTheme)
            }
        case .dark:
            guard let liveTheme = snapshot.darkChromeTheme else { return nil }
            return darkEntries.first { entry in
                entry.codeThemeId == snapshot.darkCodeThemeId &&
                    (entry.theme == liveTheme || invertedPayload(entry.payload).theme == liveTheme)
            }
        }
    }

    private func isActiveTheme(_ entry: CustomThemeEntry, to target: ApplyTarget) -> Bool {
        matches(entry.payload, to: target)
    }

    private func isInvertedTheme(_ entry: CustomThemeEntry, to target: ApplyTarget) -> Bool {
        matches(invertedPayload(entry.payload), to: target)
    }

    private func matches(_ payload: ThemeFilePayload, to target: ApplyTarget) -> Bool {
        switch target {
        case .light:
            return snapshot.lightChromeTheme == payload.theme && snapshot.lightCodeThemeId == payload.codeThemeId
        case .dark:
            return snapshot.darkChromeTheme == payload.theme && snapshot.darkCodeThemeId == payload.codeThemeId
        }
    }

    private func displayName(for entry: CustomThemeEntry, inverted: Bool) -> String {
        inverted ? "\(entry.name) (inv)" : entry.name
    }

    private func invertedPayload(_ payload: ThemeFilePayload) -> ThemeFilePayload {
        return ThemeFilePayload(
            variant: payload.variant,
            codeThemeId: payload.codeThemeId,
            favorite: payload.favorite,
            theme: invertedTheme(payload.theme)
        )
    }

    private func invertedTheme(_ theme: ChromeTheme) -> ChromeTheme {
        ChromeTheme(
            accent: theme.accent,
            contrast: theme.contrast,
            fonts: theme.fonts,
            foreground: theme.background,
            opaqueWindows: theme.opaqueWindows,
            semanticColors: theme.semanticColors,
            background: theme.foreground
        )
    }

    private func currentFavoriteSelection(in snapshot: CodexGlobalStateSnapshot) -> (theme: ChromeTheme?, codeThemeId: String?) {
        switch snapshot.appearanceTheme {
        case ApplyTarget.dark.rawValue:
            return (snapshot.darkChromeTheme, snapshot.darkCodeThemeId)
        case ApplyTarget.light.rawValue:
            return (snapshot.lightChromeTheme, snapshot.lightCodeThemeId)
        default:
            return (nil, nil)
        }
    }

}

private enum ThemeExtractionError: LocalizedError {
    case missingTheme

    var errorDescription: String? {
        switch self {
        case .missingTheme:
            return "No current Codex theme was found."
        }
    }
}
