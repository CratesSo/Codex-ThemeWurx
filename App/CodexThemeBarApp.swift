import AppKit
import Carbon
import CodexThemeBarCore
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let themeManagerOutsideTextInputClick = Notification.Name("CodexThemeBar.themeManagerOutsideTextInputClick")
}

@main
struct CodexThemeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            ThemeBarSettingsView(hotkeyController: appDelegate.hotkeyController)
        }
    }
}

struct ThemeBarSettingsView: View {
    @ObservedObject var hotkeyController: ThemeHotkeyController

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Enable Keyboard Shortcuts",
                    isOn: Binding(
                        get: { hotkeyController.hotkeysEnabled },
                        set: { hotkeyController.setHotkeysEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .themeManagerCursor(.pointingHand)
            }

            Section {
                VStack(spacing: 24) {
                    shortcutRows([.lightPrevious, .lightNext])
                    shortcutRows([.darkPrevious, .darkNext])
                    shortcutRows([.favoritePrevious, .favoriteNext])
                    shortcutRows([.invertCurrent, .toggleAppearance])
                }
            }

            if let statusMessage = hotkeyController.statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcutRows(_ actions: [ThemeHotkeyAction]) -> some View {
        VStack(spacing: 10) {
            ForEach(actions, id: \.self) { action in
                VStack(alignment: .leading, spacing: 3) {
                    HotkeyRecorderRow(
                        title: action.title,
                        symbolName: action.symbolName,
                        shortcut: hotkeyController.binding(for: action),
                        onRecordingChanged: hotkeyController.setRecordingShortcut
                    )
                    if let error = hotkeyController.fieldErrors[action] {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

struct AppSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: ThemeBarModel
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    @AppStorage(MenuEffect.storageKey) private var menuEffect = MenuEffect.off.rawValue
    @State private var loginStatus: SMAppService.Status = .notRegistered
    @State private var accessibilityTrusted = false
    @State private var loginError: String?

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("GENERAL")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)

                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "power")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.tint)
                            .frame(width: 25)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Launch at Login")
                                .font(.body.weight(.semibold))
                            Text("Start ThemeWurx when you sign in to your Mac.")
                                .font(.caption)
                                .foregroundStyle(secondaryTextColor)
                        }
                        Spacer(minLength: 12)
                        Toggle("Launch at Login", isOn: Binding(
                            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                            set: { setLaunchAtLogin($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .themeManagerCursor(.pointingHand)
                    }
                    .padding(17)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)

                    if loginStatus == .requiresApproval {
                        Text("Allow ThemeWurx in System Settings → General → Login Items.")
                            .font(.caption)
                            .foregroundStyle(warningColor)
                    }
                    if let loginError {
                        Text(loginError)
                            .font(.caption)
                            .foregroundStyle(colorScheme == .dark ? Color.red : Color(red: 0.72, green: 0.12, blue: 0.12))
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("MENU ANIMATION")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.tint)
                                .frame(width: 25)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Menu Animation")
                                    .font(.body.weight(.semibold))
                                Text("Choose the effect shown while the menu is open.")
                                    .font(.caption)
                                    .foregroundStyle(secondaryTextColor)
                            }
                        }

                        Picker("Menu Animation", selection: $menuEffect) {
                            Text("Off").tag(MenuEffect.off.rawValue)
                            Text("Aurora").tag(MenuEffect.aurora.rawValue)
                            Text("Sparkles").tag(MenuEffect.rainbow.rawValue)
                            Text("Snow").tag(MenuEffect.snow.rawValue)
                            Text("Rain").tag(MenuEffect.rain.rawValue)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .themeManagerCursor(.pointingHand)

                        if let effect = MenuEffect(rawValue: menuEffect), effect != .off {
                            MenuEffectAdjustmentControl(title: "Speed", storageKey: effect.speedStorageKey)
                                .id(effect.rawValue)
                            MenuEffectAdjustmentControl(title: "Brightness", storageKey: effect.brightnessStorageKey)
                                .id(effect.rawValue)
                            if effect == .rainbow || effect == .aurora {
                                MenuEffectHueControls(effect: effect)
                                    .id(effect.rawValue)
                            }
                        }
                        if menuEffect == MenuEffect.rain.rawValue {
                            MenuRainMoreControls()
                        }
                    }
                    .padding(17)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("CODEX CONNECTION")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)

                    VStack(alignment: .leading, spacing: 17) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "bolt.horizontal.circle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.tint)
                                .frame(width: 25)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Live Bridge")
                                    .font(.body.weight(.semibold))
                                Text(model.refreshStatus)
                                    .font(.caption)
                                    .foregroundStyle(secondaryTextColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Button("Relaunch Codex With Live Bridge") {
                            model.relaunchCodexWithLiveBridge()
                        }
                        .buttonStyle(.borderedProminent)
                        .themeManagerCursor(.pointingHand)
                        .padding(.leading, 39)

                        Divider()

                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "accessibility")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.tint)
                                .frame(width: 25)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("Accessibility")
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                    Label(accessibilityTrusted ? "Enabled" : "Permission needed", systemImage: "circle.fill")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(accessibilityTrusted ? successColor : warningColor)
                                }
                                Text("Allows theme switching when the live bridge is unavailable.")
                                    .font(.caption)
                                    .foregroundStyle(secondaryTextColor)
                            }
                        }
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .themeManagerCursor(.pointingHand)
                        .padding(.leading, 39)
                    }
                    .padding(17)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)
                }
            }
            .padding(24)
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onContentHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(settingsAccentColor)
        .onAppear(perform: refreshSystemStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemStatus()
        }
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .secondary : Color(white: 0.35)
    }

    private var successColor: Color {
        colorScheme == .dark ? .green : Color(red: 0.10, green: 0.43, blue: 0.20)
    }

    private var warningColor: Color {
        colorScheme == .dark ? .orange : Color(red: 0.58, green: 0.32, blue: 0.02)
    }

    private var settingsAccentColor: Color {
        guard colorScheme == .light else { return .accentColor }
        let accent = NSColor.controlAccentColor
        return Color(nsColor: accent.blended(withFraction: 0.18, of: .black) ?? accent)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.075) : Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.10 : 0.025))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    private func refreshSystemStatus() {
        loginStatus = SMAppService.mainApp.status
        accessibilityTrusted = CodexAccessibilityImporter.isTrusted()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Could not update Launch at Login: \(error.localizedDescription)"
        }
        refreshSystemStatus()
    }
}

private struct MenuRainMoreControls: View {
    @State private var isExpanded = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("More")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .themeManagerCursor(.pointingHand)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            VStack(spacing: 10) {
                ForEach(MenuRainParameter.allCases, id: \.self) { parameter in
                    MenuRainParameterControl(parameter: parameter)
                }
                HStack {
                    Button("Default") {
                        for parameter in MenuRainParameter.allCases {
                            UserDefaults.standard.set(parameter.defaultValue, forKey: parameter.storageKey)
                        }
                    }
                    .tint(.gray)
                    .foregroundStyle(.primary)
                    .themeManagerCursor(.pointingHand)
                    .help("Restore default rain settings in More")
                    Spacer()
                }
            }
            .padding(.top, 10)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .frame(height: isExpanded ? contentHeight : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
        }
    }
}

private struct MenuRainParameterControl: View {
    let parameter: MenuRainParameter
    @AppStorage private var value: Double

    init(parameter: MenuRainParameter) {
        self.parameter = parameter
        _value = AppStorage(wrappedValue: parameter.defaultValue, parameter.storageKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Length variation")
                .hidden()
                .overlay(alignment: .leading) { Text(parameter.title) }
                .fixedSize()
            Slider(value: $value, in: parameter.range) { Text(parameter.title) }
                .labelsHidden()
                .themeManagerCursor(.pointingHand)
                .accessibilityValue(parameter.display(value))
            if parameter == .hue {
                RoundedRectangle(cornerRadius: 4)
                    .fill(value == 1 ? Color.white : Color(hue: value, saturation: 0.692, brightness: 1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.25), lineWidth: 1)
                    }
                    .frame(width: 30, height: 18)
                    .frame(width: 60, alignment: .trailing)
                    .help(parameter.display(value))
            } else {
                Text(parameter.display(value))
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }
}

private struct MenuEffectSliderLabel: View {
    let title: String

    var body: some View {
        Text("Brightness")
            .hidden()
            .overlay(alignment: .leading) { Text(title) }
            .fixedSize()
    }
}

private struct MenuEffectAdjustmentControl: View {
    let title: String
    @AppStorage private var position: Double

    init(title: String, storageKey: String) {
        self.title = title
        _position = AppStorage(wrappedValue: 0.0, storageKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            MenuEffectSliderLabel(title: title)
            Slider(value: Binding(
                get: { position },
                set: { position = abs($0) < 0.05 ? 0 : $0 }
            ), in: -1...1) {
                Text(title)
            }
            .labelsHidden()
            .accessibilityValue(String(format: "%.2f times", pow(2, position)))
            .themeManagerCursor(.pointingHand)
            Text(String(format: "%.2f×", pow(2, position)))
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
    }
}

private struct MenuEffectHueControls: View {
    let effect: MenuEffect
    @State private var showColorPair = false
    @AppStorage(MenuEffect.auroraPairEnabledKey) private var pairEnabled = false
    @AppStorage(MenuEffect.auroraFirstColorKey) private var firstColor = "#20F2C7"
    @AppStorage(MenuEffect.auroraSecondColorKey) private var secondColor = "#A661FF"
    @AppStorage private var hue: Double
    @AppStorage private var useDefault: Bool

    init(effect: MenuEffect) {
        self.effect = effect
        _hue = AppStorage(wrappedValue: 0.0, effect.hueStorageKey)
        _useDefault = AppStorage(wrappedValue: true, effect.defaultHueStorageKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            MenuEffectSliderLabel(title: "Hue")
            Slider(value: Binding(
                get: { useDefault ? 0 : hue * 0.999 + 0.001 },
                set: {
                    if effect == .aurora { pairEnabled = false }
                    useDefault = $0 < 0.001
                    if !useDefault {
                        hue = max(0, ($0 - 0.001) / 0.999)
                    }
                }
            ), in: 0...1) {
                Text("Hue")
            }
            .labelsHidden()
            .help("Far-left endpoint restores default colors")
            .themeManagerCursor(.pointingHand)
            .accessibilityValue(useDefault ? "Default colors" : "\(Int(hue * 360)) degrees")
            if effect == .aurora {
                Button { showColorPair.toggle() } label: { colorSwatch }
                    .buttonStyle(.plain)
                    .themeManagerCursor(.pointingHand)
                    .help("Choose two Aurora colors")
                    .accessibilityLabel("Choose two Aurora colors")
                    .popover(isPresented: $showColorPair) {
                        HStack(alignment: .top, spacing: 14) {
                            ThemeColorPicker(text: colorBinding($firstColor))
                                .accessibilityLabel("First Aurora color")
                            ThemeColorPicker(text: colorBinding($secondColor))
                                .accessibilityLabel("Second Aurora color")
                        }
                        .padding(16)
                    }
            } else {
                colorSwatch
            }
        }
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<String> {
        Binding(
            get: { hex.wrappedValue },
            set: {
                hex.wrappedValue = $0
                pairEnabled = true
                useDefault = false
            }
        )
    }

    private var colorSwatch: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: swatchColors, startPoint: .leading, endPoint: .trailing))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.25), lineWidth: 1)
            }
            .frame(width: 30, height: 18)
            .frame(width: 50, alignment: .trailing)
            .themeManagerCursor(.pointingHand)
            .help(useDefault ? "Default color palette" : "Hue: \(Int(hue * 360))°")
            .accessibilityLabel(useDefault ? "Default color palette" : "Selected hue: \(Int(hue * 360)) degrees")
    }

    private var swatchColors: [Color] {
        if effect == .aurora && pairEnabled {
            return [
                Color(nsColor: NSColor(hexThemeColor: firstColor) ?? .systemTeal),
                Color(nsColor: NSColor(hexThemeColor: secondColor) ?? .systemPurple)
            ]
        }
        if useDefault {
            return effect == .aurora
                ? [.teal, .blue, .purple]
                : [.red, .yellow, .green, .cyan, .blue, .purple, .red]
        }
        let color = hue == 1 ? Color.white : Color(hue: hue, saturation: 0.85, brightness: 0.85)
        return [color, color]
    }
}

struct ThemeManagerView: View {
    @ObservedObject var model: ThemeBarModel
    @State private var selectedVariant = ThemeVariant.light
    @State private var searchText = ""
    @State private var selectedEntryID: String?
    @State private var draft: ThemeEditorDraft?
    @State private var savedDraft: ThemeEditorDraft?
    @State private var draftBaseline: ThemeEditorDraft?
    @State private var draftUndoStack: [ThemeEditorDraft] = []
    @State private var activeDraftEditSnapshots: [String: ThemeEditorDraft] = [:]
    @State private var draftSourceRow: ManagedThemeRow?
    @State private var isCreatingDraft = false
    @State private var pendingAction: ThemeEditorPendingAction?
    @State private var pendingCloseWindow: NSWindow?
    @State private var showUnsavedChanges = false
    @State private var sidebarWidth: CGFloat = 300
    @State private var pendingSelectedEntryID: String?
    @State private var scrollToEntryID: String?
    @State private var didMoveTheme = false
    @State private var expandedFolderIDs: Set<String> = []
    @State private var initializedDefaultExpandedVariants: Set<String> = []
    @State private var isWindowMoving = false
    @State private var folderNamePrompt: ThemeFolderNamePrompt?
    @State private var folderNameDraft = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Menu {
                        Button {
                            requestAction(.newTheme(.light))
                        } label: {
                            Label("New light theme", systemImage: "sun.max")
                        }

                        Button {
                            requestAction(.newTheme(.dark))
                        } label: {
                            Label("New dark theme", systemImage: "moon.stars")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 18, height: 18)
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(.borderless)
                    .themeManagerButtonFeedback()
                    .themeManagerButtonHover()
                    .help("Create a new theme")

                    Button {
                        beginCreateFolder()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .themeManagerButtonFeedback()
                    .themeManagerButtonHover()
                    .help("Create a folder")

                    ThemeManagerSearchField(text: $searchText)
                        .frame(height: 26)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

                Divider()
                    .opacity(0.45)

                ThemeManagerFolderSectionsView(
                    folders: currentFolders,
                    filteredRows: filteredRows,
                    emptyRow: ThemeManagerEmptyRow(variant: selectedVariant, searchText: searchText),
                    isWindowMoving: isWindowMoving,
                    expandedFolderIDs: $expandedFolderIDs,
                    scrollToEntryID: scrollToEntryID,
                    isActive: { model.isActiveTheme($0) },
                    appearance: { model.appearance(for: $0) },
                    isSelected: { $0.id == selectedEntryID },
                    onPreview: { requestAction(.preview($0)) },
                    onMoveToFolder: moveThemeToFolder,
                    onToggleFavorite: { model.toggleFavorite($0) },
                    onDuplicate: { requestAction(.duplicateTheme($0)) },
                    onDelete: { requestAction(.delete($0)) },
                    onSelect: { requestAction(.select($0.id)) },
                    onRenameFolder: beginRenameFolder,
                    onDeleteFolder: { requestAction(.deleteFolder($0)) },
                    onMoveFolder: moveFolder
                )
            }
            .themeManagerPanelBackground(cornerRadius: 18)
            .padding(.leading, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .padding(.trailing, 2)
            .frame(width: sidebarWidth)

            ThemeManagerSidebarResizeHandleView(sidebarWidth: $sidebarWidth)
                .frame(width: 12)
                .padding(.horizontal, -5.5)
                .zIndex(10)
                .help("Resize theme list")

            ThemeEditorPane(
                draft: Binding(
                    get: { draft },
                    set: { draft = $0 }
                ),
                savedDraft: savedDraft,
                validationErrors: draft?.validationErrors ?? [],
                canRevert: hasUndoableChanges || !draftUndoStack.isEmpty,
                canSave: canSaveDraft,
                onSubmitName: saveDraftName,
                onSave: { _ = saveDraft() },
                onPreviewDraft: { model.previewDraft($0) },
                onRemixColors: { generateRemixedDraftColors() },
                onChaosColors: { generateChaosDraftColors() },
                onBeginEdit: beginDraftEdit,
                onEndEdit: endDraftEdit,
                onRevert: { revertDraftStep() },
                onUndoAll: { undoAllDraftChanges() }
            )
            .frame(minWidth: 420, maxHeight: .infinity)
        }
        .onAppear {
            ensureDefaultExpandedFolder()
            ensureSelection(preferActive: true)
        }
        .onChange(of: selectedVariant) {
            ensureDefaultExpandedFolder()
        }
        .onChange(of: model.catalog) {
            ensureDefaultExpandedFolder()
            if let preservedEntryID = pendingSelectedEntryID,
               let selectedRow = currentRows.first(where: { $0.entry.id == preservedEntryID }) {
                didMoveTheme = false
                selectedEntryID = selectedRow.id
                pendingSelectedEntryID = nil
                ensureSelection()
            } else if didMoveTheme {
                didMoveTheme = false
                pendingSelectedEntryID = nil
                ensureSelection()
            } else {
                ensureSelection()
            }
        }
        .onChange(of: model.snapshot) {
            ensureSelection(preferActive: true)
        }
        .confirmationDialog("Save changes?", isPresented: $showUnsavedChanges) {
            Button("Save") {
                if saveDraft() {
                    runPendingAction()
                }
            }
            .disabled(!(draft?.isValid ?? false))
            Button("Discard", role: .destructive) {
                discardDraftChanges()
                runPendingAction()
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text("This theme has unsaved edits.")
        }
        .alert(folderNamePrompt?.title ?? "Folder", isPresented: Binding(
            get: { folderNamePrompt != nil },
            set: { if !$0 { folderNamePrompt = nil } }
        )) {
            TextField("Folder name", text: $folderNameDraft)
            Button("Cancel", role: .cancel) {
                folderNamePrompt = nil
            }
            Button("Save") {
                submitFolderNamePrompt()
            }
        }
        .background(ThemeManagerCloseGuard(
            onWindowMovingChanged: { isWindowMoving = $0 },
            shouldClose: { window in
                guard hasUnsavedChanges else {
                    pendingCloseWindow = nil
                    return true
                }
                pendingCloseWindow = window
                pendingAction = .closeWindow
                showUnsavedChanges = true
                return false
            }
        ))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Text("Theme Manager")
                        .font(.system(size: 17.3, weight: .semibold))
                    ThemeVariantPicker(
                        selectedVariant: selectedVariant,
                        selectVariant: { requestAction(.selectVariant($0)) }
                    )
                }
                .padding(.top, 5)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) {
                ThemeFileMenuButton(
                    canRestoreThemeBackup: model.canRestoreThemeBackup,
                    onExtractLiveCodexTheme: extractLiveCodexTheme,
                    onSaveThemeBackup: { model.saveThemeBackup() },
                    onRestoreThemeBackup: { model.restoreThemeBackup() },
                    onOpenThemeFile: { model.openThemeFile() },
                    onReloadThemeFile: { model.reloadThemeFile() }
                )
                .padding(.top, 5)
                .opacity(0.75)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .frame(width: 860)
        .frame(minHeight: 647)
    }

    private var currentRows: [ManagedThemeRow] {
        selectedVariant == .light ? model.lightRows : model.darkRows
    }

    private var currentFolders: [ThemeFolder] {
        let folders = model.catalog.folders(for: selectedVariant)
        return folders.filter { !$0.isImplicitUnfiled } + folders.filter(\.isImplicitUnfiled)
    }

    private var filteredRows: [ManagedThemeRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return currentRows }
        return currentRows.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var currentSelectedRow: ManagedThemeRow? {
        guard let selectedEntryID else { return nil }
        return currentRows.first { $0.id == selectedEntryID }
    }

    private var hasUnsavedChanges: Bool {
        draft != savedDraft
    }

    private var canSaveDraft: Bool {
        (draft?.isValid ?? false) && hasUnsavedChanges
    }

    private var hasUndoableChanges: Bool {
        guard let draft, let draftBaseline else { return false }
        return !draft.hasSameSettings(as: draftBaseline)
    }

    private func moveThemeToFolder(_ row: ManagedThemeRow, folderID: String, insertionIndex: Int) {
        didMoveTheme = true
        pendingSelectedEntryID = currentSelectedRow?.entry.id
        model.moveTheme(row, toFolderID: folderID, insertionIndex: insertionIndex)
    }

    private func moveFolder(_ folder: ThemeFolder, toOffset destination: Int) {
        requestAction(.moveFolder(folder.id, destination))
    }

    private func beginCreateFolder() {
        folderNameDraft = uniqueFolderName("New Folder", in: currentFolders)
        folderNamePrompt = ThemeFolderNamePrompt(mode: .create, variant: selectedVariant, folderID: nil)
    }

    private func beginRenameFolder(_ folder: ThemeFolder) {
        folderNameDraft = folder.name
        folderNamePrompt = ThemeFolderNamePrompt(mode: .rename, variant: folder.variant, folderID: folder.id)
    }

    private func submitFolderNamePrompt() {
        guard let prompt = folderNamePrompt else { return }
        let name = folderNameDraft
        folderNamePrompt = nil
        switch prompt.mode {
        case .create:
            requestAction(.createFolder(prompt.variant, name))
        case .rename:
            guard let folderID = prompt.folderID else { return }
            requestAction(.renameFolder(prompt.variant, folderID, name))
        }
    }

    private func uniqueFolderName(_ proposedName: String, in folders: [ThemeFolder]) -> String {
        let existingNames = Set(folders.filter { !$0.isImplicitUnfiled }.map(\.name))
        guard existingNames.contains(proposedName) else { return proposedName }
        var suffix = 2
        while true {
            let candidate = "\(proposedName) \(suffix)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            suffix += 1
        }
    }

    private func extractLiveCodexTheme() {
        let shouldSelectExtractedTheme = !hasUnsavedChanges
        guard let entry = model.extractLiveCodexTheme() else { return }
        guard shouldSelectExtractedTheme else { return }
        selectedVariant = entry.variant
        if let row = model.catalog.managedRows(for: entry.variant).first(where: { $0.entry.id == entry.id }) {
            selectedEntryID = row.id
            load(row)
        }
    }

    private func ensureSelection(preferActive: Bool = false) {
        if preferActive, !hasUnsavedChanges, let activeRow = currentActiveRow {
            if selectedEntryID != activeRow.id || draftSourceRow?.id != activeRow.id {
                selectedEntryID = activeRow.id
                load(activeRow)
            }
            return
        }
        if let selectedEntryID, let row = currentRows.first(where: { $0.id == selectedEntryID }) {
            if draftSourceRow?.id != row.id || (!hasUnsavedChanges && savedDraft != ThemeEditorDraft(entry: row.entry)) {
                load(row)
            } else {
                draftSourceRow = row
            }
            return
        }
        if let row = currentActiveRow ?? currentRows.first {
            selectedEntryID = row.id
            load(row)
        } else {
            selectedEntryID = nil
            draft = nil
            savedDraft = nil
            draftBaseline = nil
            clearDraftHistory()
            draftSourceRow = nil
            isCreatingDraft = false
        }
    }

    private func ensureDefaultExpandedFolder() {
        let variantKey = selectedVariant.rawValue
        guard !initializedDefaultExpandedVariants.contains(variantKey) else { return }
        currentFolders
            .filter(\.isImplicitUnfiled)
            .forEach { expandedFolderIDs.insert($0.id) }
        initializedDefaultExpandedVariants.insert(variantKey)
    }

    private func load(_ row: ManagedThemeRow) {
        let nextDraft = ThemeEditorDraft(entry: row.entry)
        draft = nextDraft
        savedDraft = nextDraft
        draftBaseline = nextDraft
        clearDraftHistory()
        draftSourceRow = row
        isCreatingDraft = false
    }

    private var currentActiveRow: ManagedThemeRow? {
        currentRows.first { model.isActiveTheme($0) }
    }

    private func preview(_ row: ManagedThemeRow) {
        selectedVariant = row.variant
        selectedEntryID = row.id
        load(row)
        model.previewTheme(row)
    }

    private func requestAction(_ action: ThemeEditorPendingAction) {
        if hasUnsavedChanges {
            pendingAction = action
            showUnsavedChanges = true
        } else {
            perform(action)
        }
    }

    private func runPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        perform(action)
    }

    private func perform(_ action: ThemeEditorPendingAction) {
        switch action {
        case .select(let id):
            selectedEntryID = id
            ensureSelection()
        case .preview(let row):
            preview(row)
        case .selectVariant(let variant):
            selectedVariant = variant
            selectedEntryID = nil
            ensureSelection(preferActive: true)
        case .newTheme(let variant):
            let source = model.catalog.managedRows(for: variant).first
            var nextDraft = source.map { ThemeEditorDraft(entry: $0.entry) } ?? ThemeEditorDraft.fallback(for: variant)
            nextDraft.name = variant == .light ? "New Light Theme" : "New Dark Theme"
            nextDraft.variant = variant
            nextDraft.favorite = false
            selectedVariant = variant
            draft = nextDraft
            savedDraft = nil
            draftBaseline = nextDraft
            clearDraftHistory()
            draftSourceRow = source ?? currentSelectedRow
            isCreatingDraft = true
        case .duplicateTheme(let source):
            var nextDraft = ThemeEditorDraft(entry: source.entry)
            nextDraft.name = source.name + " Copy"
            guard let entry = model.createTheme(from: nextDraft, toFolderID: source.folderID),
                  let row = model.catalog.managedRows(for: source.variant).first(where: { $0.entry.id == entry.id }) else { return }
            selectedVariant = row.variant
            selectedEntryID = row.id
            load(row)
            pendingSelectedEntryID = row.id
            expandedFolderIDs.insert(row.folderID)
            if !row.name.localizedCaseInsensitiveContains(searchText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                searchText = ""
            }
            scrollToEntryID = row.id
        case .delete(let row):
            clearDraftHistory()
            model.deleteTheme(row)
        case .createFolder(let variant, let name):
            pendingSelectedEntryID = currentSelectedRow?.entry.id
            model.createFolder(variant: variant, name: name)
        case .renameFolder(let variant, let folderID, let name):
            pendingSelectedEntryID = currentSelectedRow?.entry.id
            model.renameFolder(variant: variant, folderID: folderID, name: name)
        case .deleteFolder(let folder):
            clearDraftHistory()
            pendingSelectedEntryID = currentSelectedRow?.entry.id
            model.deleteFolder(variant: folder.variant, folderID: folder.id)
        case .moveFolder(let folderID, let destination):
            pendingSelectedEntryID = currentSelectedRow?.entry.id
            model.moveFolder(variant: selectedVariant, folderID: folderID, toOffset: destination)
        case .closeWindow:
            let window = pendingCloseWindow
            pendingCloseWindow = nil
            window?.close()
        }
    }

    @discardableResult
    private func saveDraft() -> Bool {
        guard let draft else { return false }
        let saved: CustomThemeEntry?
        if isCreatingDraft {
            saved = model.createTheme(from: draft)
        } else if let row = draftSourceRow {
            saved = model.saveThemeDraft(draft, replacing: row)
        } else {
            saved = nil
        }
        guard let saved else { return false }
        selectedVariant = saved.variant
        let nextDraft = ThemeEditorDraft(entry: saved)
        self.draft = nextDraft
        savedDraft = nextDraft
        draftBaseline = nextDraft
        clearDraftHistory()
        let savedRow = model.catalog.managedRows(for: saved.variant).first { $0.entry.id == saved.id }
        selectedEntryID = savedRow?.id
        if case .delete(let row) = pendingAction, row.id == draftSourceRow?.id, let savedRow {
            pendingAction = .delete(savedRow)
        }
        draftSourceRow = savedRow
        isCreatingDraft = false
        return true
    }

    private func saveDraftName() {
        guard !isCreatingDraft, let draft, var renamedDraft = savedDraft,
              let source = draftSourceRow, draft.name != renamedDraft.name else { return }
        renamedDraft.name = draft.name
        guard let entry = model.saveThemeDraft(renamedDraft, replacing: source) else { return }
        self.draft?.name = entry.name
        savedDraft = ThemeEditorDraft(entry: entry)
        draftSourceRow = model.catalog.managedRows(for: entry.variant).first { $0.entry.id == entry.id }
        selectedEntryID = draftSourceRow?.id
    }

    private func restoreDraftSettings(from snapshot: ThemeEditorDraft) {
        var restored = snapshot
        restored.name = draft?.name ?? snapshot.name
        draft = restored
    }

    private func discardDraftChanges() {
        clearDraftHistory()
        if isCreatingDraft {
            if let row = draftSourceRow {
                selectedEntryID = row.id
                load(row)
            }
            return
        }
        if let savedDraft {
            draft = savedDraft
        }
    }

    private func undoAllDraftChanges() {
        clearDraftHistory()
        if let draftBaseline {
            restoreDraftSettings(from: draftBaseline)
        }
    }

    private func generateRemixedDraftColors() {
        generateDraftColors(ThemeGeneratorPalette.remixedDraft)
    }

    private func generateChaosDraftColors() {
        generateDraftColors(ThemeGeneratorPalette.chaosDraft)
    }

    private func generateDraftColors(_ transform: (ThemeEditorDraft) -> ThemeEditorDraft) {
        guard let currentDraft = draft else { return }
        activeDraftEditSnapshots.removeAll()
        pushDraftUndoSnapshot(currentDraft)
        draft = transform(currentDraft)
    }

    private func revertDraftStep() {
        activeDraftEditSnapshots.removeAll()
        if let previousDraft = draftUndoStack.popLast() {
            restoreDraftSettings(from: previousDraft)
        } else if let savedDraft {
            restoreDraftSettings(from: savedDraft)
        }
    }

    private func beginDraftEdit(_ key: String, snapshot: ThemeEditorDraft) {
        guard activeDraftEditSnapshots[key] == nil else { return }
        activeDraftEditSnapshots[key] = snapshot
        pushDraftUndoSnapshot(snapshot)
    }

    private func endDraftEdit(_ key: String) {
        activeDraftEditSnapshots[key] = nil
    }

    private func pushDraftUndoSnapshot(_ snapshot: ThemeEditorDraft) {
        guard draftUndoStack.last?.hasSameSettings(as: snapshot) != true else { return }
        draftUndoStack.append(snapshot)
        if draftUndoStack.count > 50 {
            draftUndoStack.removeFirst(draftUndoStack.count - 50)
        }
    }

    private func clearDraftHistory() {
        draftUndoStack.removeAll()
        activeDraftEditSnapshots.removeAll()
    }
}

private enum ThemeEditorPendingAction: Equatable {
    case select(String)
    case preview(ManagedThemeRow)
    case selectVariant(ThemeVariant)
    case newTheme(ThemeVariant)
    case duplicateTheme(ManagedThemeRow)
    case delete(ManagedThemeRow)
    case createFolder(ThemeVariant, String)
    case renameFolder(ThemeVariant, String, String)
    case deleteFolder(ThemeFolder)
    case moveFolder(String, Int)
    case closeWindow
}

private struct ThemeFolderNamePrompt: Identifiable, Equatable {
    enum Mode: Equatable {
        case create
        case rename
    }

    let id = UUID()
    let mode: Mode
    let variant: ThemeVariant
    let folderID: String?

    var title: String {
        switch mode {
        case .create:
            return "New Folder"
        case .rename:
            return "Rename Folder"
        }
    }
}

private struct ThemeVariantPicker: View {
    let selectedVariant: ThemeVariant
    let selectVariant: (ThemeVariant) -> Void

    var body: some View {
        Picker("Theme appearance", selection: Binding(
            get: { selectedVariant },
            set: { selectVariant($0) }
        )) {
            Label("Light", systemImage: "sun.max").tag(ThemeVariant.light)
            Label("Dark", systemImage: "moon").tag(ThemeVariant.dark)
        }
        .pickerStyle(.segmented)
        .themeManagerCursor(.pointingHand)
        .labelsHidden()
        .controlSize(.large)
        .fixedSize()
        .help("Show light or dark themes")
    }
}

private struct ThemeManagerCloseGuard: NSViewRepresentable {
    let onWindowMovingChanged: (Bool) -> Void
    let shouldClose: (NSWindow) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowMovingChanged: onWindowMovingChanged, shouldClose: shouldClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.configure(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onWindowMovingChanged = onWindowMovingChanged
        context.coordinator.shouldClose = shouldClose
        guard let window = nsView.window else { return }
        context.coordinator.configure(window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        guard nsView.window?.delegate === coordinator else { return }
        nsView.window?.delegate = nil
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var onWindowMovingChanged: (Bool) -> Void
        var shouldClose: (NSWindow) -> Bool
        private weak var configuredWindow: NSWindow?
        private var moveGeneration = 0

        init(onWindowMovingChanged: @escaping (Bool) -> Void, shouldClose: @escaping (NSWindow) -> Bool) {
            self.onWindowMovingChanged = onWindowMovingChanged
            self.shouldClose = shouldClose
        }

        @MainActor
        func configure(_ window: NSWindow) {
            guard configuredWindow !== window || window.delegate !== self else {
                window.titlebarSeparatorStyle = .none
                return
            }
            configuredWindow = window
            window.delegate = self
            window.titlebarSeparatorStyle = .none
        }

        @MainActor
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            shouldClose(sender)
        }

        @MainActor
        func windowWillMove(_ _: Notification) {
            moveGeneration += 1
            onWindowMovingChanged(true)
        }

        @MainActor
        func windowDidMove(_ _: Notification) {
            moveGeneration += 1
            let generation = moveGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.moveGeneration == generation else { return }
                self.onWindowMovingChanged(false)
            }
        }
    }
}

private struct ThemeManagerSidebarResizeHandleView: NSViewRepresentable {
    @Binding var sidebarWidth: CGFloat

    func makeNSView(context: Context) -> SidebarResizeHandleNSView {
        let view = SidebarResizeHandleNSView()
        view.onDrag = { deltaX in
            sidebarWidth = min(360, max(260, sidebarWidth + deltaX))
        }
        return view
    }

    func updateNSView(_ nsView: SidebarResizeHandleNSView, context: Context) {
        nsView.onDrag = { deltaX in
            sidebarWidth = min(360, max(260, sidebarWidth + deltaX))
        }
    }
}

private final class SidebarResizeHandleNSView: NSView {
    var onDrag: ((CGFloat) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.deltaX)
    }
}

private enum ThemeManagerRowCoordinateSpace {
    static let name = "ThemeManagerRows"
}

private enum ThemeManagerFolderCoordinateSpace {
    static let name = "ThemeManagerFolders"
}

private enum ThemeManagerExternalDragEndResult {
    case notHandled
    case cancelled
    case acceptedMove
}

@MainActor
private enum ThemeManagerDragCursorLock {
    private static var monitor: Any?
    private static weak var window: NSWindow?
    static var isActive: Bool { monitor != nil }

    static func start() {
        NSCursor.closedHand.set()
        guard monitor == nil else { return }
        window = NSApp.currentEvent?.window ?? NSApp.keyWindow
        window?.disableCursorRects()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate]) { event in
            NSCursor.closedHand.set()
            return event
        }
    }

    static func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            window?.enableCursorRects()
            window = nil
            NSCursor.arrow.set()
        }
    }
}

private let themeManagerRowSlotHeight: CGFloat = 36
private let themeManagerExternalDropTargetHeight: CGFloat = 42
private let themeManagerDragSettleDuration = 0.176

private func themeManagerExternalDropTargetHeight(for index: Int) -> CGFloat {
    index == 0 ? themeManagerExternalDropTargetHeight + 6 : themeManagerExternalDropTargetHeight
}

private struct ThemeManagerRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ThemeManagerExternalRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ThemeManagerFolderFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ThemeManagerFolderHeaderFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ThemeManagerListHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ThemeManagerFolderListHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private func themeManagerFramesEqual(_ lhs: [String: CGRect], _ rhs: [String: CGRect], tolerance: CGFloat = 0.5) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (id, lhsFrame) in lhs {
        guard let rhsFrame = rhs[id],
              abs(lhsFrame.minX - rhsFrame.minX) <= tolerance,
              abs(lhsFrame.minY - rhsFrame.minY) <= tolerance,
              abs(lhsFrame.width - rhsFrame.width) <= tolerance,
              abs(lhsFrame.height - rhsFrame.height) <= tolerance else {
            return false
        }
    }
    return true
}

private func themeManagerValuesEqual(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
    abs(lhs - rhs) <= tolerance
}

private struct ThemeManagerFolderSectionsView<EmptyContent: View>: View {
    let folders: [ThemeFolder]
    let filteredRows: [ManagedThemeRow]
    let emptyRow: EmptyContent
    let isWindowMoving: Bool
    @Binding var expandedFolderIDs: Set<String>
    let scrollToEntryID: String?
    let isActive: (ManagedThemeRow) -> Bool
    let appearance: (ManagedThemeRow) -> (name: String, theme: ChromeTheme)
    let isSelected: (ManagedThemeRow) -> Bool
    let onPreview: (ManagedThemeRow) -> Void
    let onMoveToFolder: (ManagedThemeRow, String, Int) -> Void
    let onToggleFavorite: (ManagedThemeRow) -> Void
    let onDuplicate: (ManagedThemeRow) -> Void
    let onDelete: (ManagedThemeRow) -> Void
    let onSelect: (ManagedThemeRow) -> Void
    let onRenameFolder: (ThemeFolder) -> Void
    let onDeleteFolder: (ThemeFolder) -> Void
    let onMoveFolder: (ThemeFolder, Int) -> Void
    @State private var folderFrames: [String: CGRect] = [:]
    @State private var folderHeaderFrames: [String: CGRect] = [:]
    @State private var rowFramesInFolderSpace: [String: CGRect] = [:]
    @State private var folderListHeight: CGFloat = 0
    @State private var folderAutoScrollID: String?
    @State private var folderAutoScrollAnchor: UnitPoint = .center
    @State private var folderAutoScrollTick = 0
    @State private var dragPointerY: CGFloat?
    @State private var activeDropTargetFolderID: String?
    @State private var activeDropInsertionIndex: Int?
    @State private var activeDragSourceFolderID: String?
    @State private var dragGhostRow: ManagedThemeRow?
    @State private var dragGhostFrame: CGRect?
    @State private var dragGhostTranslation: CGSize = .zero
    @State private var dragGhostSettleID: UUID?
    @State private var draggedFolderID: String?
    @State private var folderDragFrame: CGRect?
    @State private var folderDragY: CGFloat = 0
    @State private var folderInsertionIndex: Int?
    @State private var folderSettleID: UUID?
    @State private var folderDragValue: DragGesture.Value?

    var body: some View {
        if folders.isEmpty {
            emptyRow
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                                    folderSection(folder, at: index)
                                    .id(folder.id)
                                    .zIndex(activeDragSourceFolderID == folder.id ? 100 : activeDropTargetFolderID == folder.id ? 10 : 0)
                                    .offset(y: folderReorderOffset(at: index))
                                    .animation(draggedFolderID != nil && folderSettleID == nil ? .easeOut(duration: 0.12) : nil, value: folderInsertionIndex)
                                    .opacity(draggedFolderID == folder.id ? 0 : 1)
                                    .background(folderFrameReader(for: folder.id))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .onChange(of: folderAutoScrollID) {
                            guard let folderAutoScrollID else { return }
                            withAnimation(.linear(duration: 0.26)) {
                                scrollProxy.scrollTo(folderAutoScrollID, anchor: folderAutoScrollAnchor)
                            }
                        }
                        .onChange(of: folderAutoScrollTick) {
                            guard let folderAutoScrollID else { return }
                            withAnimation(.linear(duration: 0.26)) {
                                scrollProxy.scrollTo(folderAutoScrollID, anchor: folderAutoScrollAnchor)
                            }
                        }
                        .onChange(of: scrollToEntryID) {
                            guard let scrollToEntryID else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                scrollProxy.scrollTo(scrollToEntryID, anchor: .center)
                            }
                        }
                    }
                    dragGhost
                    folderDragGhost
                }
                .coordinateSpace(name: ThemeManagerFolderCoordinateSpace.name)
                .preference(key: ThemeManagerFolderListHeightPreferenceKey.self, value: proxy.size.height)
            }
            .onPreferenceChange(ThemeManagerFolderFramePreferenceKey.self) {
                guard !isWindowMoving else { return }
                guard !themeManagerFramesEqual(folderFrames, $0) else { return }
                folderFrames = $0
                if let draggedFolderID, let value = folderDragValue,
                   let folder = folders.first(where: { $0.id == draggedFolderID }) {
                    updateFolderDrag(folder, value: value)
                }
            }
            .onPreferenceChange(ThemeManagerFolderHeaderFramePreferenceKey.self) {
                guard !isWindowMoving else { return }
                guard !themeManagerFramesEqual(folderHeaderFrames, $0) else { return }
                folderHeaderFrames = $0
            }
            .onPreferenceChange(ThemeManagerExternalRowFramePreferenceKey.self) {
                guard !isWindowMoving else { return }
                guard !themeManagerFramesEqual(rowFramesInFolderSpace, $0) else { return }
                rowFramesInFolderSpace = $0
            }
            .onPreferenceChange(ThemeManagerFolderListHeightPreferenceKey.self) {
                guard !isWindowMoving else { return }
                guard !themeManagerValuesEqual(folderListHeight, $0) else { return }
                folderListHeight = $0
            }
            .onChange(of: folders.map(\.id)) { clearFolderDrag() }
            .onDisappear { clearFolderDrag() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                clearFolderDrag()
            }
            .onChange(of: isWindowMoving) { if isWindowMoving { clearFolderDrag() } }
            .task(id: folderAutoScrollID) {
                guard folderAutoScrollID != nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(340))
                    guard !Task.isCancelled, folderAutoScrollID != nil else { return }
                    folderAutoScrollTick += 1
                }
            }
        }
    }

    private func folderSection(_ folder: ThemeFolder, at index: Int, isGhost: Bool = false) -> some View {
        ThemeManagerFolderSectionView(
            folder: folder,
            allRows: filteredRows,
            explicitFolderIndex: folders.prefix(index).filter { !$0.isImplicitUnfiled }.count,
            folderCount: movableFolders.count,
            isExpanded: isFolderExpanded(folder),
            setExpanded: { setFolder(folder, expanded: $0) },
            isActive: isActive,
            appearance: appearance,
            isSelected: isSelected,
            onPreview: onPreview,
            onMoveToFolder: onMoveToFolder,
            onToggleFavorite: onToggleFavorite,
            onDuplicate: onDuplicate,
            onDelete: onDelete,
            onSelect: onSelect,
            onRenameFolder: onRenameFolder,
            onDeleteFolder: onDeleteFolder,
            onMoveFolder: onMoveFolder,
            isGeometryTrackingEnabled: !isWindowMoving && !isGhost,
            isDropTarget: activeDropTargetFolderID == folder.id && activeDragSourceFolderID != folder.id,
            externalDropTargetIndex: activeDropTargetFolderID == folder.id && activeDragSourceFolderID != folder.id ? activeDropInsertionIndex : nil,
            headerFrame: folderHeaderFrameReader(for: folder.id, isEnabled: !isGhost),
            onDragPointerChanged: updateDragPointer,
            onDragGhostChanged: updateDragGhost,
            onDragEnded: handleDragEnd,
            isFolderDragActive: draggedFolderID != nil,
            onFolderDragChanged: { updateFolderDrag(folder, value: $0) },
            onFolderDragEnded: endFolderDrag
        )
    }

    private var movableFolders: [ThemeFolder] { folders.filter { !$0.isImplicitUnfiled } }

    private func folderReorderOffset(at index: Int) -> CGFloat {
        guard let draggedFolderID, let frame = folderDragFrame,
              let source = folders.firstIndex(where: { $0.id == draggedFolderID }),
              let insertion = folderInsertionIndex,
              !folders[index].isImplicitUnfiled else { return 0 }
        if index > source && index < insertion { return -(frame.height + 6) }
        if index < source && index >= insertion { return frame.height + 6 }
        return 0
    }

    @ViewBuilder
    private var folderDragGhost: some View {
        if let draggedFolderID, let frame = folderDragFrame,
           let index = folders.firstIndex(where: { $0.id == draggedFolderID }) {
            folderSection(folders[index], at: index, isGhost: true)
                .frame(width: frame.width, height: frame.height, alignment: .top)
                .offset(x: frame.minX, y: folderDragY)
                .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 5)
                .zIndex(1000)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func updateFolderDrag(_ folder: ThemeFolder, value: DragGesture.Value) {
        guard movableFolders.count > 1, !folder.isImplicitUnfiled, dragGhostRow == nil, folderSettleID == nil else { return }
        if draggedFolderID == nil {
            guard let frame = folderHeaderFrames[folder.id] else { return }
            setFolder(folder, expanded: false)
            folderDragFrame = frame
            draggedFolderID = folder.id
            ThemeManagerDragCursorLock.start()
        }
        guard draggedFolderID == folder.id, let frame = folderDragFrame else { return }
        folderDragValue = value
        let unfiledTop = folders.first(where: \.isImplicitUnfiled).flatMap { folderFrames[$0.id]?.minY }
        let upperBound = min(folderListHeight - frame.height, unfiledTop.map { $0 - frame.height - 6 } ?? .greatestFiniteMagnitude)
        folderDragY = min(max(frame.minY + value.translation.height, 0), max(upperBound, 0))
        folderInsertionIndex = movableFolders.firstIndex { candidate in
            guard let candidateFrame = folderFrames[candidate.id] else { return false }
            return value.location.y < candidateFrame.midY
        } ?? movableFolders.count
        updateFolderAutoScrollTarget(pointerY: value.location.y)
    }

    private func endFolderDrag(_ value: DragGesture.Value) {
        guard let draggedFolderID, folderSettleID == nil,
              let folder = folders.first(where: { $0.id == draggedFolderID }) else { return }
        updateFolderDrag(folder, value: value)
        ThemeManagerDragCursorLock.stop()
        folderAutoScrollID = nil
        guard let frame = folderDragFrame,
              let source = movableFolders.firstIndex(where: { $0.id == draggedFolderID }),
              let insertion = folderInsertionIndex else {
            clearFolderDrag()
            return
        }
        let location = value.location
        guard isPointerInsideFolderList(location.y), location.x >= 0, location.x <= frame.maxX + 8 else {
            clearFolderDrag()
            return
        }
        let targetY: CGFloat?
        if insertion == source || insertion == source + 1 {
            targetY = folderFrames[draggedFolderID]?.minY
        } else if insertion < movableFolders.count {
            targetY = folderFrames[movableFolders[insertion].id].map {
                $0.minY - (insertion > source ? frame.height + 6 : 0)
            }
        } else {
            targetY = movableFolders.last.flatMap { folderFrames[$0.id]?.maxY }.map { $0 - frame.height }
        }
        let settleID = UUID()
        folderSettleID = settleID
        withAnimation(.easeOut(duration: themeManagerDragSettleDuration)) {
            folderDragY = targetY ?? frame.minY
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + themeManagerDragSettleDuration) {
            guard folderSettleID == settleID else { return }
            withTransaction(Transaction(animation: nil)) {
                if insertion != source && insertion != source + 1 {
                    onMoveFolder(folder, insertion)
                }
                clearFolderDrag()
            }
        }
    }

    private func clearFolderDrag() {
        guard draggedFolderID != nil else { return }
        ThemeManagerDragCursorLock.stop()
        draggedFolderID = nil
        folderDragFrame = nil
        folderInsertionIndex = nil
        folderSettleID = nil
        folderDragValue = nil
        folderAutoScrollID = nil
        folderAutoScrollAnchor = .center
    }

    private func isFolderExpanded(_ folder: ThemeFolder) -> Bool {
        expandedFolderIDs.contains(folder.id)
    }

    private func setFolder(_ folder: ThemeFolder, expanded: Bool) {
        if expanded {
            expandedFolderIDs.insert(folder.id)
        } else {
            expandedFolderIDs.remove(folder.id)
        }
    }

    private func updateDragPointer(_ row: ManagedThemeRow, pointerY: CGFloat) {
        guard isPointerInsideFolderList(pointerY) else {
            dragPointerY = nil
            activeDropTargetFolderID = nil
            activeDropInsertionIndex = nil
            folderAutoScrollID = nil
            return
        }
        dragPointerY = pointerY
        if activeDragSourceFolderID != row.folderID {
            activeDragSourceFolderID = row.folderID
        }
        let targetFolder = folder(at: pointerY)
        let targetInsertionIndex = targetFolder.flatMap { folder in
            folder.id == row.folderID ? nil : insertionIndex(in: folder, pointerY: pointerY, sourceRow: row)
        }
        let targetFolderID = targetInsertionIndex.flatMap { _ in
            targetFolder?.id
        }
        if targetFolderID != activeDropTargetFolderID || targetInsertionIndex != activeDropInsertionIndex {
            activeDropTargetFolderID = targetFolderID
            activeDropInsertionIndex = targetInsertionIndex
        }
        updateFolderAutoScrollTarget(pointerY: pointerY)
    }

    private func updateDragGhost(row: ManagedThemeRow?, frame: CGRect?, translation: CGSize) {
        if row != nil {
            dragGhostSettleID = nil
        }
        dragGhostRow = row
        dragGhostFrame = frame
        dragGhostTranslation = translation
    }

    @ViewBuilder
    private var dragGhost: some View {
        if let dragGhostRow, let dragGhostFrame {
            let ghostY = min(
                max(dragGhostFrame.minY + dragGhostTranslation.height, 0),
                max(folderListHeight - dragGhostFrame.height, 0)
            )
            ThemeManagerSidebarRow(
                row: dragGhostRow,
                isActive: isActive(dragGhostRow),
                appearance: appearance(dragGhostRow),
                isSelected: isSelected(dragGhostRow),
                isReorderEnabled: false,
                isGhost: true,
                isDragActive: true,
                dragCoordinateSpaceName: ThemeManagerFolderCoordinateSpace.name,
                onPreview: {},
                onSelect: {},
                onDragChanged: { _ in },
                onDragEnded: {},
                onToggleFavorite: {},
                onDuplicate: {},
                onDelete: {}
            )
            .frame(width: dragGhostFrame.width, height: dragGhostFrame.height)
            .offset(x: dragGhostFrame.minX, y: ghostY)
            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 5)
            .zIndex(1000)
            .allowsHitTesting(false)
        }
    }

    private func handleDragEnd(_ row: ManagedThemeRow, insertionIndex sourceInsertionIndex: Int?) -> ThemeManagerExternalDragEndResult {
        let finishDrag: () -> Void = {
            dragPointerY = nil
            activeDropTargetFolderID = nil
            activeDropInsertionIndex = nil
            activeDragSourceFolderID = nil
            dragGhostSettleID = nil
            updateDragGhost(row: nil, frame: nil, translation: .zero)
            folderAutoScrollID = nil
            folderAutoScrollAnchor = .center
        }
        let settleAndMove: (ThemeFolder, Int) -> ThemeManagerExternalDragEndResult = { targetFolder, insertionIndex in
            if isNoOpDrop(in: targetFolder, insertionIndex: insertionIndex, sourceRow: row) {
                finishDrag()
                return .cancelled
            }
            let commitMove: () -> Void = {
                withTransaction(Transaction(animation: nil)) {
                    onMoveToFolder(row, targetFolder.id, insertionIndex)
                }
                DispatchQueue.main.async {
                    finishDrag()
                }
            }
            guard let targetY = dropTargetY(in: targetFolder, insertionIndex: insertionIndex, sourceRow: row),
                  let dragGhostFrame else {
                commitMove()
                return .acceptedMove
            }
            let settleID = UUID()
            dragGhostSettleID = settleID
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: themeManagerDragSettleDuration)) {
                    dragGhostTranslation.height = targetY - dragGhostFrame.minY
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + themeManagerDragSettleDuration) {
                    withTransaction(Transaction(animation: nil)) {
                        onMoveToFolder(row, targetFolder.id, insertionIndex)
                    }
                    guard dragGhostSettleID == settleID else { return }
                    finishDrag()
                }
            }
            return .acceptedMove
        }
        if let activeDropTargetFolderID,
           let targetFolder = folders.first(where: { $0.id == activeDropTargetFolderID }),
           targetFolder.id != row.folderID {
            return settleAndMove(targetFolder, activeDropInsertionIndex ?? targetFolder.entries.count)
        }
        guard let pointerY = dragPointerY,
              isPointerInsideFolderList(pointerY),
              let targetFolder = activeDropTargetFolderID.flatMap({ id in folders.first { $0.id == id } }) ?? folder(at: pointerY),
              !isHeaderTarget(targetFolder, pointerY: pointerY) else {
            finishDrag()
            return .cancelled
        }
        let insertionIndex = activeDropInsertionIndex
            ?? sourceInsertionIndex
            ?? insertionIndex(in: targetFolder, pointerY: pointerY, sourceRow: row)
            ?? targetFolder.entries.count
        return settleAndMove(targetFolder, insertionIndex)
    }

    private func isNoOpDrop(in folder: ThemeFolder, insertionIndex: Int, sourceRow: ManagedThemeRow) -> Bool {
        guard folder.id == sourceRow.folderID,
              let sourceIndex = folder.entries.firstIndex(where: { $0.id == sourceRow.entry.id }) else {
            return false
        }
        return insertionIndex == sourceIndex || insertionIndex == sourceIndex + 1
    }

    private func dropTargetY(in folder: ThemeFolder, insertionIndex: Int, sourceRow: ManagedThemeRow) -> CGFloat? {
        let targetRows = folder.entries.compactMap { entry in
            filteredRows.first { $0.entry.id == entry.id }
        }
        if folder.id != sourceRow.folderID {
            return externalDropTargetY(in: folder, insertionIndex: insertionIndex, targetRows: targetRows)
        }
        let targetIndex = stableDropTargetIndex(in: folder, insertionIndex: insertionIndex, sourceRow: sourceRow)
        if targetIndex < targetRows.count, let frame = rowFramesInFolderSpace[targetRows[targetIndex].id] {
            return frame.minY - sameFolderRowOffset(
                at: targetIndex,
                in: folder,
                insertionIndex: insertionIndex,
                sourceRow: sourceRow
            )
        }
        if let frame = targetRows.compactMap({ rowFramesInFolderSpace[$0.id] }).max(by: { $0.maxY < $1.maxY }) {
            return frame.maxY - themeManagerRowSlotHeight
        }
        guard let folderFrame = folderFrames[folder.id] else { return nil }
        return folderFrame.maxY - themeManagerRowSlotHeight - 6
    }

    private func externalDropTargetY(
        in folder: ThemeFolder,
        insertionIndex: Int,
        targetRows: [ManagedThemeRow]
    ) -> CGFloat? {
        let boundedInsertionIndex = min(max(insertionIndex, 0), targetRows.count)
        if boundedInsertionIndex < targetRows.count,
           let frame = rowFramesInFolderSpace[targetRows[boundedInsertionIndex].id] {
            return frame.minY - themeManagerExternalDropTargetHeight(for: boundedInsertionIndex)
        }
        if let frame = targetRows.compactMap({ rowFramesInFolderSpace[$0.id] }).max(by: { $0.maxY < $1.maxY }) {
            return frame.maxY
        }
        guard let folderFrame = folderFrames[folder.id] else { return nil }
        return folderFrame.maxY - themeManagerRowSlotHeight - 6
    }

    private func sameFolderRowOffset(
        at index: Int,
        in folder: ThemeFolder,
        insertionIndex: Int,
        sourceRow: ManagedThemeRow
    ) -> CGFloat {
        guard let sourceIndex = folder.entries.firstIndex(where: { $0.id == sourceRow.entry.id }),
              insertionIndex != sourceIndex,
              insertionIndex != sourceIndex + 1 else {
            return 0
        }
        if insertionIndex > sourceIndex,
           index > sourceIndex,
           index < insertionIndex {
            return -themeManagerRowSlotHeight
        }
        if insertionIndex < sourceIndex,
           index >= insertionIndex,
           index < sourceIndex {
            return themeManagerRowSlotHeight
        }
        return 0
    }

    private func stableDropTargetIndex(in folder: ThemeFolder, insertionIndex: Int, sourceRow: ManagedThemeRow) -> Int {
        let rowCount = folder.entries.count
        guard folder.id == sourceRow.folderID,
              let sourceIndex = folder.entries.firstIndex(where: { $0.id == sourceRow.id }) else {
            return min(max(insertionIndex, 0), rowCount)
        }
        if insertionIndex == sourceIndex || insertionIndex == sourceIndex + 1 {
            return sourceIndex
        }
        let adjustedIndex = insertionIndex > sourceIndex ? insertionIndex - 1 : insertionIndex
        return min(max(adjustedIndex, 0), rowCount)
    }

    private func insertionIndex(in folder: ThemeFolder, pointerY: CGFloat, sourceRow: ManagedThemeRow) -> Int? {
        if isHeaderTarget(folder, pointerY: pointerY) {
            return isFolderExpanded(folder) ? nil : folder.entries.count
        }
        let targetRows = folder.entries.compactMap { entry in
            filteredRows.first { $0.entry.id == entry.id && $0.id != sourceRow.id }
        }
        guard !targetRows.isEmpty else { return 0 }
        guard let firstRowFrame = targetRows.compactMap({ rowFramesInFolderSpace[$0.id] }).min(by: { $0.minY < $1.minY }),
              pointerY > firstRowFrame.minY else {
            return 0
        }
        for (index, row) in targetRows.enumerated() {
            guard let frame = rowFramesInFolderSpace[row.id] else { continue }
            if pointerY < frame.maxY {
                return pointerY < frame.midY ? index : index + 1
            }
        }
        return targetRows.count
    }

    private func isHeaderTarget(_ folder: ThemeFolder, pointerY: CGFloat) -> Bool {
        guard let frame = folderHeaderFrames[folder.id] else { return false }
        return pointerY >= frame.minY && pointerY <= frame.maxY
    }

    private func folder(at pointerY: CGFloat) -> ThemeFolder? {
        return folders.first { folder in
            guard let frame = folderFrames[folder.id] else { return false }
            return pointerY >= frame.minY && pointerY <= frame.maxY
        }
    }

    private func updateFolderAutoScrollTarget(pointerY: CGFloat) {
        guard folderListHeight > 0 else { return }
        let candidates = draggedFolderID == nil ? folders : movableFolders
        if pointerY < 48 {
            folderAutoScrollAnchor = .top
            folderAutoScrollID = nearbyFolderID(pointerY: pointerY, direction: -1, in: candidates) ?? candidates.first?.id
        } else if pointerY > folderListHeight - 48 {
            if draggedFolderID != nil, let last = candidates.last,
               let frame = folderFrames[last.id], frame.maxY <= folderListHeight {
                folderAutoScrollID = nil
                return
            }
            folderAutoScrollAnchor = .bottom
            folderAutoScrollID = nearbyFolderID(pointerY: pointerY, direction: 1, in: candidates) ?? candidates.last?.id
        } else {
            folderAutoScrollID = nil
        }
    }

    private func isPointerInsideFolderList(_ pointerY: CGFloat) -> Bool {
        guard folderListHeight > 0 else { return true }
        return pointerY >= 0 && pointerY <= folderListHeight
    }

    private func nearbyFolderID(pointerY: CGFloat, direction: Int, in candidates: [ThemeFolder]) -> String? {
        let orderedFolders = candidates.enumerated().compactMap { index, folder -> (Int, ThemeFolder, CGRect)? in
            guard let frame = folderFrames[folder.id] else { return nil }
            return (index, folder, frame)
        }
        guard let nearest = orderedFolders.min(by: { abs($0.2.midY - pointerY) < abs($1.2.midY - pointerY) }) else {
            return nil
        }
        let nextIndex = min(max(nearest.0 + direction, 0), candidates.count - 1)
        return candidates[nextIndex].id
    }

    private func folderFrameReader(for id: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ThemeManagerFolderFramePreferenceKey.self,
                value: [id: proxy.frame(in: .named(ThemeManagerFolderCoordinateSpace.name))]
            )
        }
    }

    private func folderHeaderFrameReader(for id: String, isEnabled: Bool) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ThemeManagerFolderHeaderFramePreferenceKey.self,
                value: isEnabled ? [id: proxy.frame(in: .named(ThemeManagerFolderCoordinateSpace.name))] : [:]
            )
        }
    }
}

private struct ThemeFolderActionsButton: NSViewRepresentable {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onRename: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> ThemeFolderMenuButton {
        let button = ThemeFolderMenuButton()
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.target = button
        button.action = #selector(ThemeFolderMenuButton.showActions)
        button.setAccessibilityLabel("Folder actions")
        button.actionsMenu.autoenablesItems = false
        for (index, title) in ["Rename", "Move Up", "Move Down", "Delete"].enumerated() {
            if index == 3 { button.actionsMenu.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: #selector(ThemeFolderMenuButton.performAction(_:)), keyEquivalent: "")
            item.target = button
            item.tag = index
            button.actionsMenu.addItem(item)
        }
        return button
    }

    func updateNSView(_ button: ThemeFolderMenuButton, context: Context) {
        button.actions = [onRename, onMoveUp, onMoveDown, onDelete]
        button.actionsMenu.item(withTag: 1)?.isEnabled = canMoveUp
        button.actionsMenu.item(withTag: 2)?.isEnabled = canMoveDown
    }
}

private final class ThemeFolderMenuButton: NSButton {
    var actions: [() -> Void] = []
    let actionsMenu = NSMenu()
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
        if let window {
            isHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private var hoverCursor: NSCursor {
        ThemeManagerDragCursorLock.isActive ? .closedHand : .pointingHand
    }

    override func cursorUpdate(with event: NSEvent) { hoverCursor.set() }
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        hoverCursor.set()
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let tint: NSColor = isHovered || isHighlighted ? .labelColor : .secondaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [tint]))
        if let symbol = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            symbol.draw(in: NSRect(x: bounds.midX - symbol.size.width / 2, y: bounds.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height))
        }
    }

    @objc func showActions() {
        actionsMenu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: bounds.maxY), in: self)
    }

    @objc func performAction(_ sender: NSMenuItem) { actions[sender.tag]() }
}

private struct ThemeManagerFolderSectionView<HeaderFrame: View>: View {
    @State private var isHeaderHovered = false
    let folder: ThemeFolder
    let allRows: [ManagedThemeRow]
    let explicitFolderIndex: Int
    let folderCount: Int
    let isExpanded: Bool
    let setExpanded: (Bool) -> Void
    let isActive: (ManagedThemeRow) -> Bool
    let appearance: (ManagedThemeRow) -> (name: String, theme: ChromeTheme)
    let isSelected: (ManagedThemeRow) -> Bool
    let onPreview: (ManagedThemeRow) -> Void
    let onMoveToFolder: (ManagedThemeRow, String, Int) -> Void
    let onToggleFavorite: (ManagedThemeRow) -> Void
    let onDuplicate: (ManagedThemeRow) -> Void
    let onDelete: (ManagedThemeRow) -> Void
    let onSelect: (ManagedThemeRow) -> Void
    let onRenameFolder: (ThemeFolder) -> Void
    let onDeleteFolder: (ThemeFolder) -> Void
    let onMoveFolder: (ThemeFolder, Int) -> Void
    let isGeometryTrackingEnabled: Bool
    let isDropTarget: Bool
    let externalDropTargetIndex: Int?
    let headerFrame: HeaderFrame
    let onDragPointerChanged: (ManagedThemeRow, CGFloat) -> Void
    let onDragGhostChanged: (ManagedThemeRow?, CGRect?, CGSize) -> Void
    let onDragEnded: (ManagedThemeRow, Int?) -> ThemeManagerExternalDragEndResult

    let isFolderDragActive: Bool
    let onFolderDragChanged: (DragGesture.Value) -> Void
    let onFolderDragEnded: (DragGesture.Value) -> Void

    private var canDragFolder: Bool { folderCount > 1 && !folder.isImplicitUnfiled }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    setExpanded(!isExpanded)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 14)
                }
                .buttonStyle(.borderless)
                .themeManagerCursor(.pointingHand)
                .themeManagerButtonFeedback()

                HStack(spacing: 6) {
                    Image(systemName: folder.isImplicitUnfiled ? "tray" : "folder")
                        .foregroundStyle(.secondary)
                    Text(folder.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text("\(folder.entries.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    if !isExpanded && folderRows.contains(where: isActive) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                            .shadow(color: Color.green.opacity(0.55), radius: 2, x: 0, y: 0)
                            .help("Contains the active theme")
                            .accessibilityLabel("Contains the active theme")
                    }
                    Spacer()
                }
                .frame(minHeight: 18)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isFolderDragActive { setExpanded(!isExpanded) }
                }
                .themeManagerCursor(.openHand, isEnabled: canDragFolder && !isFolderDragActive)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(ThemeManagerFolderCoordinateSpace.name))
                        .onChanged { if canDragFolder { onFolderDragChanged($0) } }
                        .onEnded { if canDragFolder { onFolderDragEnded($0) } },
                    including: canDragFolder ? .all : .none
                )
                if !folder.isImplicitUnfiled {
                    ThemeFolderActionsButton(
                        canMoveUp: explicitFolderIndex > 0,
                        canMoveDown: explicitFolderIndex < folderCount - 1,
                        onRename: { onRenameFolder(folder) },
                        onMoveUp: { onMoveFolder(folder, max(explicitFolderIndex - 1, 0)) },
                        onMoveDown: { onMoveFolder(folder, min(explicitFolderIndex + 2, folderCount)) },
                        onDelete: { onDeleteFolder(folder) }
                    )
                    .frame(width: 33, height: 26.4)
                    .padding(.horizontal, -1.5)
                    .padding(.trailing, -3)
                    .help("Folder actions")
                    .opacity(isHeaderHovered ? 1 : 0)
                    .allowsHitTesting(isHeaderHovered)
                }
            }
            .padding(.horizontal, 8)
            .background(headerFrame)
            .background(folderHeaderBackground, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
            .onHover { isHeaderHovered = $0 }
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.accentColor.opacity(0.75), lineWidth: 1)
                }
            }

            if isExpanded {
                ThemeManagerRowsScrollView(
                    rows: folderRows,
                    emptyRow: ThemeManagerFolderEmptyRows(folderName: folder.name),
                    isScrollEnabled: false,
                    isGeometryTrackingEnabled: isGeometryTrackingEnabled,
                    isReorderEnabled: true,
                    isActive: isActive,
                    appearance: appearance,
                    isSelected: isSelected,
                    onPreview: onPreview,
                    onMove: { sourceID, insertionIndex in
                        guard let row = folderRows.first(where: { $0.id == sourceID }) else { return }
                        onMoveToFolder(row, folder.id, insertionIndex)
                    },
                    onToggleFavorite: onToggleFavorite,
                    onDuplicate: onDuplicate,
                    onDelete: onDelete,
                    onSelect: onSelect,
                    externalDropTargetIndex: externalDropTargetIndex,
                    externalCoordinateSpaceName: ThemeManagerFolderCoordinateSpace.name,
                    onDragPointerChanged: onDragPointerChanged,
                    onDragGhostChanged: onDragGhostChanged,
                    onDragEndedExternal: onDragEnded
                )
                .frame(height: rowsViewHeight)
            }
        }
    }

    private var folderHeaderBackground: Color {
        isDropTarget ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045)
    }

    private var rowsViewHeight: CGFloat {
        let baseHeight = folderRows.isEmpty ? 54 : CGFloat(folderRows.count) * themeManagerRowSlotHeight + 12
        guard let externalDropTargetIndex else { return baseHeight }
        return baseHeight + themeManagerExternalDropTargetHeight(for: externalDropTargetIndex)
    }

    private var folderRows: [ManagedThemeRow] {
        allRows.filter { row in
            folder.entries.contains { $0.id == row.entry.id }
        }
    }
}

private struct ThemeManagerFolderEmptyRows: View {
    let folderName: String

    var body: some View {
        Text("\(folderName) is empty")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
    }
}

private struct ThemeManagerRowsScrollView<EmptyContent: View>: View {
    let rows: [ManagedThemeRow]
    let emptyRow: EmptyContent
    var isScrollEnabled = true
    var isGeometryTrackingEnabled = true
    let isReorderEnabled: Bool
    let isActive: (ManagedThemeRow) -> Bool
    let appearance: (ManagedThemeRow) -> (name: String, theme: ChromeTheme)
    let isSelected: (ManagedThemeRow) -> Bool
    let onPreview: (ManagedThemeRow) -> Void
    let onMove: (String, Int) -> Void
    let onToggleFavorite: (ManagedThemeRow) -> Void
    let onDuplicate: (ManagedThemeRow) -> Void
    let onDelete: (ManagedThemeRow) -> Void
    let onSelect: (ManagedThemeRow) -> Void
    var externalDropTargetIndex: Int?
    var coordinateSpaceName = ThemeManagerRowCoordinateSpace.name
    var externalCoordinateSpaceName: String?
    var onDragPointerChanged: (ManagedThemeRow, CGFloat) -> Void = { _, _ in }
    var onDragGhostChanged: (ManagedThemeRow?, CGRect?, CGSize) -> Void = { _, _, _ in }
    var onDragEndedExternal: (ManagedThemeRow, Int?) -> ThemeManagerExternalDragEndResult = { _, _ in .notHandled }
    @State private var draggedThemeID: String?
    @State private var dragInsertionIndex: Int?
    @State private var dragTranslation: CGSize = .zero
    @State private var dragRowFrames: [String: CGRect] = [:]
    @State private var dragExternalRowFrames: [String: CGRect] = [:]
    @State private var dragSourceFrame: CGRect?
    @State private var dragExternalSourceFrame: CGRect?
    @State private var dragGrabOffset: CGSize = .zero
    @State private var dragListHeight: CGFloat = 0
    @State private var dragAutoScrollID: String?
    @State private var dragAutoScrollAnchor: UnitPoint = .center
    @State private var autoScrollTick = 0
    @State private var pendingDragRow: ManagedThemeRow?
    @State private var pendingDragValue: DragGesture.Value?
    @State private var isDragUpdateScheduled = false
    @State private var isDropHandoffVisible = false
    @State private var isExternalGhostHandoff = false
    @State private var settlingGhostRow: ManagedThemeRow?
    @State private var settlingGhostFrame: CGRect?
    @State private var settlingGhostTranslation: CGSize = .zero
    @State private var settlingGhostID: UUID?
    @State private var settlingHiddenThemeID: String?

    var body: some View {
        Group {
            if isScrollEnabled {
                scrollingRows
            } else {
                nonScrollingRows
            }
        }
        .onPreferenceChange(ThemeManagerRowFramePreferenceKey.self) {
            guard isGeometryTrackingEnabled else { return }
            guard !themeManagerFramesEqual(dragRowFrames, $0) else { return }
            dragRowFrames = $0
        }
        .onPreferenceChange(ThemeManagerExternalRowFramePreferenceKey.self) {
            guard isGeometryTrackingEnabled else { return }
            guard !themeManagerFramesEqual(dragExternalRowFrames, $0) else { return }
            dragExternalRowFrames = $0
        }
        .onPreferenceChange(ThemeManagerListHeightPreferenceKey.self) {
            guard isGeometryTrackingEnabled else { return }
            guard isScrollEnabled else { return }
            guard !themeManagerValuesEqual(dragListHeight, $0) else { return }
            dragListHeight = $0
        }
        .onChange(of: rows.map(\.id)) {
            if draggedThemeID != nil {
                isDropHandoffVisible = true
                DispatchQueue.main.async {
                    cancelDrag(clearExternalGhost: !isExternalGhostHandoff)
                }
            } else if isExternalGhostHandoff {
                isExternalGhostHandoff = false
                cancelDrag(clearExternalGhost: false)
            } else {
                cancelDrag()
            }
        }
        .onChange(of: isReorderEnabled) {
            if !isReorderEnabled {
                cancelDrag()
            }
        }
        .task(id: dragAutoScrollID) {
            guard isScrollEnabled, dragAutoScrollID != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, dragAutoScrollID != nil else { return }
                autoScrollTick += 1
            }
        }
    }

    private var scrollingRows: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        rowsContent
                    }
                    .onChange(of: dragAutoScrollID) {
                        guard let dragAutoScrollID else { return }
                        withAnimation(.linear(duration: 0.22)) {
                            scrollProxy.scrollTo(dragAutoScrollID, anchor: dragAutoScrollAnchor)
                        }
                    }
                    .onChange(of: autoScrollTick) {
                        guard let dragAutoScrollID else { return }
                        withAnimation(.linear(duration: 0.22)) {
                            scrollProxy.scrollTo(dragAutoScrollID, anchor: dragAutoScrollAnchor)
                        }
                    }
                }
                dragGhost
            }
            .coordinateSpace(name: coordinateSpaceName)
            .preference(key: ThemeManagerListHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    private var nonScrollingRows: some View {
        ZStack(alignment: .topLeading) {
            rowsContent
            dragGhost
        }
        .coordinateSpace(name: coordinateSpaceName)
    }

    @ViewBuilder
    private var dragGhost: some View {
        if externalCoordinateSpaceName == nil {
            if let ghostRow, let frame = dragSourceFrame {
                rowView(ghostRow, isGhost: true)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY + dragTranslation.height)
                    .zIndex(1000)
                    .allowsHitTesting(false)
            }
            if let settlingGhostRow, let settlingGhostFrame {
                rowView(settlingGhostRow, isGhost: true)
                    .frame(width: settlingGhostFrame.width, height: settlingGhostFrame.height)
                    .offset(
                        x: settlingGhostFrame.minX,
                        y: settlingGhostFrame.minY + settlingGhostTranslation.height
                    )
                    .zIndex(1001)
                    .allowsHitTesting(false)
            }
        }
    }

    private var rowsContent: some View {
        LazyVStack(spacing: 0) {
            if rows.isEmpty {
                emptyRow
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if externalDropTargetIndex == index {
                        ThemeManagerDropTarget(height: themeManagerExternalDropTargetHeight(for: index))
                    }
                    rowView(row, isGhost: false)
                        .id(row.id)
                        .background(rowFrameReader(for: row.id))
                        .background(externalRowFrameReader(for: row.id))
                        .contentShape(Rectangle())
                        .opacity(isRowHiddenForDrag(row) ? 0 : 1)
                        .allowsHitTesting(!isRowHiddenForDrag(row))
                        .offset(y: rowDragOffset(at: index))
                        .animation(.easeOut(duration: 0.12), value: dragInsertionIndex)
                }
                if externalDropTargetIndex == rows.count {
                    ThemeManagerDropTarget(height: themeManagerExternalDropTargetHeight(for: rows.count))
                }
            }
        }
        .padding(.leading, 8)
        .padding(.vertical, 6)
    }

    private var ghostRow: ManagedThemeRow? {
        guard let draggedThemeID else { return nil }
        return rows.first { $0.id == draggedThemeID }
    }

    private func isRowHiddenForDrag(_ row: ManagedThemeRow) -> Bool {
        (row.id == draggedThemeID && !isDropHandoffVisible) || row.id == settlingHiddenThemeID
    }

    private func rowDragOffset(at index: Int) -> CGFloat {
        guard
            let draggedThemeID,
            let sourceIndex = rows.firstIndex(where: { $0.id == draggedThemeID }),
            let insertionIndex = dragInsertionIndex,
            insertionIndex != sourceIndex,
            insertionIndex != sourceIndex + 1
        else {
            return 0
        }

        if insertionIndex > sourceIndex,
           index > sourceIndex,
           index < insertionIndex {
            return -themeManagerRowSlotHeight
        }
        if insertionIndex < sourceIndex,
           index >= insertionIndex,
           index < sourceIndex {
            return themeManagerRowSlotHeight
        }
        return 0
    }

    private func rowView(_ row: ManagedThemeRow, isGhost: Bool) -> some View {
        ThemeManagerSidebarRow(
            row: row,
            isActive: isActive(row),
            appearance: appearance(row),
            isSelected: isSelected(row),
            isReorderEnabled: isReorderEnabled,
            isGhost: isGhost,
            isDragActive: draggedThemeID != nil,
            dragCoordinateSpaceName: dragGestureCoordinateSpaceName,
            onPreview: { onPreview(row) },
            onSelect: { onSelect(row) },
            onDragChanged: { updateDrag(row, value: $0) },
            onDragEnded: endDrag,
            onToggleFavorite: { onToggleFavorite(row) },
            onDuplicate: { onDuplicate(row) },
            onDelete: { onDelete(row) }
        )
        .frame(height: themeManagerRowSlotHeight)
        .shadow(color: isGhost ? Color.black.opacity(0.22) : Color.clear, radius: 10, x: 0, y: 5)
    }

    private var dragGestureCoordinateSpaceName: String {
        externalCoordinateSpaceName ?? coordinateSpaceName
    }

    private var usesExternalDragGeometry: Bool {
        externalCoordinateSpaceName != nil
    }

    private func updateDrag(_ row: ManagedThemeRow, value: DragGesture.Value) {
        guard isReorderEnabled else { return }
        if draggedThemeID != row.id {
            processDrag(row, value: value)
            return
        }
        pendingDragRow = row
        pendingDragValue = value
        schedulePendingDragUpdate()
    }

    private func schedulePendingDragUpdate() {
        guard !isDragUpdateScheduled else { return }
        isDragUpdateScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) {
            flushPendingDragUpdate()
        }
    }

    private func flushPendingDragUpdate() {
        isDragUpdateScheduled = false
        guard let row = pendingDragRow, let value = pendingDragValue else { return }
        pendingDragRow = nil
        pendingDragValue = nil
        processDrag(row, value: value)
    }

    private func processDrag(_ row: ManagedThemeRow, value: DragGesture.Value) {
        guard isReorderEnabled else { return }
        ThemeManagerDragCursorLock.start()
        if draggedThemeID != row.id {
            dragInsertionIndex = rows.firstIndex { $0.id == row.id }
            draggedThemeID = row.id
            dragSourceFrame = dragRowFrames[row.id]
            dragExternalSourceFrame = dragExternalRowFrames[row.id]
            guard let sourceFrame = dragGestureSourceFrame(for: row.id) else { return }
            dragGrabOffset = CGSize(
                width: value.startLocation.x - sourceFrame.minX,
                height: value.startLocation.y - sourceFrame.minY
            )
        }
        guard let sourceFrame = dragGestureSourceFrame(for: row.id) else { return }
        let dragDelta = CGSize(
            width: value.location.x - dragGrabOffset.width - sourceFrame.minX,
            height: value.location.y - dragGrabOffset.height - sourceFrame.minY
        )
        dragTranslation = dragDelta
        if let sourceFrame = dragExternalSourceFrame {
            onDragGhostChanged(row, sourceFrame, dragDelta)
        }
        if usesExternalDragGeometry {
            onDragPointerChanged(row, value.location.y)
        }
        let insertionIndex = draggedInsertionIndex(for: row.id, pointerY: value.location.y)
        if insertionIndex != dragInsertionIndex {
            dragInsertionIndex = insertionIndex
        }
        updateAutoScrollTarget(pointerY: value.location.y)
    }

    private func endDrag() {
        flushPendingDragUpdate()
        guard
            let draggedThemeID,
            let dragInsertionIndex,
            let draggedRow = rows.first(where: { $0.id == draggedThemeID })
        else {
            cancelDrag()
            return
        }

        switch onDragEndedExternal(draggedRow, dragInsertionIndex) {
        case .acceptedMove:
            isExternalGhostHandoff = true
            ThemeManagerDragCursorLock.stop()
            pendingDragRow = nil
            pendingDragValue = nil
            isDragUpdateScheduled = false
            dragAutoScrollID = nil
            dragAutoScrollAnchor = .center
            return
        case .cancelled:
            cancelDrag(clearExternalGhost: false)
            return
        case .notHandled:
            break
        }
        if isNoOpDrop(sourceID: draggedThemeID, insertionIndex: dragInsertionIndex) {
            cancelDrag()
            return
        }
        guard let targetY = dropTargetY(for: dragInsertionIndex, sourceID: draggedThemeID),
              let sourceFrame = dragSourceFrame else {
            withTransaction(Transaction(animation: nil)) {
                onMove(draggedThemeID, dragInsertionIndex)
            }
            cancelDrag()
            return
        }
        let finalTranslation = targetY - sourceFrame.minY
        settlingGhostRow = draggedRow
        settlingGhostFrame = sourceFrame
        settlingGhostTranslation = dragTranslation
        let settleID = UUID()
        settlingGhostID = settleID
        settlingHiddenThemeID = draggedThemeID
        cancelDrag()
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: themeManagerDragSettleDuration)) {
                settlingGhostTranslation.height = finalTranslation
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + themeManagerDragSettleDuration) {
                withTransaction(Transaction(animation: nil)) {
                    onMove(draggedThemeID, dragInsertionIndex)
                }
                if settlingHiddenThemeID == draggedThemeID {
                    settlingHiddenThemeID = nil
                }
                guard settlingGhostID == settleID else { return }
                settlingGhostRow = nil
                settlingGhostFrame = nil
                settlingGhostTranslation = .zero
                settlingGhostID = nil
            }
        }
    }

    private func isNoOpDrop(sourceID: String, insertionIndex: Int) -> Bool {
        guard let sourceIndex = rows.firstIndex(where: { $0.id == sourceID }) else { return false }
        return insertionIndex == sourceIndex || insertionIndex == sourceIndex + 1
    }

    private func cancelDrag(clearExternalGhost: Bool = true) {
        ThemeManagerDragCursorLock.stop()
        if clearExternalGhost {
            onDragGhostChanged(nil, nil, .zero)
        }
        draggedThemeID = nil
        dragInsertionIndex = nil
        dragTranslation = .zero
        dragSourceFrame = nil
        dragExternalSourceFrame = nil
        dragGrabOffset = .zero
        dragAutoScrollID = nil
        dragAutoScrollAnchor = .center
        pendingDragRow = nil
        pendingDragValue = nil
        isDragUpdateScheduled = false
        isDropHandoffVisible = false
    }

    private func dropTargetY(for insertionIndex: Int, sourceID: String) -> CGFloat? {
        guard let sourceIndex = rows.firstIndex(where: { $0.id == sourceID }) else { return nil }
        let targetIndex: Int
        if insertionIndex == sourceIndex || insertionIndex == sourceIndex + 1 {
            targetIndex = sourceIndex
        } else {
            targetIndex = insertionIndex > sourceIndex ? insertionIndex - 1 : insertionIndex
        }
        let boundedIndex = min(max(targetIndex, 0), max(rows.count - 1, 0))
        guard let frame = dragRowFrames[rows[boundedIndex].id] else { return nil }
        return frame.minY - rowDragOffset(at: boundedIndex)
    }

    private func draggedInsertionIndex(for sourceID: String, pointerY: CGFloat) -> Int {
        guard !rows.isEmpty else { return rows.firstIndex { $0.id == sourceID } ?? 0 }
        let targetFrames = usesExternalDragGeometry ? dragExternalRowFrames : dragRowFrames
        let targetRows = rows.enumerated().compactMap { index, row -> (Int, CGRect)? in
            guard row.id != sourceID, let frame = targetFrames[row.id] else { return nil }
            return (index, frame)
        }
        guard let first = targetRows.first else {
            return rows.firstIndex { $0.id == sourceID } ?? 0
        }
        if pointerY <= first.1.minY {
            return first.0
        }
        for (index, frame) in targetRows {
            if pointerY < frame.maxY {
                return pointerY < frame.midY ? index : index + 1
            }
        }
        return rows.count
    }

    private func updateAutoScrollTarget(pointerY: CGFloat) {
        guard isScrollEnabled else { return }
        guard dragListHeight > 0, rows.count > 1 else { return }
        if pointerY < 42 {
            dragAutoScrollAnchor = .top
            let targetIndex = max((dragInsertionIndex ?? 0) - 1, 0)
            dragAutoScrollID = rows[targetIndex].id
        } else if pointerY > dragListHeight - 42 {
            dragAutoScrollAnchor = .bottom
            let targetIndex = min((dragInsertionIndex ?? rows.count) + 1, rows.count - 1)
            dragAutoScrollID = rows[targetIndex].id
        } else {
            dragAutoScrollID = nil
        }
    }

    private func dragGestureSourceFrame(for id: String) -> CGRect? {
        if usesExternalDragGeometry {
            return dragExternalSourceFrame ?? dragExternalRowFrames[id]
        }
        return dragSourceFrame ?? dragRowFrames[id]
    }

    private func rowFrameReader(for id: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ThemeManagerRowFramePreferenceKey.self,
                value: [id: proxy.frame(in: .named(coordinateSpaceName))]
            )
        }
    }

    @ViewBuilder
    private func externalRowFrameReader(for id: String) -> some View {
        if isGeometryTrackingEnabled, let externalCoordinateSpaceName {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ThemeManagerExternalRowFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named(externalCoordinateSpaceName))]
                )
            }
        }
    }
}

private struct ThemeManagerDropTarget: View {
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(height: height)
            .padding(.horizontal, 4)
    }
}

private struct ThemeManagerEmptyRow: View {
    let variant: ThemeVariant
    let searchText: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: variant == .light ? "sun.max" : "moon.stars")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowSeparator(.hidden)
    }

    private var title: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No \(variant.rawValue) themes"
            : "No matching themes"
    }

    private var description: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Add more themes or switch tabs."
            : "Try another search or clear the filter."
    }
}

private struct ThemeManagerSidebarRow: View {
    let row: ManagedThemeRow
    let isActive: Bool
    let appearance: (name: String, theme: ChromeTheme)
    let isSelected: Bool
    let isReorderEnabled: Bool
    let isGhost: Bool
    let isDragActive: Bool
    let dragCoordinateSpaceName: String
    let onPreview: () -> Void
    let onSelect: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void
    let onToggleFavorite: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @State private var isStripPressed = false
    @State private var isStripDragging = false
    @State private var showDeleteConfirmation = false
    @AppStorage("ThemeManagerSkipDeleteConfirmations") private var skipDeleteConfirmations = false

    var body: some View {
        HStack(spacing: 6) {
            ThemeManagerSplitColorStrip(name: appearance.name, variant: row.variant, theme: appearance.theme, isActive: isActive)
                .contentShape(Rectangle())
                .themeManagerCursor(rowCursor, isEnabled: isReorderEnabled && !isGhost && !isDragActive)
                .gesture(stripDragGesture)

            HStack(spacing: 4) {
                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .themeManagerButtonFeedback()
                .frame(width: 30, height: 30)
                .themeManagerButtonHover(isEnabled: !isGhost, verticalPadding: -1)
                .help("Apply saved theme in Codex")
                .accessibilityLabel("Preview \(row.name) in Codex")
                .disabled(isGhost)

                Button(action: onToggleFavorite) {
                    Image(systemName: row.entry.isFavorite ? "heart.fill" : "heart")
                        .frame(width: 30, height: 30)
                        .foregroundStyle(row.entry.isFavorite ? Color.primary : Color.secondary)
                }
                .buttonStyle(.borderless)
                .themeManagerButtonFeedback()
                .frame(width: 30, height: 30)
                .themeManagerButtonHover(isEnabled: !isGhost, verticalPadding: -1)
                .help(row.entry.isFavorite ? "Remove favorite" : "Favorite theme")
                .accessibilityLabel(row.entry.isFavorite ? "Remove favorite" : "Favorite theme")
                .disabled(isGhost)

                Menu {
                    Button(action: onDuplicate) {
                        Label("Duplicate Theme", systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        if skipDeleteConfirmations {
                            onDelete()
                        } else {
                            showDeleteConfirmation = true
                        }
                    } label: {
                        Label("Delete Theme…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor.withAlphaComponent(1)))
                        .frame(width: 30, height: 30)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.borderless)
                // Menu template rendering overrides label colors; apply secondary alpha once here.
                .opacity(Double(NSColor.secondaryLabelColor.alphaComponent))
                .themeManagerButtonFeedback()
                .frame(width: 30, height: 30)
                .themeManagerButtonHover(isEnabled: !isGhost, verticalPadding: -1)
                .help("More actions for \(row.name)")
                .accessibilityLabel("More actions for \(row.name)")
                .disabled(isGhost)
            }
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(rowBackground)
        }
        .sheet(isPresented: $showDeleteConfirmation) {
            ThemeDeleteConfirmationView(
                themeName: row.name,
                skipDeleteConfirmations: $skipDeleteConfirmations,
                onCancel: { showDeleteConfirmation = false },
                onDelete: {
                    showDeleteConfirmation = false
                    onDelete()
                }
            )
        }
    }

    private var rowBackground: Color {
        if isGhost {
            return Color.primary.opacity(0.08)
        }
        if isSelected {
            return Color.primary.opacity(0.08)
        }
        return Color.clear
    }

    private var rowCursor: NSCursor {
        isStripPressed || isStripDragging ? .closedHand : .openHand
    }

    private var stripDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(dragCoordinateSpaceName))
            .onChanged { value in
                guard isReorderEnabled, !isGhost else { return }
                isStripPressed = true
                NSCursor.closedHand.set()
                guard isStripDragging || hypot(value.translation.width, value.translation.height) >= 4 else { return }
                isStripDragging = true
                onDragChanged(value)
            }
            .onEnded { _ in
                let wasDragging = isStripDragging
                isStripPressed = false
                isStripDragging = false
                guard !isGhost else { return }
                if wasDragging {
                    onDragEnded()
                } else {
                    onSelect()
                }
            }
    }
}

private struct ThemeDeleteConfirmationView: View {
    let themeName: String
    @Binding var skipDeleteConfirmations: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete \(themeName)?")
                .font(.headline)
            Text("This removes the theme from custom-themes.md.")
                .foregroundStyle(.secondary)
            Toggle("Don't show delete confirmations.", isOn: $skipDeleteConfirmations)
                .themeManagerCursor(.pointingHand)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .themeManagerCursor(.pointingHand)
                    .keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive, action: onDelete)
                    .themeManagerCursor(.pointingHand)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

private struct ThemeManagerSplitColorStrip: View {
    let name: String
    let variant: ThemeVariant
    let theme: ChromeTheme
    let isActive: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var nameTrailingPadding: CGFloat {
        isActive ? 30 : 10
    }

    private var foreground: Color {
        Color(nsColor: NSColor(hexThemeColor: theme.foreground) ?? .labelColor)
    }

    private var background: Color {
        Color(nsColor: NSColor(hexThemeColor: theme.background) ?? .windowBackgroundColor)
    }

    private var checkmarkColor: Color {
        // The trailing checkmark sits over the foreground half of the strip.
        let color = NSColor(foreground).usingColorSpace(.sRGB) ?? .black
        func linearize(_ component: CGFloat) -> CGFloat {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearize(color.redComponent)
            + 0.7152 * linearize(color.greenComponent)
            + 0.0722 * linearize(color.blueComponent)
        // Choose whichever monochrome color has the higher contrast ratio.
        return luminance > 0.179 ? .black : .white
    }

    private var borderColor: Color {
        if colorScheme == .dark {
            return (variant == .light ? background : foreground).opacity(0.5)
        }
        return (variant == .light ? foreground : background).opacity(0.5)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    background
                    foreground
                }

                ThemeStripLabel(name: name, foreground: foreground, background: background, fonts: theme.fonts)
                    .padding(.leading, 10)
                    .padding(.trailing, nameTrailingPadding)
                    .frame(width: proxy.size.width, alignment: .leading)
                    .allowsHitTesting(false)

                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(checkmarkColor)
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("Active theme")
                    .accessibilityHidden(!isActive)
                    .allowsHitTesting(false)
                    .opacity(isActive ? 1 : 0)
                    .animation(.easeInOut(duration: 0.16), value: isActive)
                    .padding(.trailing, 6)
                    .frame(width: proxy.size.width, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(borderColor, lineWidth: 1)
        }
        .themeManagerCursor(.openHand)
        .accessibilityLabel(name)
    }
}

private struct ThemeStripLabel: NSViewRepresentable {
    let name: String
    let foreground: Color
    let background: Color
    let fonts: ThemeFonts

    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.cell = ThemeStripLabelCell(textCell: "")
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        let family = unquotedFontName(fonts.ui)
        let fontName = family.isEmpty ? "" : (fonts.uiFace?.postscriptName ?? family)
        let font = NSFont(name: fontName, size: 13) ?? .systemFont(ofSize: 13, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        (label.cell as? ThemeStripLabelCell)?.outlineColor = NSColor(background)
        label.attributedStringValue = NSAttributedString(string: name, attributes: [
            .font: font,
            .foregroundColor: NSColor(foreground),
            .paragraphStyle: paragraphStyle
        ])
        label.setAccessibilityLabel(name)
        label.needsDisplay = true
    }
}

private final class ThemeStripLabelCell: NSTextFieldCell {
    var outlineColor: NSColor = .clear

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let fill = attributedStringValue
        let outline = NSMutableAttributedString(attributedString: fill)
        let font = fill.length > 0 ? fill.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
        // Native strokes are centered on glyph edges; repaint the fill to keep
        // the full letter weight and leave a 3.1-point outline outside it.
        outline.addAttributes([
            .strokeColor: outlineColor,
            .strokeWidth: 100 * 6.2 / (font?.pointSize ?? 13)
        ], range: NSRange(location: 0, length: outline.length))
        attributedStringValue = outline
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.setLineJoin(.round)
        context?.setLineCap(.round)
        super.drawInterior(withFrame: cellFrame, in: controlView)
        context?.restoreGState()
        attributedStringValue = fill
        super.drawInterior(withFrame: cellFrame, in: controlView)
    }
}

private struct ThemeGeneratorSplitButton: View {
    let onRemix: () -> Void
    let onChaos: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullButtons
                .fixedSize(horizontal: true, vertical: false)
            iconButtons
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func styledButtonStrip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(.primary.opacity(0.82))
            .frame(height: 26.1)
            .background(.primary.opacity(0.11), in: Capsule())
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
    }

    private var fullButtons: some View {
        styledButtonStrip {
            HStack(spacing: 0) {
                Button(action: onRemix) {
                    Label("Remix", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                        .frame(height: 18)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .themeManagerCursor(.pointingHand)
                .themeManagerButtonFeedback()
                .frame(height: 26.1)
                .themeManagerIconHover()
                .help("Remix theme colors")

                Rectangle()
                    .fill(.separator.opacity(0.35))
                    .frame(width: 1, height: 14)

                Button(action: onChaos) {
                    Label("Scramble", systemImage: "dice")
                        .labelStyle(.titleAndIcon)
                        .frame(height: 18)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .themeManagerCursor(.pointingHand)
                .themeManagerButtonFeedback()
                .frame(height: 26.1)
                .themeManagerIconHover()
                .help("Scramble theme colors")
            }
        }
    }

    private var iconButtons: some View {
        styledButtonStrip {
            HStack(spacing: 0) {
                Button(action: onRemix) {
                    Image(systemName: "sparkles")
                        .frame(width: 18, height: 18)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .themeManagerCursor(.pointingHand)
                .themeManagerButtonFeedback()
                .frame(height: 26.1)
                .themeManagerIconHover()
                .help("Remix theme colors")

                Rectangle()
                    .fill(.separator.opacity(0.35))
                    .frame(width: 1, height: 14)

                Button(action: onChaos) {
                    Image(systemName: "dice")
                        .frame(width: 18, height: 18)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .themeManagerCursor(.pointingHand)
                .themeManagerButtonFeedback()
                .frame(height: 26.1)
                .themeManagerIconHover()
                .help("Scramble theme colors")
            }
        }
    }
}

private struct ThemeRevertSplitButton: View {
    let canRevert: Bool
    let onRevert: () -> Void
    let onUndoAll: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onRevert) {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .themeManagerCursor(.pointingHand)
            .help("Revert one step")
            .disabled(!canRevert)

            Rectangle()
                .fill(.separator.opacity(0.35))
                .frame(width: 1, height: 14)

            Menu {
                Button(action: onUndoAll) {
                    Label("Undo All", systemImage: "arrow.counterclockwise")
                }
                .disabled(!canRevert)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .themeManagerCursor(.pointingHand)
            .help("Open revert options")
            .disabled(!canRevert)
        }
        .frame(height: 26.1)
        .foregroundStyle(.primary.opacity(0.82))
        .background(.primary.opacity(0.11), in: Capsule())
        .opacity(canRevert ? 1 : 0.45)
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.095), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .themeManagerButtonFeedback(isEnabled: canRevert)
    }
}

private struct ThemeEditorSaveButton: View {
    let isSaved: Bool
    let canSave: Bool
    let onSave: () -> Void

    private var isSaveEnabled: Bool { canSave && !isSaved }

    var body: some View {
        Button(action: onSave) {
            Label(isSaved ? "Saved" : "Save", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.body)
                .foregroundStyle(isSaved ? Color.primary.opacity(0.82) : Color.white)
                .frame(width: 73.9, height: 26.1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .themeManagerCursor(.pointingHand, isEnabled: isSaveEnabled)
        .themeManagerButtonFeedback(isEnabled: isSaveEnabled)
        .help(isSaved ? "Theme is saved" : "Save this theme")
        .disabled(!isSaveEnabled)
        .background(
            isSaved ? Color.primary.opacity(0.11) : Color.accentColor,
            in: Capsule()
        )
        .opacity(isSaved ? 0.45 : 1)
        .overlay {
            Capsule()
                .strokeBorder(isSaved ? Color.primary.opacity(0.095) : Color.clear, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .allowsHitTesting(isSaveEnabled)
    }
}

private struct ThemeEditorPane: View {
    @Binding var draft: ThemeEditorDraft?
    let savedDraft: ThemeEditorDraft?
    let validationErrors: [String]
    let canRevert: Bool
    let canSave: Bool
    let onSubmitName: () -> Void
    let onSave: () -> Void
    let onPreviewDraft: (ThemeEditorDraft) -> Void
    let onRemixColors: () -> Void
    let onChaosColors: () -> Void
    let onBeginEdit: (String, ThemeEditorDraft) -> Void
    let onEndEdit: (String) -> Void
    let onRevert: () -> Void
    let onUndoAll: () -> Void
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        if let draftBinding {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    TextField("Theme name", text: draftBinding.name)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(.horizontal, 10)
                        .frame(width: themeNameFieldWidth(for: draftBinding.wrappedValue.name), height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    nameFieldFocused ? Color.accentColor.opacity(0.88) : Color.primary.opacity(0.24),
                                    lineWidth: nameFieldFocused ? 1.35 : 1
                                )
                        }
                        .layoutPriority(-1)
                        .focused($nameFieldFocused)
                        .onSubmit {
                            onSubmitName()
                        }
                        .onChange(of: nameFieldFocused) {
                            if !nameFieldFocused {
                                onSubmitName()
                            }
                        }
                    Spacer(minLength: 0)
                    ThemeRevertSplitButton(
                        canRevert: canRevert,
                        onRevert: onRevert,
                        onUndoAll: onUndoAll
                    )
                    ThemeEditorSaveButton(
                        isSaved: savedDraft == draft || isNameOnlyEdit,
                        canSave: canSave,
                        onSave: onSave
                    )
                }

                ThemeEditorPreview(draft: draftBinding.wrappedValue)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), alignment: .leading, spacing: 20) {
                    ThemeColorField(title: "Foreground", text: historyBinding("foreground", draftBinding.foreground, draft: draftBinding), onRemix: { remixColorField(.foreground, draft: draftBinding) }, onEndEditing: { onEndEdit("foreground") })
                    ThemeColorField(title: "Background", text: historyBinding("background", draftBinding.background, draft: draftBinding), onRemix: { remixColorField(.background, draft: draftBinding) }, onEndEditing: { onEndEdit("background") })
                    ThemeColorField(title: "Accent", text: historyBinding("accent", draftBinding.accent, draft: draftBinding), onRemix: { remixColorField(.accent, draft: draftBinding) }, onEndEditing: { onEndEdit("accent") })
                    ThemeColorField(title: "Diff Added", text: historyBinding("diffAdded", draftBinding.diffAdded, draft: draftBinding), onRemix: { remixColorField(.diffAdded, draft: draftBinding) }, onEndEditing: { onEndEdit("diffAdded") })
                    ThemeColorField(title: "Diff Removed", text: historyBinding("diffRemoved", draftBinding.diffRemoved, draft: draftBinding), onRemix: { remixColorField(.diffRemoved, draft: draftBinding) }, onEndEditing: { onEndEdit("diffRemoved") })
                    ThemeContrastField(text: contrastBinding(for: draftBinding), onCommit: { oldValue in
                        var snapshot = draftBinding.wrappedValue
                        snapshot.contrast = oldValue
                        onBeginEdit("contrast", snapshot)
                        onEndEdit("contrast")
                    })
                    }
                    .padding(.top, 7)

                    VStack(spacing: 0) {
                        Divider()
                            .opacity(0.70)
                        fontRow(
                            title: "UI font",
                            key: "uiFont",
                            text: fontFamilyBinding(for: draftBinding, family: \.uiFont, face: \.uiFontFace),
                            face: draftBinding.wrappedValue.uiFontFace,
                            faceKeyPath: \.uiFontFace,
                            draft: draftBinding
                        )
                        Divider()
                            .opacity(0.70)
                        fontRow(
                            title: "Content font",
                            key: "contentFont",
                            text: contentFontBinding(for: draftBinding),
                            face: draftBinding.wrappedValue.contentFontFace,
                            faceKeyPath: \.contentFontFace,
                            draft: draftBinding,
                            defaultOptionLabel: "Use UI Font"
                        )
                        Divider()
                            .opacity(0.70)
                        fontRow(
                            title: "Code font",
                            key: "codeFont",
                            text: fontFamilyBinding(for: draftBinding, family: \.codeFont, face: \.codeFontFace),
                            face: draftBinding.wrappedValue.codeFontFace,
                            faceKeyPath: \.codeFontFace,
                            draft: draftBinding
                        )
                        Divider()
                            .opacity(0.70)
                    }

                    if !validationErrors.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(validationErrors, id: \.self) { error in
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.caption)
                    }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)

                editorFooter
            }
                .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .themeManagerPanelBackground(cornerRadius: 18)
            .padding(.top, 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .onAppear {
                DispatchQueue.main.async {
                    nameFieldFocused = false
                }
            }
            .onChange(of: savedDraft) {
                DispatchQueue.main.async {
                    nameFieldFocused = false
                }
                endAllHistoryEdits()
            }
            .onReceive(NotificationCenter.default.publisher(for: .themeManagerOutsideTextInputClick)) { _ in
                guard nameFieldFocused else { return }
                onSubmitName()
                nameFieldFocused = false
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "paintpalette")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Select a theme")
                    .font(.headline)
                Text("Choose a light or dark theme to edit its colors and preview.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themeManagerPanelBackground(cornerRadius: 18)
            .padding(12)
        }
    }

    private var editorFooter: some View {
        HStack(alignment: .center, spacing: 8) {
            ThemeGeneratorSplitButton(
                onRemix: onRemixColors,
                onChaos: onChaosColors
            )
            .layoutPriority(2)
            Spacer(minLength: 0)

        }
    }

    private var draftBinding: Binding<ThemeEditorDraft>? {
        guard let currentDraft = draft else { return nil }
        return Binding<ThemeEditorDraft>(
            get: { draft ?? currentDraft },
            set: { draft = $0 }
        )
    }

    private var isNameOnlyEdit: Bool {
        guard let draft, let savedDraft else { return false }
        return draft.name != savedDraft.name && draft.hasSameSettings(as: savedDraft)
    }

    private func contrastBinding(for draft: Binding<ThemeEditorDraft>) -> Binding<String> {
        Binding(
            get: { draft.wrappedValue.contrast },
            set: { value in
                var updatedDraft = draft.wrappedValue
                updatedDraft.contrast = value
                draft.wrappedValue = updatedDraft
            }
        )
    }

    private func fontRow(
        title: String,
        key: String,
        text: Binding<String>,
        face: ThemeFontFace?,
        faceKeyPath: WritableKeyPath<ThemeEditorDraft, ThemeFontFace?>,
        draft: Binding<ThemeEditorDraft>,
        defaultOptionLabel: String = "System default"
    ) -> some View {
        GeometryReader { geometry in
            let faceLabel = face?.fullName ?? "Default"
            let faceWidth = fontFaceWidth(for: faceLabel)
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                    .frame(width: 100, alignment: .leading)
                Spacer(minLength: 0)
                ThemeFontSearchField(
                    title: title,
                    text: historyBinding(key, text, draft: draft),
                    prompt: defaultOptionLabel,
                    defaultOptionLabel: defaultOptionLabel,
                    onEndEditing: { onEndEdit(key) }
                )
                .frame(width: min(fontInputWidth(for: text.wrappedValue, prompt: defaultOptionLabel), max(100, geometry.size.width - 124 - faceWidth)))
                ThemeFontFacePicker(
                    title: title,
                    family: text.wrappedValue,
                    face: face,
                    onSelect: { setFontFace($0, for: faceKeyPath, key: key + "Face", draft: draft) }
                )
                .frame(width: faceWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 40)
    }

    private func fontInputWidth(for family: String, prompt: String) -> CGFloat {
        let selectedName = unquotedFontName(family)
        let displayedName = selectedName.isEmpty ? prompt : selectedName
        let textWidth = (displayedName as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]).width
        return min(250, max(112, ceil(textWidth) + 44))
    }

    private func fontFaceWidth(for label: String) -> CGFloat {
        let textWidth = (label as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 13)
        ]).width
        return min(160, max(82, ceil(textWidth) + 44))
    }

    private func contentFontBinding(for draft: Binding<ThemeEditorDraft>) -> Binding<String> {
        Binding(
            get: { draft.wrappedValue.contentFont ?? "" },
            set: { value in
                var updatedDraft = draft.wrappedValue
                let previousFamily = unquotedFontName(updatedDraft.contentFont ?? "")
                let selectedFamily = unquotedFontName(value)
                updatedDraft.contentFont = selectedFamily.isEmpty ? nil : value
                if selectedFamily.isEmpty || previousFamily.caseInsensitiveCompare(selectedFamily) != .orderedSame {
                    updatedDraft.contentFontFace = nil
                }
                draft.wrappedValue = updatedDraft
            }
        )
    }

    private func fontFamilyBinding(
        for draft: Binding<ThemeEditorDraft>,
        family: WritableKeyPath<ThemeEditorDraft, String>,
        face: WritableKeyPath<ThemeEditorDraft, ThemeFontFace?>
    ) -> Binding<String> {
        Binding(
            get: { draft.wrappedValue[keyPath: family] },
            set: { value in
                var updatedDraft = draft.wrappedValue
                let previousFamily = unquotedFontName(updatedDraft[keyPath: family])
                let selectedFamily = unquotedFontName(value)
                updatedDraft[keyPath: family] = value
                if selectedFamily.isEmpty || previousFamily.caseInsensitiveCompare(selectedFamily) != .orderedSame {
                    updatedDraft[keyPath: face] = nil
                }
                draft.wrappedValue = updatedDraft
            }
        )
    }

    private func setFontFace(
        _ face: ThemeFontFace?,
        for keyPath: WritableKeyPath<ThemeEditorDraft, ThemeFontFace?>,
        key: String,
        draft: Binding<ThemeEditorDraft>
    ) {
        var updatedDraft = draft.wrappedValue
        guard updatedDraft[keyPath: keyPath] != face else { return }
        onBeginEdit(key, updatedDraft)
        updatedDraft[keyPath: keyPath] = face
        draft.wrappedValue = updatedDraft
        onEndEdit(key)
    }

    private func historyBinding(_ key: String, _ source: Binding<String>, draft: Binding<ThemeEditorDraft>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { value in
                if value != source.wrappedValue {
                    onBeginEdit(key, draft.wrappedValue)
                }
                source.wrappedValue = value
            }
        )
    }

    private func remixColorField(_ field: ThemeColorRemixField, draft: Binding<ThemeEditorDraft>) {
        var updatedDraft = draft.wrappedValue
        onBeginEdit(field.key, updatedDraft)
        let nextColor = ThemeGeneratorPalette.remixedColor(for: field, variant: updatedDraft.variant)
        switch field {
        case .foreground:
            updatedDraft.foreground = nextColor
        case .background:
            updatedDraft.background = nextColor
        case .accent:
            updatedDraft.accent = nextColor
        case .diffAdded:
            updatedDraft.diffAdded = nextColor
        case .diffRemoved:
            updatedDraft.diffRemoved = nextColor
        }
        draft.wrappedValue = updatedDraft
        onEndEdit(field.key)
        onPreviewDraft(updatedDraft)
    }

    private func endAllHistoryEdits() {
        for key in ["foreground", "background", "accent", "diffAdded", "diffRemoved", "uiFont", "uiFontFace", "contentFont", "contentFontFace", "codeFont", "codeFontFace", "contrast"] {
            onEndEdit(key)
        }
    }

    private func themeNameFieldWidth(for name: String) -> CGFloat {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Theme name" : trimmedName
        let textWidth = (displayName as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]).width
        return min(170, max(82, ceil(textWidth) + 24))
    }
}

private struct ThemeFileMenuButton: View {
    let canRestoreThemeBackup: Bool
    let onExtractLiveCodexTheme: () -> Void
    let onSaveThemeBackup: () -> Void
    let onRestoreThemeBackup: () -> Void
    let onOpenThemeFile: () -> Void
    let onReloadThemeFile: () -> Void

    var body: some View {
        Menu {
            Button {
                onExtractLiveCodexTheme()
            } label: {
                Label("Extract live Codex theme", systemImage: "square.and.arrow.down.on.square")
            }

            Divider()

            Button {
                onSaveThemeBackup()
            } label: {
                Label("Save Backup", systemImage: "square.and.arrow.down")
            }

            Button {
                onRestoreThemeBackup()
            } label: {
                Label("Load Backup", systemImage: "arrow.counterclockwise")
            }
            .disabled(!canRestoreThemeBackup)

            Divider()

            Button {
                onOpenThemeFile()
            } label: {
                Label("Show Theme File in Finder", systemImage: "finder")
            }

            Button {
                onReloadThemeFile()
            } label: {
                Label("Reload Theme File", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "doc.text")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .opacity(0.85)
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.visible)
        .themeManagerButtonFeedback()
        .themeManagerButtonHover()
        .help("Theme file")
    }
}

private extension ThemeEditorDraft {
    static func fallback(for variant: ThemeVariant) -> ThemeEditorDraft {
        switch variant {
        case .light:
            return ThemeEditorDraft(
                name: "New Light Theme",
                variant: .light,
                favorite: false,
                foreground: "#6e5f69",
                background: "#faf4ed",
                accent: "#d7827e",
                diffAdded: "#56949f",
                diffRemoved: "#b4637a",
                contrast: "68",
                codeFont: "Berkeley Mono Trial",
                uiFont: "IBM Plex Mono"
            )
        case .dark:
            return ThemeEditorDraft(
                name: "New Dark Theme",
                variant: .dark,
                favorite: false,
                foreground: "#e0def4",
                background: "#191724",
                accent: "#ebbcba",
                diffAdded: "#9ccfd8",
                diffRemoved: "#eb6f92",
                contrast: "68",
                codeFont: "Berkeley Mono Trial",
                uiFont: "IBM Plex Mono"
            )
        }
    }
}

private enum ThemeColorRemixField {
    case foreground
    case background
    case accent
    case diffAdded
    case diffRemoved

    var key: String {
        switch self {
        case .foreground:
            return "foreground"
        case .background:
            return "background"
        case .accent:
            return "accent"
        case .diffAdded:
            return "diffAdded"
        case .diffRemoved:
            return "diffRemoved"
        }
    }
}

private struct ThemeGeneratorPalette {
    static func remixedDraft(from draft: ThemeEditorDraft) -> ThemeEditorDraft {
        var nextDraft = draft
        let palette = Bool.random() ? harmonizedPalette(for: draft.variant) : independentPalette(for: draft.variant)
        nextDraft.foreground = palette.foreground
        nextDraft.background = palette.background
        nextDraft.accent = palette.accent
        nextDraft.diffAdded = palette.diffAdded
        nextDraft.diffRemoved = palette.diffRemoved
        return nextDraft
    }

    static func chaosDraft(from draft: ThemeEditorDraft) -> ThemeEditorDraft {
        var nextDraft = draft
        nextDraft.foreground = randomRGBColor()
        nextDraft.background = randomRGBColor()
        nextDraft.accent = randomRGBColor()
        nextDraft.diffAdded = randomRGBColor()
        nextDraft.diffRemoved = randomRGBColor()
        return nextDraft
    }

    static func remixedColor(for field: ThemeColorRemixField, variant: ThemeVariant) -> String {
        switch field {
        case .foreground:
            return textColor(hue: CGFloat.random(in: 0...1), variant: variant)
        case .background:
            return backgroundColor(hue: CGFloat.random(in: 0...1), variant: variant)
        case .accent:
            return color(hue: 0...1, saturation: 0.48...0.78, brightness: variant == .light ? 0.48...0.70 : 0.70...0.92)
        case .diffAdded:
            return color(hue: 0.28...0.44, saturation: 0.38...0.70, brightness: variant == .light ? 0.46...0.64 : 0.66...0.90)
        case .diffRemoved:
            return color(hue: 0.94...1.00, saturation: 0.40...0.72, brightness: variant == .light ? 0.50...0.68 : 0.72...0.94)
        }
    }

    private static func harmonizedPalette(for variant: ThemeVariant) -> Palette {
        let hue = CGFloat.random(in: 0...1)
        return Palette(
            foreground: textColor(hue: hue.shifted(by: CGFloat.random(in: -0.04...0.04)), variant: variant),
            background: backgroundColor(hue: hue.shifted(by: CGFloat.random(in: -0.03...0.03)), variant: variant),
            accent: color(hue: hue.shifted(by: CGFloat.random(in: 0.08...0.18)), saturation: 0.52...0.76, brightness: variant == .light ? 0.56...0.72 : 0.72...0.90),
            diffAdded: color(hue: 0.30...0.43, saturation: 0.38...0.66, brightness: variant == .light ? 0.48...0.62 : 0.66...0.86),
            diffRemoved: color(hue: 0.96...1.00, saturation: 0.42...0.70, brightness: variant == .light ? 0.50...0.68 : 0.72...0.92)
        )
    }

    private static func independentPalette(for variant: ThemeVariant) -> Palette {
        Palette(
            foreground: textColor(hue: CGFloat.random(in: 0...1), variant: variant),
            background: backgroundColor(hue: CGFloat.random(in: 0...1), variant: variant),
            accent: color(hue: 0...1, saturation: 0.48...0.78, brightness: variant == .light ? 0.48...0.70 : 0.70...0.92),
            diffAdded: color(hue: 0.28...0.44, saturation: 0.38...0.70, brightness: variant == .light ? 0.46...0.64 : 0.66...0.90),
            diffRemoved: color(hue: 0.94...1.00, saturation: 0.40...0.72, brightness: variant == .light ? 0.50...0.68 : 0.72...0.94)
        )
    }

    private static func textColor(hue: CGFloat, variant: ThemeVariant) -> String {
        switch variant {
        case .light:
            return color(hue: hue, saturation: 0.20...0.44, brightness: 0.18...0.30)
        case .dark:
            return color(hue: hue, saturation: 0.10...0.34, brightness: 0.78...0.94)
        }
    }

    private static func backgroundColor(hue: CGFloat, variant: ThemeVariant) -> String {
        switch variant {
        case .light:
            return color(hue: hue, saturation: 0.04...0.18, brightness: 0.91...0.98)
        case .dark:
            return color(hue: hue, saturation: 0.10...0.26, brightness: 0.08...0.17)
        }
    }

    private static func color(hue: ClosedRange<CGFloat>, saturation: ClosedRange<CGFloat>, brightness: ClosedRange<CGFloat>) -> String {
        color(hue: CGFloat.random(in: hue), saturation: saturation, brightness: brightness)
    }

    private static func color(hue: CGFloat, saturation: ClosedRange<CGFloat>, brightness: ClosedRange<CGFloat>) -> String {
        NSColor(
            calibratedHue: hue.wrappedUnit,
            saturation: CGFloat.random(in: saturation),
            brightness: CGFloat.random(in: brightness),
            alpha: 1
        ).hexThemeColor
    }

    private static func randomRGBColor() -> String {
        String(
            format: "#%02x%02x%02x",
            Int.random(in: 0...255),
            Int.random(in: 0...255),
            Int.random(in: 0...255)
        )
    }

    private struct Palette {
        let foreground: String
        let background: String
        let accent: String
        let diffAdded: String
        let diffRemoved: String
    }
}

private extension CGFloat {
    var wrappedUnit: CGFloat {
        let remainder = truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }

    func shifted(by amount: CGFloat) -> CGFloat {
        (self + amount).wrappedUnit
    }
}

private enum ThemeFontCatalog {
    static func families() -> [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    static func faces(for family: String) -> [ThemeFontFaceOption] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
            guard member.count >= 2,
                  let postscriptName = member[0] as? String,
                  let title = member[1] as? String else {
                return nil
            }
            let fullName = NSFont(name: postscriptName, size: 14)?.displayName ?? "\(family) \(title)"
            return ThemeFontFaceOption(
                title: title,
                face: ThemeFontFace(family: family, fullName: fullName, postscriptName: postscriptName)
            )
        }
    }

}

private struct ThemeFontFaceOption: Identifiable {
    let title: String
    let face: ThemeFontFace

    var id: String { face.postscriptName }
}

private func unquotedFontName(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2, trimmed.first == "\"", trimmed.last == "\"" else {
        return trimmed
    }
    return String(trimmed.dropFirst().dropLast())
}

private struct ThemeFontSearchField: View {
    let title: String
    @Binding var text: String
    var prompt = ""
    var defaultOptionLabel = "System default"
    var onEndEditing: () -> Void = {}
    @State private var isFocused = false
    @State private var isPopoverPresented = false
    @State private var searchText = ""
    @State private var didEndEditingForCurrentFocus = false
    @State private var isApplyingNavigationSelection = false
    @State private var navigationOptions: [Option]?
    @State private var fontFamilies: [String]?

    private enum Option: Hashable {
        case systemDefault
        case custom(String)
        case family(String)

        var label: String {
            switch self {
            case .systemDefault:
                return "System default"
            case let .custom(value):
                return "Use custom \(value)"
            case let .family(value):
                return value
            }
        }

        var textValue: String {
            switch self {
            case .systemDefault:
                return ""
            case let .custom(value), let .family(value):
                return value
            }
        }
    }

    var body: some View {
        return VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .trailing) {
                ThemeFontSearchTextField(
                    placeholder: prompt.isEmpty ? title : prompt,
                    text: $searchText,
                    displayText: isPopoverPresented ? searchText : selectedFontName,
                    isFocused: $isFocused,
                    onClick: openPopover,
                    onSubmit: finishEditing,
                    onExit: cancelSearch,
                    onMove: handleMoveCommand
                )
                    .onChange(of: searchText) {
                        if isApplyingNavigationSelection {
                            isApplyingNavigationSelection = false
                        } else {
                            navigationOptions = nil
                        }
                        didEndEditingForCurrentFocus = false
                    }
                    .onChange(of: isFocused, handleFocusChange)
                    .onChange(of: isPopoverPresented) {
                        if !isPopoverPresented {
                            searchText = ""
                            navigationOptions = nil
                            isFocused = false
                            DispatchQueue.main.async {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                            }
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 28)
                Button(action: openPopover) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .themeManagerCursor(.pointingHand)
                .padding(.trailing, 5)
            }
            .frame(height: 30)
            .themeManagerInputSurface(isFocused: isFocused)
            .popover(isPresented: $isPopoverPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                if isPopoverPresented, fontFamilies != nil {
                    let currentOption = activeOption
                    let highlightedOption = selectedOption
                    VStack(alignment: .leading, spacing: 0) {
                        ScrollView {
                            if displayedOptions.isEmpty {
                                Text("No matching fonts")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 12)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(displayedOptions, id: \.self) { option in
                                        Button {
                                            select(option)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Text(option == .systemDefault ? defaultOptionLabel : option.label)
                                                    .lineLimit(1)
                                                Spacer(minLength: 0)
                                                if option == currentOption {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 11, weight: .semibold))
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .themeManagerCursor(.pointingHand)
                                        .modifier(ThemeFontOptionHoverModifier(showsSelectionFill: option == highlightedOption))
                                    }
                                }
                            }
                        }
                        .frame(width: 320, height: 240)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var selectedFontName: String {
        unquotedFontName(text)
    }

    private var normalizedSearchText: String {
        unquotedFontName(searchText)
    }

    private var exactMatch: String? {
        guard !normalizedSearchText.isEmpty, let fontFamilies else { return nil }
        return fontFamilies.first {
            $0.caseInsensitiveCompare(normalizedSearchText) == .orderedSame
        }
    }

    private var matchingFamilies: [String] {
        guard let fontFamilies else { return [] }
        guard !normalizedSearchText.isEmpty else { return fontFamilies }
        return fontFamilies.filter {
            $0.range(of: normalizedSearchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var options: [Option] {
        var result: [Option] = [.systemDefault]
        if normalizedSearchText.isEmpty, case .custom = activeOption {
            result.append(activeOption)
        }
        if !normalizedSearchText.isEmpty && exactMatch == nil {
            result.append(.custom(normalizedSearchText))
        }
        result.append(contentsOf: matchingFamilies.map(Option.family))
        return result
    }

    private var displayedOptions: [Option] {
        navigationOptions ?? options
    }

    private var activeOption: Option {
        option(for: selectedFontName)
    }

    private var selectedOption: Option {
        option(for: normalizedSearchText.isEmpty ? selectedFontName : normalizedSearchText)
    }

    private func option(for value: String) -> Option {
        if value.isEmpty {
            return .systemDefault
        }
        if let family = fontFamilies?.first(where: {
            $0.caseInsensitiveCompare(value) == .orderedSame
        }) {
            return .family(family)
        }
        return .custom(value)
    }

    private func openPopover() {
        guard !isPopoverPresented else { return }
        if fontFamilies == nil {
            fontFamilies = ThemeFontCatalog.families()
        }
        searchText = ""
        navigationOptions = nil
        isPopoverPresented = true
    }

    private func select(_ option: Option) {
        navigationOptions = nil
        let selectedText = option.textValue
        text = selectedText
        searchText = ""
        isPopoverPresented = false
        finishEditing()
    }

    private func finishEditing() {
        if isPopoverPresented, !normalizedSearchText.isEmpty {
            text = exactMatch ?? normalizedSearchText
        }
        searchText = ""
        isPopoverPresented = false
        guard !didEndEditingForCurrentFocus else { return }
        didEndEditingForCurrentFocus = true
        onEndEditing()
    }

    private func cancelSearch() {
        searchText = ""
        isPopoverPresented = false
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard isFocused, !displayedOptions.isEmpty else { return }
        let availableOptions = displayedOptions
        let currentIndex = availableOptions.firstIndex(of: selectedOption) ?? 0
        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = currentIndex == 0 ? availableOptions.count - 1 : currentIndex - 1
        case .down:
            nextIndex = (currentIndex + 1) % availableOptions.count
        default:
            return
        }
        navigationOptions = availableOptions
        selectWithoutEnding(availableOptions[nextIndex])
    }

    private func selectWithoutEnding(_ option: Option) {
        isApplyingNavigationSelection = true
        text = option.textValue
    }

    private func handleFocusChange() {
        if isFocused {
            didEndEditingForCurrentFocus = false
        } else {
            finishEditing()
        }
    }
}

private struct ThemeFontFacePicker: View {
    let title: String
    let family: String?
    let face: ThemeFontFace?
    let onSelect: (ThemeFontFace?) -> Void
    @State private var isPopoverPresented = false
    @State private var faceOptions: [ThemeFontFaceOption]?

    private var options: [ThemeFontFaceOption] {
        faceOptions ?? []
    }

    private var selectedLabel: String {
        face?.fullName ?? "Default"
    }

    var body: some View {
        Button {
            if faceOptions == nil {
                faceOptions = ThemeFontCatalog.faces(for: unquotedFontName(family ?? ""))
            }
            isPopoverPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(selectedLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .themeManagerInputSurface()
        }
        .buttonStyle(.plain)
        .themeManagerCursor(.pointingHand)
        .disabled(unquotedFontName(family ?? "").isEmpty)
        .help("\(title) face")
        .popover(isPresented: $isPopoverPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            if isPopoverPresented, faceOptions != nil {
                ScrollView {
                    VStack(spacing: 0) {
                        optionRow("Default", face: nil)
                        ForEach(options) { option in
                            optionRow(option.title, face: option.face)
                        }
                    }
                }
                .frame(width: 200, height: min(CGFloat(options.count + 1) * 32, 240))
                .padding(.vertical, 4)
            }
        }
    }

    private func optionRow(_ label: String, face optionFace: ThemeFontFace?) -> some View {
        let isSelected = face?.postscriptName == optionFace?.postscriptName
        return Button {
            onSelect(optionFace)
            isPopoverPresented = false
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .themeManagerCursor(.pointingHand)
        .modifier(ThemeFontOptionHoverModifier(showsSelectionFill: false))
    }
}

private struct ThemeFontOptionHoverModifier: ViewModifier {
    let showsSelectionFill: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered
                        ? (showsSelectionFill ? Color.accentColor.opacity(0.26) : Color.primary.opacity(0.10))
                        : (showsSelectionFill ? Color.accentColor.opacity(0.16) : .clear))
                    .padding(.horizontal, 4)
            }
            .onHover { isHovered = $0 }
    }
}

private struct ThemeFontSearchTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let displayText: String
    @Binding var isFocused: Bool
    var onClick: () -> Void
    var onSubmit: () -> Void
    var onExit: () -> Void
    var onMove: (MoveCommandDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ThemeFontInputTextField {
        let textField = ThemeFontInputTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.onMouseDown = { [weak coordinator = context.coordinator] in
            DispatchQueue.main.async {
                coordinator?.parent.onClick()
            }
        }
        return textField
    }

    func updateNSView(_ nsView: ThemeFontInputTextField, context: Context) {
        context.coordinator.parent = self
        nsView.placeholderString = placeholder
        nsView.onMouseDown = { [weak coordinator = context.coordinator] in
            DispatchQueue.main.async {
                coordinator?.parent.onClick()
            }
        }
        if nsView.stringValue != displayText {
            nsView.stringValue = displayText
            nsView.clearTextSelection()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ThemeFontSearchTextField

        init(_ parent: ThemeFontSearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(.up)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(.down)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onExit()
                return true
            default:
                return false
            }
        }
    }
}

private final class ThemeFontInputTextField: NSTextField {
    var onMouseDown: (() -> Void)?

    func clearTextSelection() {
        guard let editor = window?.fieldEditor(false, for: self) as? NSTextView,
              window?.firstResponder === editor else { return }
        let end = (editor.string as NSString).length
        editor.setSelectedRange(NSRange(location: end, length: 0))
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

private struct ThemeColorField: View {
    let title: String
    @Binding var text: String
    var onRemix: (() -> Void)?
    var onEndEditing: () -> Void = {}
    @State private var isRemixHovered = false
    @State private var isPickerPresented = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Button {
                    isFocused = false
                    isPickerPresented = true
                } label: {
                    Rectangle()
                        .fill(Color(nsColor: NSColor(hexThemeColor: text) ?? .clear))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.plain)
                .themeManagerCursor(.pointingHand)
                .help("Choose \(title) color")
                .accessibilityLabel("Choose \(title) color")
                .accessibilityValue(text)
                .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
                    ThemeColorPicker(text: $text)
                }
                .onChange(of: isPickerPresented) {
                    if !isPickerPresented { onEndEditing() }
                }
                TextField("#RRGGBB", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(.leading, 9)
                    .padding(.trailing, 4)
                    .themeManagerCursor(.iBeam)
                    .focused($isFocused)
                    .onSubmit(onEndEditing)
                    .onChange(of: isFocused) {
                        if !isFocused {
                            onEndEditing()
                        }
                    }
                if let onRemix {
                    Button(action: onRemix) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .brightness(isRemixHovered ? 0.22 : 0)
                    .shadow(color: .white.opacity(isRemixHovered ? 0.24 : 0), radius: isRemixHovered ? 2 : 0)
                    .themeManagerButtonFeedback()
                    .themeManagerCursor(.pointingHand)
                    .help("Remix \(title)")
                    .padding(.trailing, 3)
                    .onHover { isRemixHovered = $0 }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .themeManagerInputSurface(isFocused: isFocused || isPickerPresented)
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeManagerOutsideTextInputClick)) { _ in
            if isFocused {
                isFocused = false
            }
        }
    }
}

private struct ThemeColorPicker: View {
    @Binding var text: String
    @State private var hue: CGFloat = 0
    @State private var saturation: CGFloat = 0
    @State private var brightness: CGFloat = 1

    private let scale: CGFloat = 0.6

    private var width: CGFloat { 320 * scale }
    private var squareHeight: CGFloat { 280 * scale }
    private var hueHeight: CGFloat { 42 * scale }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(
                        colors: [.white, Color(hue: Double(hue), saturation: 1, brightness: 1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    Circle()
                        .fill(Color(nsColor: selectedColor))
                        .frame(width: 42 * scale, height: 42 * scale)
                        .overlay(Circle().stroke(.white, lineWidth: 2.5 * scale))
                        .shadow(color: .black.opacity(0.45), radius: 2 * scale)
                        .position(
                            x: saturation * geometry.size.width,
                            y: (1 - brightness) * geometry.size.height
                        )
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    saturation = min(1, max(0, value.location.x / geometry.size.width))
                    brightness = 1 - min(1, max(0, value.location.y / geometry.size.height))
                    writeColor()
                })
            }
            .frame(height: squareHeight)

            Rectangle()
                .fill(.black)
                .frame(height: 1)

            GeometryReader { geometry in
                ZStack {
                    LinearGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, Color(nsColor: .magenta), .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    Circle()
                        .fill(Color(hue: Double(hue), saturation: 1, brightness: 1))
                        .frame(width: 38 * scale, height: 38 * scale)
                        .overlay(Circle().stroke(.white, lineWidth: 2.5 * scale))
                        .shadow(color: .black.opacity(0.45), radius: 2 * scale)
                        .position(x: hue * geometry.size.width, y: geometry.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    hue = min(1, max(0, value.location.x / geometry.size.width))
                    writeColor()
                })
            }
            .frame(height: hueHeight)
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 13 * scale))
        .overlay {
            RoundedRectangle(cornerRadius: 13 * scale)
                .stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .padding(5 * scale)
        .background(Color(nsColor: NSColor(white: 0.11, alpha: 1)), in: RoundedRectangle(cornerRadius: 18 * scale))
        .preferredColorScheme(.dark)
        .onAppear(perform: readColor)
    }

    private var selectedColor: NSColor {
        NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    private func readColor() {
        guard let color = NSColor(hexThemeColor: text)?.usingColorSpace(.deviceRGB) else { return }
        hue = color.hueComponent
        saturation = color.saturationComponent
        brightness = color.brightnessComponent
    }

    private func writeColor() {
        text = selectedColor.hexThemeColor
    }
}

private struct ThemeContrastField: View {
    @Binding var text: String
    var onCommit: (String) -> Void = { _ in }
    @State private var numberText = ""
    @State private var sliderEditStartText: String?
    @FocusState private var numberFocused: Bool

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(clampedContrast) },
            set: {
                let value = Int($0.rounded())
                if sliderEditStartText == nil {
                    sliderEditStartText = text
                }
                text = String(value)
                numberText = String(value)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Contrast")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Slider(value: sliderValue, in: 0...100) { editing in
                    if !editing { commitSlider() }
                }
                    .accessibilityLabel("Contrast")
                    .themeManagerCursor(.pointingHand)
                TextField("0", text: $numberText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .frame(width: 44, height: 24)
                    .themeManagerInputSurface(isFocused: numberFocused)
                    .focused($numberFocused)
                    .onSubmit(commitNumber)
                    .onChange(of: numberFocused) {
                        if !numberFocused {
                            commitNumber()
                        }
                    }
            }
        }
        .onAppear {
            syncNumberText()
        }
        .onChange(of: text) {
            if !numberFocused {
                syncNumberText()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeManagerOutsideTextInputClick)) { _ in
            if numberFocused {
                numberFocused = false
            }
        }
    }

    private var clampedContrast: Int {
        ThemeEditorDraft.clampedContrast(text)
    }

    private func syncNumberText() {
        numberText = String(clampedContrast)
    }

    private func commitNumber() {
        let value = ThemeEditorDraft.clampedContrast(numberText, fallback: clampedContrast)
        let committedText = String(value)
        if committedText != text {
            onCommit(text)
        }
        text = String(value)
        numberText = String(value)
    }

    private func commitSlider() {
        guard let oldValue = sliderEditStartText else { return }
        sliderEditStartText = nil
        if oldValue != text {
            onCommit(oldValue)
        }
    }
}

private struct ThemePreviewText: NSViewRepresentable {
    let text: AttributedString
    let font: NSFont
    let color: NSColor

    init(_ text: String, font: NSFont, color: NSColor) {
        self.init(AttributedString(text), font: font, color: color)
    }

    init(_ text: AttributedString, font: NSFont, color: NSColor) {
        self.text = text
        self.font = font
        self.color = color
    }

    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.cell = ThemePreviewTextCell(textCell: "")
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.allowsEditingTextAttributes = true
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        let value = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let range = NSRange(location: 0, length: value.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        value.addAttributes([.font: font, .paragraphStyle: paragraph], range: range)
        value.enumerateAttribute(.foregroundColor, in: range) { existing, run, _ in
            if existing == nil { value.addAttribute(.foregroundColor, value: color, range: run) }
        }
        label.isSelectable = text.runs.contains { $0.link != nil }
        label.attributedStringValue = value
        label.invalidateIntrinsicContentSize()
        label.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        guard let cell = nsView.cell else { return nil }
        let width = proposal.width ?? ceil(nsView.attributedStringValue.size().width + 4)
        let size = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: min(width, ceil(size.width)), height: ceil(size.height))
    }
}

private final class ThemePreviewTextCell: NSTextFieldCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        // Match Codex's -webkit-font-smoothing: antialiased without changing font weight.
        context?.setShouldSmoothFonts(false)
        // Draw links with the theme's color instead of AppKit's default blue.
        // Restore their attributes immediately afterward to retain link interaction.
        let original = attributedStringValue
        let drawing = NSMutableAttributedString(attributedString: original)
        drawing.removeAttribute(.link, range: NSRange(location: 0, length: drawing.length))
        attributedStringValue = drawing
        super.drawInterior(withFrame: cellFrame, in: controlView)
        attributedStringValue = original
        context?.restoreGState()
    }
}

private struct ThemeEditorPreview: View {
    let draft: ThemeEditorDraft
    private let themeFileURL = AppPaths.make().themeFileURL

    var body: some View {
        let colors = CodexPreviewColors(draft: draft)
        let foreground = Color(nsColor: colors.foreground)
        let background = Color(nsColor: colors.background)
        let added = Color(nsColor: colors.diffAdded)
        let addedBackground = Color(nsColor: colors.diffAddedBackground)
        let removed = Color(nsColor: colors.diffRemoved)
        let removedBackground = Color(nsColor: colors.diffRemovedBackground)
        let uiFontFamily = unquotedFontName(draft.uiFont)
        let codeFontFamily = unquotedFontName(draft.codeFont)
        let contentFontName = unquotedFontName(draft.contentFont ?? "")
        let uiFontName = uiFontFamily.isEmpty ? "" : (draft.uiFontFace?.postscriptName ?? uiFontFamily)
        let codeFontName = codeFontFamily.isEmpty ? "" : (draft.codeFontFace?.postscriptName ?? codeFontFamily)
        let uiFont = NSFont(name: uiFontName, size: 13.8) ?? .systemFont(ofSize: 13.8)
        let chatFontFamily = contentFontName.isEmpty ? uiFontFamily : contentFontName
        // Codex body text uses CSS weight 400; resolve the draft's family at
        // normal weight rather than retaining a previously selected heavy face.
        let chatFont = NSFontManager.shared.font(
            withFamily: chatFontFamily, traits: [], weight: 5, size: 16
        ) ?? .systemFont(ofSize: 16, weight: .regular)
        let nativeCodeFont = NSFont(name: codeFontName, size: 14) ?? .monospacedSystemFont(ofSize: 14, weight: .regular)
        let headingFont = colors.codeHeadingIsBold
            ? NSFontManager.shared.convert(nativeCodeFont, toHaveTrait: .boldFontMask)
            : nativeCodeFont
        let codeCharacterWidth = ("0" as NSString).size(withAttributes: [.font: nativeCodeFont]).width
        let border = Color(nsColor: colors.border)
        let tertiaryText = Color(nsColor: colors.tertiaryText)
        let composerBackground = Color(nsColor: colors.composerBackground)
        let userBubbleBackground = Color(nsColor: colors.userBubbleBackground)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ThemePreviewText("Preview Theme", font: uiFont, color: colors.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(userBubbleBackground, in: UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(nsColor: colors.subtleBorder))
                    .frame(height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 14) {
                ThemePreviewText("Create ten new \(draft.variant.rawValue) themes. Make no mistakes.", font: chatFont, color: colors.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: 322, alignment: .leading)
                    .background(userBubbleBackground, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                VStack(alignment: .leading, spacing: 8) {
                    ThemePreviewText("Worked for 13s", font: uiFont, color: colors.statusText)

                    Rectangle()
                        .fill(border)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }

                ThemePreviewText(completionMessage(linkColor: colors.link), font: chatFont, color: colors.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    ThemePreviewText("\(themeFileURL.deletingLastPathComponent().lastPathComponent)/\(themeFileURL.lastPathComponent)", font: uiFont, color: colors.foreground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(border)
                                .frame(height: 1)
                        }

                    ThemePreviewCodeDiffRow(
                        lineNumber: 362,
                        isAdded: false,
                        tint: removed,
                        rowBackground: removedBackground,
                        gutterBackground: Color(nsColor: colors.diffRemovedGutter),
                        gutterSeparator: background,
                        characterWidth: codeCharacterWidth,
                        codeFont: nativeCodeFont,
                        content: ThemePreviewText(markdownHeading("New \(draft.variant.rawValue.capitalized) Theme", colors: colors),
                            font: headingFont,
                            color: colors.codeHeadingMarker)
                    )
                    ThemePreviewCodeDiffRow(
                        lineNumber: 362,
                        isAdded: true,
                        tint: added,
                        rowBackground: addedBackground,
                        gutterBackground: Color(nsColor: colors.diffAddedGutter),
                        gutterSeparator: background,
                        characterWidth: codeCharacterWidth,
                        codeFont: nativeCodeFont,
                        content: ThemePreviewText(markdownHeading(draft.name, colors: colors),
                            font: headingFont,
                            color: colors.codeHeadingMarker)
                    )
                }
                .id("\(draft.diffAdded)|\(draft.diffRemoved)|\(draft.background)|\(draft.contrast)|\(draft.codeThemeId)|\(draft.variant.rawValue)")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(border, lineWidth: 1)
                }

                HStack(spacing: 9) {
                    ThemePreviewText("Do anything", font: uiFont, color: colors.tertiaryText)
                    Spacer()
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(background)
                        .frame(width: 25, height: 25)
                        .background(foreground, in: Circle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(composerBackground, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(border, lineWidth: 1)
                }
            }
            .padding(14)
        }
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(border, lineWidth: 1)
        }
    }

    private func markdownHeading(_ name: String, colors: CodexPreviewColors) -> AttributedString {
        var heading = AttributedString("### ")
        var title = AttributedString(name)
        title.appKit.foregroundColor = colors.codeHeading
        heading += title
        return heading
    }

    private func completionMessage(linkColor: NSColor) -> AttributedString {
        var message = AttributedString("Done. Added 10 \(draft.variant.rawValue) themes to ")
        var fileLink = AttributedString(themeFileURL.lastPathComponent)
        fileLink.link = themeFileURL
        fileLink.appKit.foregroundColor = linkColor
        message += fileLink
        message += AttributedString(".")
        return message
    }
}

private struct CodexPreviewColors {
    let foreground: NSColor
    let background: NSColor
    let link: NSColor
    let diffAdded: NSColor
    let diffAddedBackground: NSColor
    let diffRemoved: NSColor
    let diffRemovedBackground: NSColor
    let diffAddedGutter: NSColor
    let diffRemovedGutter: NSColor
    let statusText: NSColor
    let tertiaryText: NSColor
    let border: NSColor
    let subtleBorder: NSColor
    let composerBackground: NSColor
    let userBubbleBackground: NSColor
    let codeHeadingMarker: NSColor
    let codeHeading: NSColor
    let codeHeadingIsBold: Bool

    init(draft: ThemeEditorDraft) {
        foreground = NSColor(hexThemeColor: draft.foreground) ?? .labelColor
        background = NSColor(hexThemeColor: draft.background) ?? .windowBackgroundColor
        let accent = NSColor(hexThemeColor: draft.accent) ?? .controlAccentColor
        diffAdded = NSColor(hexThemeColor: draft.diffAdded) ?? .systemGreen
        diffRemoved = NSColor(hexThemeColor: draft.diffRemoved) ?? .systemRed

        let contrast = Self.normalizedContrast(draft.contrast, variant: draft.variant)
        link = accent
        let codePalette = Self.codePalette(for: draft)
        let syntaxSurface = NSColor(hexThemeColor: codePalette.surface) ?? background
        diffAddedBackground = Self.diffBackground(tint: diffAdded, surface: background, variant: draft.variant)
        diffRemovedBackground = Self.diffBackground(tint: diffRemoved, surface: background, variant: draft.variant)
        let gutterTint = draft.variant == .light ? 0.09 : 0.15
        diffAddedGutter = syntaxSurface.cssLabMixed(with: diffAdded, foregroundAmount: gutterTint)
        diffRemovedGutter = syntaxSurface.cssLabMixed(with: diffRemoved, foregroundAmount: gutterTint)
        statusText = foreground.withAlphaComponent(0.60)
        let tertiaryAlpha = Self.clampedAlpha((draft.variant == .light ? 0.45 : 0.42) + contrast * (draft.variant == .light ? 0.10 : 0.13))
        tertiaryText = foreground.withAlphaComponent((tertiaryAlpha * 1000).rounded() / 1000)
        border = foreground.withAlphaComponent(Self.clampedAlpha(0.06 + contrast * 0.04))
        let subtleBorderAlpha = Self.clampedAlpha((draft.variant == .light ? 0.04 : 0.03) + contrast * 0.02)
        subtleBorder = foreground.withAlphaComponent((subtleBorderAlpha * 1000).rounded() / 1000)
        composerBackground = Self.composerBackground(surface: background, ink: foreground, contrast: contrast, variant: draft.variant)
        userBubbleBackground = Self.elevatedSecondaryBackground(surface: background, ink: foreground, contrast: contrast, variant: draft.variant)
        codeHeadingMarker = NSColor(hexThemeColor: codePalette.marker) ?? foreground
        codeHeading = NSColor(hexThemeColor: codePalette.heading) ?? foreground
        codeHeadingIsBold = codePalette.bold
    }

    private static func elevatedSecondaryBackground(surface: NSColor, ink: NSColor, contrast: CGFloat, variant: ThemeVariant) -> NSColor {
        if variant == .light {
            return surface.mixed(with: .white, foregroundAmount: 0.08 + contrast * 0.08).withAlphaComponent(0.96)
        }
        return ink.withAlphaComponent(Self.clampedAlpha(0.02 + contrast * 0.02))
    }

    private static func composerBackground(surface: NSColor, ink: NSColor, contrast: CGFloat, variant: ThemeVariant) -> NSColor {
        if variant == .light {
            return surface.mixed(with: .white, foregroundAmount: 0.09 + contrast * 0.04)
        }
        // Codex uses elevated-primary-opaque for dark composers, not control.
        return surface.mixed(with: ink, foregroundAmount: 0.08 + contrast * 0.08)
    }

    private static func codePalette(for draft: ThemeEditorDraft) -> (surface: String, marker: String, heading: String, bold: Bool) {
        // Codex maps the Rose Pine preset to Dawn in light mode and Moon in dark mode.
        let palettes = [
            "dracula": ("#282a36", "#bd93f9", "#bd93f9", true),
            "github-dark-default": ("#0d1117", "#79c0ff", "#79c0ff", true),
            "github-light-default": ("#ffffff", "#0550ae", "#0550ae", true),
            "rose-pine-dawn": ("#faf4ed", "#575279", "#56949f", true),
            "rose-pine-moon": ("#232136", "#e0def4", "#9ccfd8", true),
            "vesper": ("#101010", "#ffc799", "#ffc799", false)
        ]
        let key = draft.codeThemeId == "rose-pine"
            ? (draft.variant == .light ? "rose-pine-dawn" : "rose-pine-moon")
            : draft.codeThemeId
        return palettes[key] ?? (draft.background, draft.foreground, draft.foreground, false)
    }

    private static func diffBackground(tint: NSColor, surface: NSColor, variant: ThemeVariant) -> NSColor {
        surface.cssLabMixed(with: tint, foregroundAmount: variant == .light ? 0.12 : 0.20)
    }

    private static func normalizedContrast(_ value: String, variant: ThemeVariant) -> CGFloat {
        let defaultContrast = variant == .light ? 45 : 60
        let rawContrast = CGFloat(
            min(
                ThemeEditorDraft.contrastRange.upperBound,
                max(ThemeEditorDraft.contrastRange.lowerBound, ThemeEditorDraft.parsedContrast(value) ?? defaultContrast)
            )
        )
        let baseContrast = CGFloat(defaultContrast)
        let baseNormalized = baseContrast / 100
        let initial = rawContrast / 100 + (rawContrast - baseContrast) / 60 * 0.7
        if rawContrast <= baseContrast {
            return initial
        }
        return baseNormalized + (initial - baseNormalized) * 2
    }

    private static func clampedAlpha(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }
}

private struct ThemePreviewCodeDiffRow: View {
    let lineNumber: Int
    let isAdded: Bool
    let tint: Color
    let rowBackground: Color
    let gutterBackground: Color
    let gutterSeparator: Color
    let characterWidth: CGFloat
    let codeFont: NSFont
    let content: ThemePreviewText

    var body: some View {
        HStack(spacing: 0) {
            ThemePreviewText("\(lineNumber)", font: codeFont, color: NSColor(tint))
                .frame(width: characterWidth * 4, alignment: .trailing)
                .padding(.leading, characterWidth * 2)
                .padding(.trailing, characterWidth)
                .frame(maxHeight: .infinity)
                .background(gutterBackground)
                .overlay(alignment: .leading) {
                    Canvas { context, size in
                        if isAdded {
                            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(tint))
                        } else {
                            let period = size.height / (size.height / 2).rounded()
                            for y in stride(from: CGFloat.zero, to: size.height, by: period) {
                                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: period / 2)), with: .color(tint))
                                context.fill(Path(CGRect(x: 0, y: y + period / 2, width: size.width, height: period / 2)), with: .color(rowBackground))
                            }
                        }
                    }
                    .frame(width: 4)
                    .accessibilityHidden(true)
                }

            Rectangle()
                .fill(gutterSeparator)
                .frame(width: 2)

            ScrollView(.horizontal, showsIndicators: false) {
                content
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, characterWidth)
            }
            .scrollDisabled(true)
        }
        .frame(height: 14 * 1.8)
        .background(rowBackground)
    }
}

private struct ThemeManagerSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)

            TextField("Search themes", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .themeManagerCursor(.pointingHand)
                .themeManagerButtonFeedback()
                .help("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ThemeManagerPressDownModifier: ViewModifier {
    let isEnabled: Bool
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .offset(y: isEnabled && isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.06), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
            )
    }
}

private struct ThemeManagerButtonHoverModifier: ViewModifier {
    let isEnabled: Bool
    let verticalPadding: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEnabled && isHovering ? Color.primary.opacity(0.10) : .clear)
                    .padding(.horizontal, -3)
                    .padding(.vertical, verticalPadding)
            }
            .contentShape(Rectangle())
            .themeManagerCursor(.pointingHand, isEnabled: isEnabled)
            .onHover { hovering in
                isHovering = isEnabled && hovering
            }
            .onChange(of: isEnabled) {
                if !isEnabled {
                    isHovering = false
                }
            }
    }
}

private struct ThemeManagerIconHoverModifier: ViewModifier {
    let isEnabled: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEnabled && isHovering ? Color.primary.opacity(0.10) : .clear)
                    .allowsHitTesting(false)
            }
            .onHover { hovering in
                isHovering = isEnabled && hovering
            }
            .onChange(of: isEnabled) {
                if !isEnabled {
                    isHovering = false
                }
            }
    }
}

private struct ThemeManagerCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var controlIsEnabled
    let cursor: NSCursor
    let isEnabled: Bool
    private var cursorID: ObjectIdentifier {
        ObjectIdentifier(cursor)
    }

    @State private var isHovering = false
    @State private var isPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                syncCursor()
            }
            .onContinuousHover { phase in
                if ThemeManagerDragCursorLock.isActive {
                    NSCursor.closedHand.set()
                    return
                }
                if case .active = phase, isEnabled, controlIsEnabled {
                    cursor.set()
                }
            }
            .onChange(of: controlIsEnabled) {
                syncCursor()
            }
            .onChange(of: cursorID) {
                syncCursor()
            }
            .onChange(of: isEnabled) {
                syncCursor()
            }
            .onDisappear {
                popIfNeeded()
            }
    }

    private func syncCursor() {
        popIfNeeded()
        guard !ThemeManagerDragCursorLock.isActive else {
            NSCursor.closedHand.set()
            return
        }
        guard isEnabled, controlIsEnabled, isHovering else { return }
        cursor.push()
        isPushed = true
    }

    private func popIfNeeded() {
        guard isPushed else { return }
        NSCursor.pop()
        isPushed = false
        if ThemeManagerDragCursorLock.isActive { NSCursor.closedHand.set() }
    }
}

private struct ThemeManagerPanelBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .background(
                colorScheme == .dark
                    ? Color(.sRGB, white: 34 / 255, opacity: 1)
                    : Color(nsColor: .controlBackgroundColor).opacity(0.82),
                in: shape
            )
            .overlay {
                shape.stroke(
                    colorScheme == .dark ? Color.white.opacity(0.07) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
            }
    }
}

private extension View {
    func themeManagerInputSurface(isFocused: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return background(Color.primary.opacity(0.07), in: shape)
            .overlay {
                shape.stroke(
                    isFocused ? Color.accentColor.opacity(0.82) : Color.primary.opacity(0.20),
                    lineWidth: isFocused ? 1.25 : 1
                )
            }
    }

    func themeManagerPanelBackground(cornerRadius: CGFloat) -> some View {
        modifier(ThemeManagerPanelBackgroundModifier(cornerRadius: cornerRadius))
    }

    func themeManagerButtonFeedback(isEnabled: Bool = true) -> some View {
        modifier(ThemeManagerPressDownModifier(isEnabled: isEnabled))
    }

    func themeManagerButtonHover(isEnabled: Bool = true, verticalPadding: CGFloat = -3) -> some View {
        modifier(ThemeManagerButtonHoverModifier(isEnabled: isEnabled, verticalPadding: verticalPadding))
    }

    func themeManagerIconHover(isEnabled: Bool = true) -> some View {
        modifier(ThemeManagerIconHoverModifier(isEnabled: isEnabled))
    }

    func themeManagerCursor(_ cursor: NSCursor, isEnabled: Bool = true) -> some View {
        modifier(ThemeManagerCursorModifier(cursor: cursor, isEnabled: isEnabled))
    }
}

extension NSColor {
    var hexThemeColor: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(
            format: "#%02x%02x%02x",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }

    convenience init?(hexThemeColor value: String) {
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("#")
        guard hex.count == 6, let rgb = Int(hex, radix: 16) else { return nil }

        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: 1
        )
    }

    func mixed(with other: NSColor, foregroundAmount: CGFloat) -> NSColor {
        let amount = min(1, max(0, foregroundAmount))
        let base = usingColorSpace(.sRGB) ?? self
        let foreground = other.usingColorSpace(.sRGB) ?? other
        // Codex rounds each mixed sRGB channel to an 8-bit value.
        return NSColor(
            srgbRed: ((base.redComponent * (1 - amount) + foreground.redComponent * amount) * 255).rounded() / 255,
            green: ((base.greenComponent * (1 - amount) + foreground.greenComponent * amount) * 255).rounded() / 255,
            blue: ((base.blueComponent * (1 - amount) + foreground.blueComponent * amount) * 255).rounded() / 255,
            alpha: base.alphaComponent * (1 - amount) + foreground.alphaComponent * amount
        )
    }

    func cssLabMixed(with other: NSColor, foregroundAmount: CGFloat) -> NSColor {
        let amount = Double(min(1, max(0, foregroundAmount)))
        let baseLab = cssLabComponents()
        let foregroundLab = other.cssLabComponents()
        return NSColor(cssLab: (
            l: baseLab.l * (1 - amount) + foregroundLab.l * amount,
            a: baseLab.a * (1 - amount) + foregroundLab.a * amount,
            b: baseLab.b * (1 - amount) + foregroundLab.b * amount
        ))
    }

    private func cssLabComponents() -> (l: Double, a: Double, b: Double) {
        let color = usingColorSpace(.sRGB) ?? self
        let red = Self.srgbToLinear(Double(color.redComponent))
        let green = Self.srgbToLinear(Double(color.greenComponent))
        let blue = Self.srgbToLinear(Double(color.blueComponent))

        let xD65 = 0.4124564 * red + 0.3575761 * green + 0.1804375 * blue
        let yD65 = 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue
        let zD65 = 0.0193339 * red + 0.1191920 * green + 0.9503041 * blue
        let xyz = Self.adaptD65ToD50(x: xD65, y: yD65, z: zD65)

        let xr = xyz.x / 0.96422
        let yr = xyz.y
        let zr = xyz.z / 0.82521
        let fx = Self.labPivot(xr)
        let fy = Self.labPivot(yr)
        let fz = Self.labPivot(zr)
        return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    private convenience init(cssLab lab: (l: Double, a: Double, b: Double)) {
        let fy = (lab.l + 16) / 116
        let fx = lab.a / 500 + fy
        let fz = fy - lab.b / 200
        let xD50 = 0.96422 * Self.labPivotInverse(fx)
        let yD50 = Self.labPivotInverse(fy)
        let zD50 = 0.82521 * Self.labPivotInverse(fz)
        let xyz = Self.adaptD50ToD65(x: xD50, y: yD50, z: zD50)

        let red = 3.2404542 * xyz.x - 1.5371385 * xyz.y - 0.4985314 * xyz.z
        let green = -0.9692660 * xyz.x + 1.8760108 * xyz.y + 0.0415560 * xyz.z
        let blue = 0.0556434 * xyz.x - 0.2040259 * xyz.y + 1.0572252 * xyz.z
        self.init(
            srgbRed: CGFloat(Self.linearToSrgb(red)),
            green: CGFloat(Self.linearToSrgb(green)),
            blue: CGFloat(Self.linearToSrgb(blue)),
            alpha: 1
        )
    }

    private static func adaptD65ToD50(x: Double, y: Double, z: Double) -> (x: Double, y: Double, z: Double) {
        (
            x: 1.0479298208405488 * x + 0.022946793341019088 * y - 0.05019222954313557 * z,
            y: 0.029627815688159344 * x + 0.990434484573249 * y - 0.01707382502938514 * z,
            z: -0.009243058152591178 * x + 0.015055144896577895 * y + 0.7518742899580008 * z
        )
    }

    private static func adaptD50ToD65(x: Double, y: Double, z: Double) -> (x: Double, y: Double, z: Double) {
        (
            x: 0.955473421488075 * x - 0.02309845494876471 * y + 0.06325924320057072 * z,
            y: -0.0283697093338637 * x + 1.0099953980813041 * y + 0.021041441191917323 * z,
            z: 0.012314014864481998 * x - 0.020507649298898964 * y + 1.330365926242124 * z
        )
    }

    private static func labPivot(_ value: Double) -> Double {
        value > 216.0 / 24389.0 ? pow(value, 1.0 / 3.0) : (841.0 / 108.0) * value + 4.0 / 29.0
    }

    private static func labPivotInverse(_ value: Double) -> Double {
        let cubed = value * value * value
        return cubed > 216.0 / 24389.0 ? cubed : (108.0 / 841.0) * (value - 4.0 / 29.0)
    }

    private static func srgbToLinear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func linearToSrgb(_ value: Double) -> Double {
        let clamped = min(1, max(0, value))
        return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
    }

}

private struct HotkeyControlHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isHovered ? 0.09 : 0))
                    .allowsHitTesting(false)
            }
            .onHover { isHovered = $0 }
    }
}

private struct HotkeyRecorderRow: View {
    let title: String
    let symbolName: String
    @Binding var shortcut: ThemeHotkeyShortcut?
    let onRecordingChanged: (Bool) -> Void

    var body: some View {
        HStack {
            Image(systemName: symbolName)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            HStack(spacing: 8) {
                HotkeyRecorder(shortcut: $shortcut, onRecordingChanged: onRecordingChanged)
                    .themeManagerCursor(.pointingHand)
                    .frame(width: 170, height: 24)
                    .modifier(HotkeyControlHover())
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.bordered)
                .themeManagerCursor(.pointingHand)
                .frame(width: 32, height: 24)
                .modifier(HotkeyControlHover())
                .accessibilityLabel("Clear \(title) shortcut")
                .help("Clear shortcut")
            }
        }
    }
}

private struct HotkeyRecorder: NSViewRepresentable {
    @Binding var shortcut: ThemeHotkeyShortcut?
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderButton {
        let button = HotkeyRecorderButton()
        button.onShortcutChange = { shortcut in
            self.shortcut = shortcut
        }
        button.onRecordingChanged = onRecordingChanged
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ nsView: HotkeyRecorderButton, context: Context) {
        nsView.onShortcutChange = { shortcut in
            self.shortcut = shortcut
        }
        nsView.onRecordingChanged = onRecordingChanged
        nsView.shortcut = shortcut
    }
}

private final class HotkeyRecorderButton: NSButton {
    private var outsideClickMonitor: Any?
    var onRecordingChanged: ((Bool) -> Void)?
    var onShortcutChange: ((ThemeHotkeyShortcut?) -> Void)?
    var shortcut: ThemeHotkeyShortcut? {
        didSet { updateTitle() }
    }

    private var isRecording = false {
        didSet {
            if oldValue != isRecording {
                onRecordingChanged?(isRecording)
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResignedKey(_:)),
            name: NSWindow.didResignKeyNotification, object: nil
        )
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    @objc private func toggleRecording() {
        if !isRecording {
            guard window?.makeFirstResponder(self) == true else { return }
        }
        isRecording.toggle()
        updateTitle()
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        guard let resignedWindow = notification.object as? NSWindow,
              resignedWindow === window else { return }
        isRecording = false
        updateTitle()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if newWindow == nil {
            isRecording = false
        } else {
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let window = self.window,
                      event.window === window,
                      window.firstResponder === self else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.contains(point) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    isolated deinit {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        record(event)
        return true
    }

    private func updateTitle() {
        if isRecording {
            title = "Type shortcut"
        } else {
            title = shortcut?.displayString ?? "Record Shortcut"
        }
    }

    private func record(_ event: NSEvent) {
        let modifiers = ThemeHotkeyModifiers(eventModifiers: event.modifierFlags)
        let keyCode = UInt32(event.keyCode)

        if keyCode == UInt32(kVK_Escape) {
            isRecording = false
            updateTitle()
            return
        }

        if keyCode == UInt32(kVK_Delete) && modifiers.isEmpty {
            isRecording = false
            shortcut = nil
            onShortcutChange?(nil)
            updateTitle()
            return
        }

        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        let recorded = ThemeHotkeyShortcut(
            keyCode: keyCode,
            key: ThemeHotkeyShortcut.displayKey(for: keyCode, characters: event.charactersIgnoringModifiers),
            modifiers: modifiers
        )
        isRecording = false
        shortcut = recorded
        onShortcutChange?(recorded)
        updateTitle()
    }
}
