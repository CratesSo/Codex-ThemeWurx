import AppKit
import CodexThemeBarCore
import Metal
import QuartzCore
import SwiftUI

enum MenuEffect: String {
    static let storageKey = "MenuEffect"
    static let auroraPairEnabledKey = "MenuEffect.aurora.pairEnabled"
    static let auroraFirstColorKey = "MenuEffect.aurora.firstColor"
    static let auroraSecondColorKey = "MenuEffect.aurora.secondColor"

    case off
    case rainbow
    case snow
    case aurora
    case rain

    var hueStorageKey: String { "MenuEffect.\(rawValue).hue" }
    var defaultHueStorageKey: String { "MenuEffect.\(rawValue).defaultHue" }
    var speedStorageKey: String { "MenuEffect.\(rawValue).speed" }
    var brightnessStorageKey: String { "MenuEffect.\(rawValue).brightness" }

    var brightnessMultiplier: Double {
        pow(2, UserDefaults.standard.double(forKey: brightnessStorageKey))
    }

    var speedMultiplier: Double {
        pow(2, UserDefaults.standard.double(forKey: speedStorageKey))
    }

    var customHue: Double? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: defaultHueStorageKey) as? Bool == false else { return nil }
        return defaults.double(forKey: hueStorageKey)
    }

    static var current: MenuEffect {
        MenuEffect(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .off
    }
}

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: ThemeBarModel
    private let hotkeyController: ThemeHotkeyController
    private let openKeyboardShortcuts: () -> Void
    private let openManageThemes: () -> Void
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private var currentMenu: NSMenu?
    private var rowViewsByID: [String: [MenuThemeRowView]] = [:]
    private var folderMenuItems: [(item: NSMenuItem, rowIDs: Set<String>)] = []
    private var favoriteRowViews: [MenuThemeRowView] = []
    private var favoriteIDs: Set<String> = []
    private var favoriteMenu: NSMenu?
    private var pendingFavoriteRows: [ManagedThemeRow]?
    private var openMenus: Set<ObjectIdentifier> = []
    private var isMenuTracking = false
    private var pendingThemeNotice: (name: String, variant: ThemeVariant, theme: ChromeTheme?)?
    private var themeNoticePopover: NSPopover?
    private var themeNoticeDismissTask: Task<Void, Never>?
    private var menuEffectStartTimer: Timer?
    private var menuEffectOverlay: MenuEffectOverlay?
    private weak var toggleMenuItem: NSMenuItem?

    init(
        model: ThemeBarModel,
        hotkeyController: ThemeHotkeyController,
        openKeyboardShortcuts: @escaping () -> Void,
        openManageThemes: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.model = model
        self.hotkeyController = hotkeyController
        self.openKeyboardShortcuts = openKeyboardShortcuts
        self.openManageThemes = openManageThemes
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.autosaveName = "CodexThemeBar.statusItem.v2"
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Codex ThemeWurx")
            button.image?.isTemplate = true
            button.toolTip = "Codex ThemeWurx"
        }
        statusItem.isVisible = true

        model.onChange = { [weak self] in
            self?.refreshMenu()
        }
        model.onHotkeyThemeSelected = { [weak self] entry in
            self?.pendingThemeNotice = nil
            self?.showThemeNotice(name: entry.name, variant: entry.variant, theme: entry.theme)
        }
        model.onThemeApplied = { [weak self] name, variant in
            self?.presentThemeNotice(name: name, variant: variant)
        }
        model.onAppearanceToggleUnavailable = { reason in
            let alert = NSAlert()
            alert.messageText = "Toggle Last Light/Dark unavailable"
            alert.informativeText = reason
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        stopMenuEffect()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        rowViewsByID = [:]
        folderMenuItems = []
        favoriteRowViews = []
        favoriteMenu = nil
        pendingFavoriteRows = nil
        openMenus.removeAll()

        let favorites = model.lightRows.filter(\.entry.isFavorite) + model.darkRows.filter(\.entry.isFavorite)
        favoriteIDs = Set(favorites.map(\.id))
        if !favorites.isEmpty {
            let favoritesItem = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
            favoritesItem.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "Favorites")
            let submenu = favoritesMenu(for: favorites)
            favoriteMenu = submenu
            menu.setSubmenu(submenu, for: favoritesItem)
            menu.addItem(favoritesItem)
        }

        let lightItem = NSMenuItem(title: "Light Themes", action: nil, keyEquivalent: "")
        lightItem.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Light Themes")
        menu.setSubmenu(themeMenu(for: .light), for: lightItem)
        menu.addItem(lightItem)

        let darkItem = NSMenuItem(title: "Dark Themes", action: nil, keyEquivalent: "")
        darkItem.image = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: "Dark Themes")
        menu.setSubmenu(themeMenu(for: .dark), for: darkItem)
        menu.addItem(darkItem)

        if !model.parseIssues.isEmpty {
            menu.addItem(.separator())
            addDisabled("Parse issues", to: menu)
            for issue in model.parseIssues.prefix(8) {
                addDisabled("L\(issue.line): \(issue.message)", to: menu)
            }
        }

        menu.addItem(.separator())
        let toggle = NSMenuItem(title: "Toggle Last Light/Dark", action: #selector(toggleAppearance), keyEquivalent: "")
        toggle.target = self
        toggleMenuItem = toggle
        updateToggleShortcut()
        menu.addItem(toggle)
        menu.addItem(.separator())
        let manageThemes = NSMenuItem(title: "Theme Manager…", action: #selector(openManageThemesMenuItem), keyEquivalent: "")
        manageThemes.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Theme Manager")
        manageThemes.target = self
        menu.addItem(manageThemes)

        let keyboardShortcuts = NSMenuItem(title: "Keyboard Shortcuts…", action: #selector(openKeyboardShortcutsMenuItem), keyEquivalent: "")
        keyboardShortcuts.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Shortcuts")
        keyboardShortcuts.target = self
        menu.addItem(keyboardShortcuts)

        let moreItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        moreItem.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        let moreMenu = NSMenu()
        moreMenu.delegate = self
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        moreMenu.addItem(quit)
        moreMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettingsMenuItem), keyEquivalent: "")
        settings.target = self
        moreMenu.addItem(settings)
        menu.setSubmenu(moreMenu, for: moreItem)
        menu.addItem(moreItem)

        currentMenu = menu
        statusItem.menu = menu
    }

    private func refreshMenu() {
        guard currentMenu != nil, isMenuTracking else {
            rebuildMenu()
            return
        }

        let favorites = model.lightRows.filter(\.entry.isFavorite) + model.darkRows.filter(\.entry.isFavorite)
        if Set(favorites.map(\.id)) != favoriteIDs {
            if isMenuTracking, !isMenuOpen(favoriteMenu) {
                favoriteIDs = Set(favorites.map(\.id))
                pendingFavoriteRows = favorites
            } else {
                refreshFavoritesMenu(for: favorites)
            }
        }

        let rows = Dictionary(uniqueKeysWithValues: (model.lightRows + model.darkRows).map { ($0.id, $0) })
        for (id, rowViews) in rowViewsByID {
            guard let row = rows[id] else { continue }
            let title = model.displayName(for: row)
            let isActive = model.isActiveTheme(row)
            rowViews.forEach { $0.update(title: title, isActive: isActive) }
        }
        for (item, rowIDs) in folderMenuItems {
            let isActive = rowIDs.contains { id in
                rows[id].map { model.isActiveTheme($0) } ?? false
            }
            item.attributedTitle = menuRowTitle(title: item.title, hovered: false, isActive: isActive)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        openMenus.insert(ObjectIdentifier(menu))
        isMenuTracking = true
        if menu === currentMenu {
            updateToggleShortcut()
            startMenuEffect()
        }
    }

    private func startMenuEffect() {
        stopMenuEffect()
        guard MenuEffect.current != .off, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(showMenuEffect), userInfo: nil, repeats: false)
        menuEffectStartTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func showMenuEffect() {
        guard let menu = currentMenu, openMenus.contains(ObjectIdentifier(menu)) else { return }
        let effect = MenuEffect.current
        guard effect != .off else { return }
        let menuWindows = NSApp.windows.filter { $0.isVisible && $0.level == .popUpMenu }
        guard let window = menuWindows.min(by: {
            abs($0.frame.width - menu.size.width) + abs($0.frame.height - menu.size.height)
                < abs($1.frame.width - menu.size.width) + abs($1.frame.height - menu.size.height)
        }) else { return }
        menuEffectOverlay = MenuEffectOverlay(menuWindow: window, effect: effect)
    }

    private func stopMenuEffect() {
        menuEffectStartTimer?.invalidate()
        menuEffectStartTimer = nil
        menuEffectOverlay?.close()
        menuEffectOverlay = nil
    }

    private func updateToggleShortcut() {
        guard let toggleMenuItem else { return }
        guard let shortcut = hotkeyController.preferences.bindings.toggleAppearance else {
            toggleMenuItem.keyEquivalent = ""
            return
        }
        let key: String
        switch shortcut.key {
        case "←": key = "\u{F702}"
        case "→": key = "\u{F703}"
        case "↑": key = "\u{F700}"
        case "↓": key = "\u{F701}"
        case "↩": key = "\r"
        case "Space": key = " "
        case "Tab": key = "\t"
        case "⌫": key = "\u{7f}"
        case "⌦": key = "\u{F728}"
        case "Esc": key = "\u{1b}"
        default: key = shortcut.key.lowercased()
        }
        toggleMenuItem.keyEquivalent = key
        var modifiers: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        toggleMenuItem.keyEquivalentModifierMask = modifiers
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === currentMenu {
            stopMenuEffect()
        }
        openMenus.remove(ObjectIdentifier(menu))
        isMenuTracking = !openMenus.isEmpty
        guard !isMenuTracking else { return }
        if let pendingFavoriteRows {
            self.pendingFavoriteRows = nil
            refreshFavoritesMenu(for: pendingFavoriteRows)
        }
        if let pendingThemeNotice {
            self.pendingThemeNotice = nil
            DispatchQueue.main.async { [weak self] in
                self?.showThemeNotice(name: pendingThemeNotice.name, variant: pendingThemeNotice.variant, theme: pendingThemeNotice.theme)
            }
        }
    }

    private func presentThemeNotice(name: String, variant: ThemeVariant) {
        let theme = variant == .light ? model.snapshot.lightChromeTheme : model.snapshot.darkChromeTheme
        if isMenuTracking {
            pendingThemeNotice = (name, variant, theme)
        } else {
            showThemeNotice(name: name, variant: variant, theme: theme)
        }
    }

    private func showThemeNotice(name: String, variant: ThemeVariant, theme: ChromeTheme?) {
        guard let button = statusItem.button else { return }

        let popover: NSPopover
        if let existingPopover = themeNoticePopover, existingPopover.isShown {
            existingPopover.contentViewController = NSHostingController(
                rootView: ThemeNoticeBubble(name: name, variant: variant, theme: theme)
            )
            popover = existingPopover
        } else {
            let newPopover = NSPopover()
            newPopover.behavior = .transient
            newPopover.animates = false
            newPopover.contentSize = NSSize(width: 300, height: 52)
            newPopover.contentViewController = NSHostingController(
                rootView: ThemeNoticeBubble(name: name, variant: variant, theme: theme)
            )
            themeNoticePopover = newPopover
            newPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover = newPopover
        }

        themeNoticeDismissTask?.cancel()
        themeNoticeDismissTask = Task { [weak self, weak popover] in
            do {
                repeat {
                    try await Task.sleep(for: .milliseconds(1600))
                } while self?.model.hasPendingHotkeySelection == true
            } catch {
                return
            }
            guard
                !Task.isCancelled,
                let self,
                let popover,
                self.themeNoticePopover === popover
            else {
                return
            }
            popover.close()
            self.themeNoticePopover = nil
            self.themeNoticeDismissTask = nil
        }
    }

    private func themeMenu(for target: ApplyTarget) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let variant: ThemeVariant = target == .light ? .light : .dark
        let folders = model.catalog.folders(for: variant)
        let rows = target == .light ? model.lightRows : model.darkRows

        if rows.isEmpty {
            let empty = NSMenuItem(title: "No \(target.rawValue) themes loaded", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return menu
        }

        // Keep categorized themes above the implicit uncategorized section.
        let categorizedFolders = folders.filter { !$0.isImplicitUnfiled && !$0.entries.isEmpty }
        let uncategorizedFolders = folders.filter { $0.isImplicitUnfiled && !$0.entries.isEmpty }
        for folder in categorizedFolders {
            let folderRows = folderRows(rows, for: folder)
            let item = NSMenuItem(title: folder.name, action: nil, keyEquivalent: "")
            item.attributedTitle = menuRowTitle(
                title: folder.name,
                hovered: false,
                isActive: folderRows.contains { model.isActiveTheme($0) }
            )
            folderMenuItems.append((item, Set(folderRows.map(\.id))))
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: folder.name)
            item.image?.isTemplate = true
            let folderMenu = NSMenu()
            folderMenu.delegate = self
            addThemeRows(
                folderRows,
                to: folderMenu,
                target: target,
                includesFavoriteToggle: true
            )
            menu.setSubmenu(folderMenu, for: item)
            menu.addItem(item)
        }

        if !categorizedFolders.isEmpty && !uncategorizedFolders.isEmpty {
            menu.addItem(.separator())
        }

        for folder in uncategorizedFolders {
            let folderRows = folderRows(rows, for: folder)
            addThemeRows(
                folderRows,
                to: menu,
                target: target,
                includesFavoriteToggle: true
            )
        }
        return menu
    }

    private func folderRows(_ rows: [ManagedThemeRow], for folder: ThemeFolder) -> [ManagedThemeRow] {
        rows.filter { row in
            folder.entries.contains(where: { $0.id == row.entry.id })
        }
    }

    private func favoritesMenu(for rows: [ManagedThemeRow]) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        for variant in ThemeVariant.allCases {
            let variantRows = rows.filter { $0.variant == variant }
            guard !variantRows.isEmpty else { continue }

            if menu.numberOfItems > 0 {
                menu.addItem(.separator())
            }
            menu.addItem(favoritesSectionHeader(for: variant))

            let target: ApplyTarget = variant == .light ? .light : .dark
            addThemeRows(
                variantRows,
                to: menu,
                target: target,
                includesFavoriteToggle: true,
                tracksAsFavoritesMenu: true
            )
        }
        return menu
    }

    private func refreshFavoritesMenu(for rows: [ManagedThemeRow]) {
        guard let currentMenu else { return }

        for id in Array(rowViewsByID.keys) {
            guard let views = rowViewsByID[id] else { continue }
            rowViewsByID[id] = views.filter { view in
                !favoriteRowViews.contains { $0 === view }
            }
        }
        favoriteRowViews = []
        favoriteIDs = Set(rows.map(\.id))

        if let favoritesItem = currentMenu.items.first(where: { $0.title == "Favorites" }) {
            if rows.isEmpty {
                currentMenu.removeItem(favoritesItem)
                favoriteMenu = nil
            } else {
                let submenu = favoritesMenu(for: rows)
                favoriteMenu = submenu
                currentMenu.setSubmenu(submenu, for: favoritesItem)
            }
        } else if !rows.isEmpty {
            let favoritesItem = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
            favoritesItem.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "Favorites")
            let submenu = favoritesMenu(for: rows)
            favoriteMenu = submenu
            currentMenu.setSubmenu(submenu, for: favoritesItem)
            currentMenu.insertItem(favoritesItem, at: 0)
        }
    }

    private func isMenuOpen(_ menu: NSMenu?) -> Bool {
        guard let menu else { return false }
        return openMenus.contains(ObjectIdentifier(menu))
    }

    private func addThemeRows(
        _ rows: [ManagedThemeRow],
        to menu: NSMenu,
        target: ApplyTarget,
        includesFavoriteToggle: Bool,
        tracksAsFavoritesMenu: Bool = false
    ) {
        let rowViews = rows.map { row in
            MenuThemeRowView(
                title: model.displayName(for: row),
                theme: row.entry.theme,
                isActive: model.isActiveTheme(row),
                isFavorite: includesFavoriteToggle ? row.entry.isFavorite : nil,
                apply: { [weak self] in
                    self?.model.applyTheme(entry: row.entry, to: target)
                },
                toggleFavorite: includesFavoriteToggle ? { [weak self] in
                    self?.model.toggleFavorite(row)
                } : nil
            )
        }
        for (row, rowView) in zip(rows, rowViews) {
            rowViewsByID[row.id, default: []].append(rowView)
            if tracksAsFavoritesMenu {
                favoriteRowViews.append(rowView)
            }
        }

        for rowView in rowViews {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.view = rowView
            menu.addItem(item)
        }
    }

    private func favoritesSectionHeader(for variant: ThemeVariant) -> NSMenuItem {
        let item = NSMenuItem(title: variant.rawValue.capitalized, action: nil, keyEquivalent: "")
        item.image = variant == .light
            ? NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Light")
            : NSImage(systemSymbolName: "moon.stars", accessibilityDescription: "Dark")
        item.image?.isTemplate = true
        item.isEnabled = false
        return item
    }

    @objc private func openKeyboardShortcutsMenuItem() {
        stopMenuEffect()
        openKeyboardShortcuts()
    }

    @objc private func openManageThemesMenuItem() {
        stopMenuEffect()
        openManageThemes()
    }

    @objc private func toggleAppearance() {
        model.toggleAppearance()
    }

    @objc private func openSettingsMenuItem() {
        stopMenuEffect()
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func addDisabled(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
}

@MainActor
private final class MenuEffectView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct MenuAuroraView: View {
    @AppStorage(MenuEffect.auroraPairEnabledKey) private var pairEnabled = false
    @AppStorage(MenuEffect.auroraFirstColorKey) private var firstColor = "#20F2C7"
    @AppStorage(MenuEffect.auroraSecondColorKey) private var secondColor = "#A661FF"
    @Environment(\.colorScheme) private var colorScheme
    @State private var start = Date()
    let customHue: Double?
    let speedMultiplier: Double
    let brightnessMultiplier: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.white)
                    .colorEffect(ShaderLibrary.menuAurora(
                        .float2(geometry.size),
                        .float(timeline.date.timeIntervalSince(start) * speedMultiplier),
                        .float(colorScheme == .dark ? 1 : 0),
                        .float(customHue ?? -1),
                        .float(brightnessMultiplier),
                        .float(pairEnabled ? 1 : 0),
                        .color(Color(nsColor: NSColor(hexThemeColor: firstColor) ?? .systemTeal)),
                        .color(Color(nsColor: NSColor(hexThemeColor: secondColor) ?? .systemPurple))
                    ))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
private final class MenuEffectOverlay {
    private let content: MenuEffectView

    init?(menuWindow: NSWindow, effect: MenuEffect) {
        guard let menuContent = menuWindow.contentView else { return nil }
        if effect == .aurora {
            // Without its shader, SwiftUI displays the opaque source rectangle over the menu.
            guard let device = MTLCreateSystemDefaultDevice(),
                  let library = try? device.makeDefaultLibrary(bundle: .main),
                  library.functionNames.contains("menuAurora") else { return nil }
        }
        let inset: CGFloat = effect == .aurora ? 0 : 5
        content = MenuEffectView(frame: menuContent.bounds.insetBy(dx: inset, dy: inset))
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        content.layer?.cornerRadius = 13
        if effect == .rain {
            let rain = MenuRainView(settings: MenuRainSettings(
                speedMultiplier: effect.speedMultiplier,
                brightness: effect.brightnessMultiplier
            ))
            rain.frame = content.bounds
            rain.autoresizingMask = [.width, .height]
            content.addSubview(rain)
            menuContent.addSubview(content, positioned: .above, relativeTo: nil)
            return
        }
        if effect == .aurora {
            let aurora = NSHostingView(rootView: MenuAuroraView(
                customHue: effect.customHue,
                speedMultiplier: effect.speedMultiplier,
                brightnessMultiplier: effect.brightnessMultiplier
            ))
            aurora.frame = content.bounds
            aurora.autoresizingMask = [.width, .height]
            content.addSubview(aurora)
            menuContent.addSubview(content, positioned: .above, relativeTo: nil)
            return
        }
        guard let image = Self.particleImage(for: effect) else { return nil }
        let isLightMode = menuContent.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        let cells: [CAEmitterCell]
        if effect == .snow {
            guard let snowflakeImage = Self.snowflakeImage() else { return nil }
            cells = [Self.snowCell(image: image), Self.snowflakeCell(image: snowflakeImage)]
        } else {
            cells = Self.sparkleCells(image: image, isLightMode: isLightMode)
        }
        let brightness = CGFloat(effect.brightnessMultiplier)
        if brightness != 1 {
            for cell in cells {
                guard let cgColor = cell.color,
                      let color = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB) else { continue }
                cell.color = NSColor(
                    deviceRed: min(1, color.redComponent * brightness),
                    green: min(1, color.greenComponent * brightness),
                    blue: min(1, color.blueComponent * brightness),
                    alpha: min(1, color.alphaComponent * brightness)
                ).cgColor
                cell.alphaSpeed /= Float(brightness)
            }
        }
        let emitter = CAEmitterLayer()
        emitter.frame = content.bounds
        emitter.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        emitter.emitterShape = .line
        emitter.renderMode = effect == .rainbow && isLightMode ? .unordered : .additive
        emitter.speed = (effect == .rainbow ? 0.95 : 1) * Float(effect.speedMultiplier)
        let isSnow = effect == .snow
        // Clip births beyond the menu edge; prewarm so particles enter on open.
        emitter.emitterPosition = CGPoint(x: content.bounds.width / 2 - (isSnow ? 25 : 0), y: isSnow ? content.bounds.height + 30 : -18)
        emitter.emitterSize = CGSize(width: isSnow ? content.bounds.width + 50 : max(0, content.bounds.width - 28), height: 1)
        emitter.beginTime = CACurrentMediaTime() - (isSnow ? 7.5 : 1.2)
        emitter.emitterCells = cells
        content.layer?.addSublayer(emitter)
        menuContent.addSubview(content, positioned: .above, relativeTo: nil)
    }

    func close() {
        content.isHidden = true
        content.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        content.removeFromSuperview()
    }

    private static func sparkleCells(image: CGImage, isLightMode: Bool) -> [CAEmitterCell] {
        let customHue = MenuEffect.rainbow.customHue
        let sizes: [CGFloat] = [2, 3]
        let birthRate: Float = 1.5
        let phaseSpacing = 1.0 / (Double(8 * sizes.count) * Double(birthRate))
        return (0..<8).flatMap { index in
            sizes.enumerated().map { sizeIndex, size in
                let cell = CAEmitterCell()
                cell.contents = image
                cell.color = NSColor(
                    calibratedHue: customHue.map {
                        CGFloat(($0 + Double(index) / 7 * 0.08 - 0.04 + 1).truncatingRemainder(dividingBy: 1))
                    } ?? CGFloat(index) / 8,
                    saturation: customHue == 1 ? 0 : (isLightMode ? 1 : 0.8),
                    brightness: customHue == 1 ? 1 : (isLightMode ? 0.7 : 1),
                    alpha: 1
                ).cgColor
                cell.birthRate = birthRate
                cell.beginTime = Double(index * sizes.count + sizeIndex) * phaseSpacing
                cell.lifetime = 4.8
                cell.lifetimeRange = 0.7
                cell.yAcceleration = 40
                cell.scale = size / 20 * (isLightMode ? 1.02 : 1)
                cell.spin = 0.5
                cell.spinRange = 0.7
                cell.alphaSpeed = -0.18
                return cell
            }
        }
    }

    private static func snowCell(image: CGImage) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image
        cell.color = NSColor(calibratedWhite: 1, alpha: 0.85).cgColor
        cell.birthRate = 22
        cell.lifetime = 7.5
        cell.lifetimeRange = 1
        cell.xAcceleration = 1.625625
        cell.yAcceleration = -16.25625
        cell.scale = 3 / 20
        cell.scaleRange = 1 / 20
        cell.alphaSpeed = -0.1
        return cell
    }

    private static func snowflakeCell(image: CGImage) -> CAEmitterCell {
        let cell = snowCell(image: image)
        cell.birthRate = 1
        cell.scale = 7.5 / 20
        cell.scaleRange = 0.5 / 20
        cell.spin = 0.2
        cell.spinRange = 0.2
        return cell
    }

    private static func particleImage(for effect: MenuEffect) -> CGImage? {
        guard let context = particleContext() else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        switch effect {
        case .rainbow:
            let points = [
                CGPoint(x: 10, y: 0), CGPoint(x: 12, y: 8),
                CGPoint(x: 20, y: 10), CGPoint(x: 12, y: 12),
                CGPoint(x: 10, y: 20), CGPoint(x: 8, y: 12),
                CGPoint(x: 0, y: 10), CGPoint(x: 8, y: 8)
            ]
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        case .snow:
            context.fillEllipse(in: CGRect(x: 2, y: 2, width: 16, height: 16))
        case .off, .aurora, .rain:
            return nil
        }
        return context.makeImage()
    }

    private static func snowflakeImage() -> CGImage? {
        guard let context = particleContext() else { return nil }
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2.4)
        context.setLineCap(.round)
        for arm in 0..<6 {
            let angle = CGFloat(arm) * .pi / 3
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            context.move(to: CGPoint(x: 10, y: 10))
            context.addLine(to: CGPoint(x: 10 + 8 * direction.x, y: 10 + 8 * direction.y))
            let branch = CGPoint(x: 10 + 5 * direction.x, y: 10 + 5 * direction.y)
            for offset in [-CGFloat.pi / 4, CGFloat.pi / 4] {
                context.move(to: branch)
                context.addLine(to: CGPoint(
                    x: branch.x + 2.5 * cos(angle + offset),
                    y: branch.y + 2.5 * sin(angle + offset)
                ))
            }
        }
        context.strokePath()
        return context.makeImage()
    }

    private static func particleContext() -> CGContext? {
        CGContext(
            data: nil,
            width: 20,
            height: 20,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

private final class MenuThemeRowView: NSView {
    static let rowSize = NSSize(width: 240, height: 26)
    private let apply: () -> Void
    private let toggleFavorite: (() -> Void)?
    private var title: String
    private var isActive: Bool
    private let heartButton: MenuThemeFavoriteButton?
    private let titleButton: NSButton
    private let swatches: MenuThemeSwatchPairView
    private var isFavorite: Bool?
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false

    init(
        title: String,
        theme: ChromeTheme,
        isActive: Bool,
        isFavorite: Bool? = nil,
        apply: @escaping () -> Void,
        toggleFavorite: (() -> Void)? = nil
    ) {
        self.apply = apply
        self.toggleFavorite = toggleFavorite
        self.title = title
        self.isActive = isActive
        self.isFavorite = isFavorite
        self.heartButton = isFavorite.map { _ in
            MenuThemeFavoriteButton(image: Self.outlineHeartImage(), target: nil, action: nil)
        }
        self.titleButton = menuTitleButton(title: title)
        self.swatches = MenuThemeSwatchPairView(theme: theme)
        super.init(frame: NSRect(origin: .zero, size: Self.rowSize))
        wantsLayer = true

        titleButton.target = self
        titleButton.action = #selector(applyTheme)

        heartButton?.target = self
        heartButton?.action = #selector(toggleFavoriteTheme)
        heartButton?.isBordered = false
        heartButton?.imagePosition = .imageOnly
        updateHeart()
        heartButton?.setContentHuggingPriority(.required, for: .horizontal)
        swatches.setContentHuggingPriority(.required, for: .horizontal)

        let views = [heartButton, titleButton, swatches].compactMap { $0 }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Self.rowSize.height),
            widthAnchor.constraint(equalToConstant: Self.rowSize.width)
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func applyTheme() {
        apply()
    }

    func update(title: String, isActive: Bool) {
        self.title = title
        self.isActive = isActive
        updateAppearance()
    }

    @objc private func toggleFavoriteTheme() {
        guard let currentFavorite = isFavorite else { return }
        isFavorite = !currentFavorite
        heartButton?.suppressHoverUntilExit()
        toggleFavorite?()
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        if let heartButton, heartButton.frame.contains(convert(event.locationInWindow, from: nil)) {
            super.mouseUp(with: event)
            return
        }
        applyTheme()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isHovered ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        titleButton.attributedTitle = menuRowTitle(title: title, hovered: isHovered, isActive: isActive)
        updateHeart()
    }

    private func updateHeart() {
        guard let heartButton, let isFavorite else { return }
        heartButton.updateAppearance(
            isFavorite: isFavorite,
            rowIsHovered: isHovered,
            rowHoverSuppressed: false
        )
    }

    private static func outlineHeartImage() -> NSImage {
        let image = NSImage(systemSymbolName: "heart", accessibilityDescription: "Favorite") ?? NSImage()
        image.isTemplate = true
        return image
    }
}

private final class MenuThemeFavoriteButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    private var trackingAreaRef: NSTrackingArea?
    private var isPointerHovered = false
    private var rowIsHovered = false
    private var rowHoverSuppressed = false
    private var hoverSuppressedUntilExit = false
    private var isFavorite = false
    private var hoverFillView: NSImageView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureHoverFillView()
    }

    convenience init(image: NSImage, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.image = image
        self.target = target
        self.action = action
    }

    private func configureHoverFillView() {
        let fillView = MenuThemeFavoriteFillView(
            image: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil) ?? NSImage()
        )
        fillView.translatesAutoresizingMaskIntoConstraints = false
        fillView.imageScaling = .scaleAxesIndependently
        fillView.isHidden = true
        addSubview(fillView, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            fillView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            fillView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
        hoverFillView = fillView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerHovered = true
        hoverSuppressedUntilExit = false
        updateTint()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerHovered = false
        hoverSuppressedUntilExit = false
        updateTint()
    }

    func suppressHoverUntilExit() {
        hoverSuppressedUntilExit = true
        updateTint()
    }

    func updateAppearance(isFavorite: Bool, rowIsHovered: Bool, rowHoverSuppressed: Bool) {
        self.isFavorite = isFavorite
        self.rowIsHovered = rowIsHovered
        self.rowHoverSuppressed = rowHoverSuppressed
        updateTint()
        toolTip = isFavorite ? "Remove favorite" : "Add favorite"
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTint()
    }

    private func updateTint() {
        let isLightMode = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        let isDirectlyHovered = isPointerHovered
            && rowIsHovered
            && !rowHoverSuppressed
            && !hoverSuppressedUntilExit
        image = symbolImage(
            named: isFavorite && !isDirectlyHovered ? "heart.fill" : "heart",
            accessibilityDescription: isFavorite ? "Favorite" : "Not Favorite"
        )
        let outlineTint = isLightMode ? NSColor.black : rowIsHovered
            ? NSColor.selectedMenuItemTextColor
            : isFavorite ? .white : NSColor.secondaryLabelColor
        contentTintColor = outlineTint
        hoverFillView?.contentTintColor = isDirectlyHovered
            ? (isLightMode ? NSColor.black.withAlphaComponent(0.45)
                : NSColor.selectedMenuItemTextColor.withAlphaComponent(0.72))
            : outlineTint
        hoverFillView?.isHidden = !isDirectlyHovered
    }

    private func symbolImage(named name: String, accessibilityDescription: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) ?? NSImage()
        image.isTemplate = true
        return image
    }
}

private final class MenuThemeFavoriteFillView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class MenuThemeSwatchPairView: NSView {
    private let foregroundDot: MenuThemeSwatchDot
    private let backgroundDot: MenuThemeSwatchDot

    init(theme: ChromeTheme) {
        let foregroundColor = NSColor(hexThemeColor: theme.foreground)
        let backgroundColor = NSColor(hexThemeColor: theme.background)
        self.foregroundDot = MenuThemeSwatchDot(color: foregroundColor, borderColor: backgroundColor)
        self.backgroundDot = MenuThemeSwatchDot(color: backgroundColor, borderColor: foregroundColor)
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 12))
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [foregroundDot, backgroundDot])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            foregroundDot.widthAnchor.constraint(equalToConstant: 10.5),
            foregroundDot.heightAnchor.constraint(equalToConstant: 10.5),
            backgroundDot.widthAnchor.constraint(equalToConstant: 10.5),
            backgroundDot.heightAnchor.constraint(equalToConstant: 10.5)
        ])
        toolTip = "Foreground and background colors"
    }

    func update(theme: ChromeTheme) {
        let foreground = NSColor(hexThemeColor: theme.foreground)
        let background = NSColor(hexThemeColor: theme.background)
        foregroundDot.update(color: foreground, borderColor: background)
        backgroundDot.update(color: background, borderColor: foreground)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 25, height: 12.5)
    }
}

private final class MenuThemeSwatchDot: NSView {
    init(color: NSColor?, borderColor: NSColor?) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 5.25
        layer?.borderWidth = 1
        update(color: color, borderColor: borderColor)
    }

    func update(color: NSColor?, borderColor: NSColor?) {
        isHidden = color == nil
        layer?.backgroundColor = color?.cgColor
        layer?.borderColor = borderColor.map {
            $0.withAlphaComponent($0.alphaComponent * 0.65).cgColor
        } ?? NSColor.separatorColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class MenuThemeTitleButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }
}

@MainActor
private func menuTitleButton(title: String) -> NSButton {
    let button = MenuThemeTitleButton(title: title, target: nil, action: nil)
    button.isBordered = false
    button.alignment = .left
    button.attributedTitle = menuRowTitle(title: title, hovered: false, isActive: false)
    button.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return button
}

@MainActor
private func menuRowTitle(title: String, hovered: Bool, isActive: Bool) -> NSAttributedString {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: hovered ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
    ]
    let result = NSMutableAttributedString(string: title, attributes: attributes)
    if isActive {
        result.append(NSAttributedString(string: " ✓", attributes: attributes))
    }
    return result
}

private struct ThemeNoticeSwatches: NSViewRepresentable {
    let theme: ChromeTheme

    func makeNSView(context: Context) -> MenuThemeSwatchPairView {
        MenuThemeSwatchPairView(theme: theme)
    }

    func updateNSView(_ nsView: MenuThemeSwatchPairView, context: Context) {
        nsView.update(theme: theme)
    }
}

private struct ThemeNoticeBubble: View {
    let name: String
    let variant: ThemeVariant
    let theme: ChromeTheme?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: variant == .light ? "sun.max" : "moon.stars")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let theme {
                ThemeNoticeSwatches(theme: theme)
                    .frame(width: 25, height: 12.5)
                    .scaleEffect(1.15)
                    .frame(width: 28.75, height: 14.375)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 300, height: 52, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Theme: \(name)")
    }
}
