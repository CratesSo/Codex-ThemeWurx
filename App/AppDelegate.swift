import AppKit
import Carbon
import CodexThemeBarCore
import Combine
import Foundation
import SwiftUI

@MainActor
class ThemeBarWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        let wasVisible = isVisible
        super.close()
        guard wasVisible, !isVisible else { return }
        contentView = nil
        onClose?()
        onClose = nil
    }
}

@MainActor
final class ThemeManagerWindow: ThemeBarWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, shouldDismissNameFocus(for: event) {
            NotificationCenter.default.post(
                name: .themeManagerOutsideTextInputClick,
                object: self
            )
        }
        super.sendEvent(event)
    }

    private func shouldDismissNameFocus(for event: NSEvent) -> Bool {
        guard let responder = firstResponder as? NSView else { return false }
        let focusView = textFieldAncestor(of: responder) ?? (responder as? NSTextView)
        guard let focusView else { return false }
        let focusFrame = focusView.convert(focusView.bounds, to: nil)
        return !focusFrame.insetBy(dx: -2, dy: -2).contains(event.locationInWindow)
    }

    private func textFieldAncestor(of view: NSView) -> NSTextField? {
        var current: NSView? = view
        while let candidate = current {
            if let textField = candidate as? NSTextField {
                return textField
            }
            current = candidate.superview
        }
        return nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: ThemeBarModel
    let hotkeyController: ThemeHotkeyController

    private var menuController: StatusMenuController?
    private var keyboardShortcutsWindowController: NSWindowController?
    private var themeManagerWindowController: NSWindowController?
    private var appSettingsWindowController: NSWindowController?

    override init() {
        UserDefaults.standard.register(defaults: [
            "NSInitialToolTipDelay": 250
        ])
        Self.migrateLegacyPreferences()
        let model = ThemeBarModel(paths: AppPaths.make())
        self.model = model
        self.hotkeyController = ThemeHotkeyController(model: model)
        super.init()
    }

    private static func migrateLegacyPreferences() {
        let defaults = UserDefaults.standard
        guard let legacyDomain = defaults.persistentDomain(
            forName: "local.codex.meta.codexthemebar.app"
        ) else {
            return
        }

        let keys = [
            ThemeHotkeyPreferencesStore.storageKey,
            "ThemeManagerSkipDeleteConfirmations"
        ]
        for key in keys where defaults.object(forKey: key) == nil {
            if let legacyValue = legacyDomain[key] {
                defaults.set(legacyValue, forKey: key)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menuController = StatusMenuController(
            model: model,
            hotkeyController: hotkeyController,
            openKeyboardShortcuts: { [weak self] in
                self?.showKeyboardShortcutsWindow()
            },
            openManageThemes: { [weak self] in
                self?.showThemeManagerWindow()
            },
            openSettings: { [weak self] in
                self?.showSettingsWindow()
            }
        )
        self.menuController = menuController
        model.start()
        hotkeyController.start()
    }

    func showKeyboardShortcutsWindow() {
        let controller = keyboardShortcutsWindowController ?? makeKeyboardShortcutsWindowController()
        keyboardShortcutsWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showThemeManagerWindow() {
        model.beginThemeManagementSession()
        let controller = themeManagerWindowController ?? makeThemeManagerWindowController()
        themeManagerWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettingsWindow() {
        let controller = appSettingsWindowController ?? makeAppSettingsWindowController()
        appSettingsWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeAppSettingsWindowController() -> NSWindowController {
        let hostingView = NSHostingView(rootView: AppSettingsView(model: model))
        hostingView.sizingOptions = []
        let contentSize = NSSize(width: 680, height: 520)
        let window = ThemeBarWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.setContentSize(contentSize)
        window.title = "ThemeWurx Settings"
        window.isReleasedWhenClosed = false
        window.onClose = { [weak self] in self?.appSettingsWindowController = nil }
        window.center()
        return NSWindowController(window: window)
    }

    private func makeKeyboardShortcutsWindowController() -> NSWindowController {
        let rootView = ThemeBarSettingsView(hotkeyController: hotkeyController)
        let hostingView = NSHostingView(rootView: rootView)
        let contentHeight = hostingView.fittingSize.height
        let window = ThemeBarWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: contentHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Keyboard Shortcuts"
        window.isReleasedWhenClosed = false
        window.onClose = { [weak self] in self?.keyboardShortcutsWindowController = nil }
        window.setContentSize(NSSize(width: 520, height: contentHeight))
        window.center()
        return NSWindowController(window: window)
    }

    private func makeThemeManagerWindowController() -> NSWindowController {
        let rootView = ThemeManagerView(model: model)
        let window = ThemeManagerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: rootView)
        window.title = ""
        window.titleVisibility = .hidden
        window.isOpaque = true
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1)
                : .windowBackgroundColor
        }
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.onClose = { [weak self] in self?.themeManagerWindowController = nil }
        window.minSize = NSSize(width: 780, height: 720)
        window.setContentSize(NSSize(width: 900, height: 760))
        window.center()
        return NSWindowController(window: window)
    }
}

@MainActor
final class ThemeHotkeyController: ObservableObject {
    private static let invertHotkeyMigrationKey = "themeHotkeyPreferences.invertCurrent.v1"
    @Published private(set) var preferences: ThemeHotkeyPreferences
    @Published private(set) var statusMessage: String?
    @Published private(set) var fieldErrors: [ThemeHotkeyAction: String] = [:]

    private let model: ThemeBarModel
    private let store: ThemeHotkeyPreferencesStore
    private let hotKeyCenter: GlobalHotKeyCenter
    private var registrations: [ThemeHotkeyAction: RegisteredHotKey] = [:]
    private var isRecordingShortcut = false

    init(
        model: ThemeBarModel,
        store: ThemeHotkeyPreferencesStore = .init(),
        hotKeyCenter: GlobalHotKeyCenter = .shared
    ) {
        self.model = model
        self.store = store
        self.hotKeyCenter = hotKeyCenter
        self.preferences = (try? store.load()) ?? .defaults
    }

    var hotkeysEnabled: Bool {
        preferences.hotkeysEnabled
    }

    func start() {
        var initial = (try? store.load()) ?? .defaults
        if !UserDefaults.standard.bool(forKey: Self.invertHotkeyMigrationKey) {
            if initial.bindings.invertCurrent == nil {
                initial.bindings.invertCurrent = ThemeHotkeyAction.invertCurrent.defaultShortcut
                try? store.save(initial)
            }
            UserDefaults.standard.set(true, forKey: Self.invertHotkeyMigrationKey)
        }
        _ = applyPreferences(initial, bootstrap: true)
    }

    func setRecordingShortcut(_ isRecording: Bool) {
        guard isRecordingShortcut != isRecording else { return }
        isRecordingShortcut = isRecording
        if isRecording {
            unregisterAll()
        } else {
            _ = restore(preferences)
        }
    }

    func binding(for action: ThemeHotkeyAction) -> Binding<ThemeHotkeyShortcut?> {
        Binding(
            get: { self.preferences.bindings[action] },
            set: { self.updateShortcut($0, for: action) }
        )
    }

    func setHotkeysEnabled(_ isEnabled: Bool) {
        var candidate = preferences
        candidate.hotkeysEnabled = isEnabled
        _ = applyPreferences(candidate)
    }

    private func updateShortcut(_ shortcut: ThemeHotkeyShortcut?, for action: ThemeHotkeyAction) {
        fieldErrors[action] = nil
        statusMessage = nil

        if let duplicateOwner = preferences.bindings.duplicateOwner(for: shortcut, excluding: action) {
            fieldErrors[action] = "\(duplicateOwner.title) already uses that shortcut."
            statusMessage = "Shortcut update rejected."
            return
        }

        var candidate = preferences
        candidate.bindings[action] = shortcut
        _ = applyPreferences(candidate, sourceAction: action)
    }

    @discardableResult
    private func applyPreferences(
        _ candidate: ThemeHotkeyPreferences,
        sourceAction: ThemeHotkeyAction? = nil,
        bootstrap: Bool = false
    ) -> Bool {
        let previousPreferences = preferences
        let previousErrors = fieldErrors
        unregisterAll()

        do {
            let result = try registerAll(for: candidate, requiredAction: sourceAction)
            preferences = result.preferences
            registrations = result.registrations
            fieldErrors = result.fieldErrors
            try store.save(result.preferences)
            statusMessage = statusMessage(for: result)
            if bootstrap && !result.preferences.hotkeysEnabled {
                statusMessage = "Global hotkeys disabled."
            }
            return true
        } catch {
            if bootstrap {
                preferences = ThemeHotkeyPreferences(hotkeysEnabled: false, bindings: ThemeHotkeyBindings())
                fieldErrors = [:]
                try? store.save(preferences)
                statusMessage = "Default hotkeys disabled: \(error.localizedDescription)"
                registrations = [:]
                return false
            }

            if let sourceAction {
                fieldErrors[sourceAction] = error.localizedDescription
            }
            statusMessage = "Shortcut update rejected: \(error.localizedDescription)"
            if !restore(previousPreferences) {
                fieldErrors = previousErrors
            }
            return false
        }
    }

    @discardableResult
    private func restore(_ preferences: ThemeHotkeyPreferences) -> Bool {
        do {
            let result = try registerAll(for: preferences)
            self.preferences = result.preferences
            registrations = result.registrations
            fieldErrors = result.fieldErrors
            return true
        } catch {
            registrations = [:]
            statusMessage = "Hotkey restore failed: \(error.localizedDescription)"
            return false
        }
    }

    private func registerAll(
        for preferences: ThemeHotkeyPreferences,
        requiredAction: ThemeHotkeyAction? = nil
    ) throws -> (preferences: ThemeHotkeyPreferences, registrations: [ThemeHotkeyAction: RegisteredHotKey], fieldErrors: [ThemeHotkeyAction: String]) {
        guard preferences.hotkeysEnabled, !isRecordingShortcut else { return (preferences, [:], [:]) }
        var sanitized = preferences
        var newRegistrations: [ThemeHotkeyAction: RegisteredHotKey] = [:]
        var newFieldErrors: [ThemeHotkeyAction: String] = [:]
        do {
            for action in ThemeHotkeyAction.allCases {
                guard let shortcut = sanitized.bindings[action] else { continue }
                do {
                    newRegistrations[action] = try hotKeyCenter.register(shortcut: shortcut) { [weak self] in
                        Task { @MainActor in
                            guard let self, !self.isRecordingShortcut else { return }
                            self.model.applyHotkey(action, modifiers: shortcut.modifiers)
                        }
                    }
                } catch {
                    guard action != requiredAction else { throw error }
                    sanitized.bindings[action] = nil
                    newFieldErrors[action] = error.localizedDescription
                }
            }
            return (sanitized, newRegistrations, newFieldErrors)
        } catch {
            for registration in newRegistrations.values {
                hotKeyCenter.unregister(registration)
            }
            throw error
        }
    }

    private func unregisterAll() {
        for registration in registrations.values {
            hotKeyCenter.unregister(registration)
        }
        registrations.removeAll()
    }

    private func statusMessage(
        for result: (preferences: ThemeHotkeyPreferences, registrations: [ThemeHotkeyAction: RegisteredHotKey], fieldErrors: [ThemeHotkeyAction: String])
    ) -> String? {
        guard result.preferences.hotkeysEnabled else { return "Global hotkeys disabled." }
        guard !result.fieldErrors.isEmpty else { return nil }
        let dropped = ThemeHotkeyAction.allCases.filter { result.fieldErrors[$0] != nil }.map(\.title).joined(separator: ", ")
        return "Dropped unavailable shortcuts: \(dropped)."
    }
}

final class RegisteredHotKey {
    fileprivate let identifier: UInt32
    fileprivate let reference: EventHotKeyRef

    fileprivate init(identifier: UInt32, reference: EventHotKeyRef) {
        self.identifier = identifier
        self.reference = reference
    }
}

@MainActor
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private let signature = OSType(0x54484252)
    private var nextIdentifier: UInt32 = 1
    private var handlerRef: EventHandlerRef?
    private var handlers: [UInt32: () -> Void] = [:]

    private init() {
        installHandlerIfNeeded()
    }

    func register(shortcut: ThemeHotkeyShortcut, handler: @escaping () -> Void) throws -> RegisteredHotKey {
        installHandlerIfNeeded()

        let identifier = nextIdentifier
        nextIdentifier += 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            throw GlobalHotKeyError.registrationFailed(shortcut.displayString)
        }

        handlers[identifier] = handler
        return RegisteredHotKey(identifier: identifier, reference: hotKeyRef)
    }

    func unregister(_ registration: RegisteredHotKey) {
        UnregisterEventHotKey(registration.reference)
        handlers.removeValue(forKey: registration.identifier)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                return center.handle(event: event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    private func handle(event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        handlers[hotKeyID.id]?()
        return noErr
    }
}

enum GlobalHotKeyError: LocalizedError {
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let shortcut):
            return "\(shortcut) could not be registered."
        }
    }
}
