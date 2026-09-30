import AppKit
import Carbon
import Foundation

public enum ThemeVariant: String, Codable, CaseIterable, Sendable {
    case light
    case dark
}

public struct ThemeFontFace: Codable, Equatable, Sendable {
    public let family: String
    public let fullName: String
    public let postscriptName: String

    public init(family: String, fullName: String, postscriptName: String) {
        self.family = family
        self.fullName = fullName
        self.postscriptName = postscriptName
    }
}

public struct ThemeFonts: Codable, Equatable, Sendable {
    public let code: String
    public let ui: String
    public let content: String?
    public let contentFace: ThemeFontFace?
    public let codeFace: ThemeFontFace?
    public let uiFace: ThemeFontFace?

    public init(code: String, ui: String, content: String? = nil, contentFace: ThemeFontFace? = nil, codeFace: ThemeFontFace? = nil, uiFace: ThemeFontFace? = nil) {
        self.code = code
        self.ui = ui
        self.content = content
        self.contentFace = contentFace
        self.codeFace = codeFace
        self.uiFace = uiFace
    }
}

public struct ThemeSemanticColors: Codable, Equatable, Sendable {
    public let diffAdded: String
    public let diffRemoved: String

    public init(diffAdded: String, diffRemoved: String) {
        self.diffAdded = diffAdded
        self.diffRemoved = diffRemoved
    }
}

public struct ChromeTheme: Codable, Equatable, Sendable {
    public let accent: String
    public let contrast: Int
    public let fonts: ThemeFonts
    public let foreground: String
    public let opaqueWindows: Bool
    public let semanticColors: ThemeSemanticColors
    public let background: String

    public init(
        accent: String,
        contrast: Int,
        fonts: ThemeFonts,
        foreground: String,
        opaqueWindows: Bool,
        semanticColors: ThemeSemanticColors,
        background: String
    ) {
        self.accent = accent
        self.contrast = contrast
        self.fonts = fonts
        self.foreground = foreground
        self.opaqueWindows = opaqueWindows
        self.semanticColors = semanticColors
        self.background = background
    }

    private enum CodingKeys: String, CodingKey {
        case accent
        case contrast
        case fonts
        case foreground
        case ink
        case opaqueWindows
        case semanticColors
        case background
        case surface
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accent = try container.decode(String.self, forKey: .accent)
        contrast = try container.decode(Int.self, forKey: .contrast)
        fonts = try container.decode(ThemeFonts.self, forKey: .fonts)
        foreground = try container.decodeIfPresent(String.self, forKey: .foreground)
            ?? container.decode(String.self, forKey: .ink)
        opaqueWindows = try container.decode(Bool.self, forKey: .opaqueWindows)
        semanticColors = try container.decode(ThemeSemanticColors.self, forKey: .semanticColors)
        background = try container.decodeIfPresent(String.self, forKey: .background)
            ?? container.decode(String.self, forKey: .surface)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accent, forKey: .accent)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(fonts, forKey: .fonts)
        try container.encode(foreground, forKey: .foreground)
        try container.encode(opaqueWindows, forKey: .opaqueWindows)
        try container.encode(semanticColors, forKey: .semanticColors)
        try container.encode(background, forKey: .background)
    }

    public var inverted: ChromeTheme {
        ChromeTheme(
            accent: accent,
            contrast: contrast,
            fonts: fonts,
            foreground: background,
            opaqueWindows: opaqueWindows,
            semanticColors: semanticColors,
            background: foreground
        )
    }

    public func codexPatchObject() -> [String: Any]? {
        guard let fontData = try? JSONEncoder().encode(fonts),
              let fontObject = try? JSONSerialization.jsonObject(with: fontData) else { return nil }
        let object: [String: Any] = [
            "accent": accent,
            "contrast": contrast,
            "fonts": fontObject,
            "ink": foreground,
            "opaqueWindows": opaqueWindows,
            "semanticColors": [
                "diffAdded": semanticColors.diffAdded,
                "diffRemoved": semanticColors.diffRemoved,
                // Codex requires this field even though Codex ThemeWurx has no separate skill color.
                "skill": accent
            ],
            "surface": background
        ]
        return JSONSerialization.isValidJSONObject(object) ? object : nil
    }
}

public struct ThemeFilePayload: Codable, Equatable, Sendable {
    public let variant: ThemeVariant
    public let codeThemeId: String
    public let favorite: Bool
    public let theme: ChromeTheme

    public init(variant: ThemeVariant, codeThemeId: String, favorite: Bool = false, theme: ChromeTheme) {
        self.variant = variant
        self.codeThemeId = codeThemeId
        self.favorite = favorite
        self.theme = theme
    }

    private enum CodingKeys: String, CodingKey {
        case variant
        case codeThemeId
        case favorite
        case theme
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        variant = try container.decode(ThemeVariant.self, forKey: .variant)
        codeThemeId = try container.decode(String.self, forKey: .codeThemeId)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        theme = try container.decode(ChromeTheme.self, forKey: .theme)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(variant, forKey: .variant)
        try container.encode(codeThemeId, forKey: .codeThemeId)
        if favorite {
            try container.encode(true, forKey: .favorite)
        }
        try container.encode(theme, forKey: .theme)
    }
}

public struct CustomThemeEntry: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let payload: ThemeFilePayload

    public init(name: String, payload: ThemeFilePayload) {
        self.name = name
        self.payload = payload
    }

    public var id: String {
        [
            payload.variant.rawValue,
            name,
            payload.codeThemeId,
            payload.theme.accent,
            String(payload.theme.contrast),
            payload.theme.fonts.code,
            payload.theme.fonts.codeFace?.family ?? "",
            payload.theme.fonts.codeFace?.fullName ?? "",
            payload.theme.fonts.codeFace?.postscriptName ?? "",
            payload.theme.fonts.ui,
            payload.theme.fonts.uiFace?.family ?? "",
            payload.theme.fonts.uiFace?.fullName ?? "",
            payload.theme.fonts.uiFace?.postscriptName ?? "",
            payload.theme.fonts.content ?? "",
            payload.theme.fonts.contentFace?.family ?? "",
            payload.theme.fonts.contentFace?.fullName ?? "",
            payload.theme.fonts.contentFace?.postscriptName ?? "",
            payload.theme.foreground,
            String(payload.theme.opaqueWindows),
            payload.theme.semanticColors.diffAdded,
            payload.theme.semanticColors.diffRemoved,
            payload.theme.background
        ].joined(separator: "::")
    }

    public var variant: ThemeVariant {
        payload.variant
    }

    public var codeThemeId: String {
        payload.codeThemeId
    }

    public var theme: ChromeTheme {
        payload.theme
    }

    public var isFavorite: Bool {
        payload.favorite
    }
}

public struct ThemeEditorDraft: Equatable, Sendable {
    public static let defaultCodeThemeId = "rose-pine"
    public static let defaultOpaqueWindows = true
    public static let defaultContrast = 60
    public static let contrastRange = 0...100

    public var name: String
    public var variant: ThemeVariant
    public var favorite: Bool
    public var foreground: String
    public var background: String
    public var accent: String
    public var diffAdded: String
    public var diffRemoved: String
    public var contrast: String
    public var codeFont: String
    public var codeFontFace: ThemeFontFace?
    public var uiFont: String
    public var uiFontFace: ThemeFontFace?
    public var contentFont: String?
    public var contentFontFace: ThemeFontFace?
    public var codeThemeId: String
    public var opaqueWindows: Bool

    public init(
        name: String,
        variant: ThemeVariant,
        favorite: Bool,
        foreground: String,
        background: String,
        accent: String,
        diffAdded: String,
        diffRemoved: String,
        contrast: String,
        codeFont: String,
        uiFont: String,
        contentFont: String? = nil,
        contentFontFace: ThemeFontFace? = nil,
        codeFontFace: ThemeFontFace? = nil,
        uiFontFace: ThemeFontFace? = nil,
        codeThemeId: String = Self.defaultCodeThemeId,
        opaqueWindows: Bool = Self.defaultOpaqueWindows
    ) {
        self.name = name
        self.variant = variant
        self.favorite = favorite
        self.foreground = foreground
        self.background = background
        self.accent = accent
        self.diffAdded = diffAdded
        self.diffRemoved = diffRemoved
        self.contrast = contrast
        self.codeFont = codeFont
        self.codeFontFace = codeFontFace
        self.uiFont = uiFont
        self.uiFontFace = uiFontFace
        self.contentFont = contentFont
        self.contentFontFace = contentFontFace
        self.codeThemeId = codeThemeId
        self.opaqueWindows = opaqueWindows
    }

    public init(entry: CustomThemeEntry) {
        self.init(
            name: entry.name,
            variant: entry.variant,
            favorite: entry.isFavorite,
            foreground: entry.theme.foreground,
            background: entry.theme.background,
            accent: entry.theme.accent,
            diffAdded: entry.theme.semanticColors.diffAdded,
            diffRemoved: entry.theme.semanticColors.diffRemoved,
            contrast: String(entry.theme.contrast),
            codeFont: entry.theme.fonts.code,
            uiFont: entry.theme.fonts.ui,
            contentFont: entry.theme.fonts.content,
            contentFontFace: entry.theme.fonts.contentFace,
            codeFontFace: entry.theme.fonts.codeFace,
            uiFontFace: entry.theme.fonts.uiFace,
            codeThemeId: entry.codeThemeId,
            opaqueWindows: entry.theme.opaqueWindows
        )
    }

    public func hasSameSettings(as other: ThemeEditorDraft) -> Bool {
        var other = other
        other.name = name
        return self == other
    }

    public static func parsedContrast(_ value: String) -> Int? {
        Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func clampedContrast(_ value: String, fallback: Int = Self.defaultContrast) -> Int {
        min(
            Self.contrastRange.upperBound,
            max(Self.contrastRange.lowerBound, Self.parsedContrast(value) ?? fallback)
        )
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Theme name is required.")
        }
        for (label, value) in [
            ("Foreground", foreground),
            ("Background", background),
            ("Accent", accent),
            ("Diff-added", diffAdded),
            ("Diff-removed", diffRemoved)
        ] where !Self.isHexColor(value) {
            errors.append("\(label) must be a #RRGGBB color.")
        }
        if let contrastValue = Self.parsedContrast(contrast) {
            if !Self.contrastRange.contains(contrastValue) {
                errors.append("Contrast must be between 0 and 100.")
            }
        } else {
            errors.append("Contrast must be a whole number.")
        }
        return errors
    }

    public var isValid: Bool {
        validationErrors.isEmpty
    }

    public func entry(named resolvedName: String? = nil) -> CustomThemeEntry? {
        guard let contrastValue = Self.parsedContrast(contrast),
              Self.contrastRange.contains(contrastValue) else {
            return nil
        }
        return CustomThemeEntry(
            name: resolvedName ?? name.trimmingCharacters(in: .whitespacesAndNewlines),
            payload: ThemeFilePayload(
                variant: variant,
                codeThemeId: codeThemeId,
                favorite: favorite,
                theme: ChromeTheme(
                    accent: accent.trimmingCharacters(in: .whitespacesAndNewlines),
                    contrast: contrastValue,
                    fonts: ThemeFonts(
                        code: codeFont.trimmingCharacters(in: .whitespacesAndNewlines),
                        ui: uiFont.trimmingCharacters(in: .whitespacesAndNewlines),
                        content: contentFont,
                        contentFace: contentFontFace,
                        codeFace: codeFontFace,
                        uiFace: uiFontFace
                    ),
                    foreground: foreground.trimmingCharacters(in: .whitespacesAndNewlines),
                    opaqueWindows: opaqueWindows,
                    semanticColors: ThemeSemanticColors(
                        diffAdded: diffAdded.trimmingCharacters(in: .whitespacesAndNewlines),
                        diffRemoved: diffRemoved.trimmingCharacters(in: .whitespacesAndNewlines)
                    ),
                    background: background.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        )
    }

    private static func isHexColor(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 7, trimmed.first == "#" else { return false }
        return trimmed.dropFirst().allSatisfy { $0.isHexDigit }
    }
}

public struct ManagedThemeRow: Identifiable, Equatable, Sendable {
    public let variantIndex: Int
    public let folderID: String
    public let entry: CustomThemeEntry

    public init(variantIndex: Int, folderID: String, entry: CustomThemeEntry) {
        self.variantIndex = variantIndex
        self.folderID = folderID
        self.entry = entry
    }

    public var id: String {
        entry.id
    }

    public var variant: ThemeVariant {
        entry.variant
    }

    public var name: String {
        entry.name
    }
}

public struct ThemeFolder: Identifiable, Equatable, Sendable {
    public static let unfiledName = "Unfiled"

    public let variant: ThemeVariant
    public let name: String
    public let isImplicitUnfiled: Bool
    public let entries: [CustomThemeEntry]

    public init(variant: ThemeVariant, name: String, isImplicitUnfiled: Bool = false, entries: [CustomThemeEntry]) {
        self.variant = variant
        self.name = name
        self.isImplicitUnfiled = isImplicitUnfiled
        self.entries = entries
    }

    public var id: String {
        Self.id(for: variant, name: name, isImplicitUnfiled: isImplicitUnfiled)
    }

    public static func unfiledID(for variant: ThemeVariant) -> String {
        return id(for: variant, name: unfiledName, isImplicitUnfiled: true)
    }

    public static func id(for variant: ThemeVariant, name: String, isImplicitUnfiled: Bool = false) -> String {
        let kind = isImplicitUnfiled ? "implicit" : "folder"
        return "\(variant.rawValue):\(kind):\(name)"
    }
}

public struct ThemeParseIssue: Equatable, Sendable {
    public let line: Int
    public let message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }
}

public struct ThemeCatalog: Equatable, Sendable {
    public let folders: [ThemeFolder]
    public let issues: [ThemeParseIssue]

    public var entries: [CustomThemeEntry] {
        folders.flatMap(\.entries)
    }

    public init(entries: [CustomThemeEntry], issues: [ThemeParseIssue]) {
        self.folders = Self.folders(from: entries)
        self.issues = issues
    }

    public init(folders: [ThemeFolder], issues: [ThemeParseIssue]) {
        self.folders = folders
        self.issues = issues
    }

    public func selectedEntry(
        for target: ApplyTarget,
        in snapshot: CodexGlobalStateSnapshot,
        preferredEntryID: String?
    ) -> CustomThemeEntry? {
        let theme = target == .light ? snapshot.lightChromeTheme : snapshot.darkChromeTheme
        let codeThemeID = target == .light ? snapshot.lightCodeThemeId : snapshot.darkCodeThemeId
        let candidates = entries(for: target == .light ? .light : .dark).filter {
            $0.codeThemeId == codeThemeID && ($0.theme == theme || $0.theme.inverted == theme)
        }
        return candidates.first { $0.id == preferredEntryID } ?? candidates.first
    }

    private static func folders(from entries: [CustomThemeEntry]) -> [ThemeFolder] {
        ThemeVariant.allCases.compactMap { variant in
            let variantEntries = entries.filter { $0.variant == variant }
            guard !variantEntries.isEmpty else { return nil }
            return ThemeFolder(variant: variant, name: ThemeFolder.unfiledName, isImplicitUnfiled: true, entries: variantEntries)
        }
    }
}

public enum ApplyTarget: String, Sendable {
    case light
    case dark

    public init(_ variant: ThemeVariant) {
        switch variant {
        case .light:
            self = .light
        case .dark:
            self = .dark
        }
    }
}

public enum ThemeCycleDirection: String, Codable, Sendable {
    case previous
    case next
}

public struct ThemeHotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = ThemeHotkeyModifiers(rawValue: 1 << 0)
    public static let option = ThemeHotkeyModifiers(rawValue: 1 << 1)
    public static let control = ThemeHotkeyModifiers(rawValue: 1 << 2)
    public static let shift = ThemeHotkeyModifiers(rawValue: 1 << 3)

    public init(eventModifiers: NSEvent.ModifierFlags) {
        var modifiers: ThemeHotkeyModifiers = []
        if eventModifiers.contains(.command) {
            modifiers.insert(.command)
        }
        if eventModifiers.contains(.option) {
            modifiers.insert(.option)
        }
        if eventModifiers.contains(.control) {
            modifiers.insert(.control)
        }
        if eventModifiers.contains(.shift) {
            modifiers.insert(.shift)
        }
        self = modifiers
    }

    public var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if contains(.option) {
            flags |= UInt32(optionKey)
        }
        if contains(.control) {
            flags |= UInt32(controlKey)
        }
        if contains(.shift) {
            flags |= UInt32(shiftKey)
        }
        return flags
    }

    public var symbols: String {
        var value = ""
        if contains(.control) {
            value += "⌃"
        }
        if contains(.option) {
            value += "⌥"
        }
        if contains(.shift) {
            value += "⇧"
        }
        if contains(.command) {
            value += "⌘"
        }
        return value
    }
}

public struct ThemeHotkeyShortcut: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt32
    public let key: String
    public let modifiers: ThemeHotkeyModifiers

    public init(keyCode: UInt32, key: String, modifiers: ThemeHotkeyModifiers) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers
    }

    public var displayString: String {
        modifiers.symbols + key.uppercased()
    }

    public static func displayKey(for keyCode: UInt32, characters: String?) -> String {
        switch Int(keyCode) {
        case Int(kVK_ANSI_LeftBracket):
            return "["
        case Int(kVK_ANSI_RightBracket):
            return "]"
        case Int(kVK_LeftArrow):
            return "←"
        case Int(kVK_RightArrow):
            return "→"
        case Int(kVK_UpArrow):
            return "↑"
        case Int(kVK_DownArrow):
            return "↓"
        case Int(kVK_Return):
            return "↩"
        case Int(kVK_Space):
            return "Space"
        case Int(kVK_Tab):
            return "Tab"
        case Int(kVK_Delete):
            return "⌫"
        case Int(kVK_ForwardDelete):
            return "⌦"
        case Int(kVK_Escape):
            return "Esc"
        default:
            let value = (characters?.isEmpty == false ? characters : nil) ?? String(keyCode)
            return value.count == 1 ? value.uppercased() : value
        }
    }
}

public enum ThemeHotkeyAction: String, Codable, CaseIterable, Sendable {
    case lightPrevious
    case lightNext
    case darkPrevious
    case darkNext
    case favoritePrevious
    case favoriteNext
    case invertCurrent
    case toggleAppearance

    public var title: String {
        switch self {
        case .lightPrevious:
            return "Previous Light"
        case .lightNext:
            return "Next Light"
        case .darkPrevious:
            return "Previous Dark"
        case .darkNext:
            return "Next Dark"
        case .favoritePrevious:
            return "Previous Favorite"
        case .favoriteNext:
            return "Next Favorite"
        case .invertCurrent:
            return "Swap Colors"
        case .toggleAppearance:
            return "Toggle Last Light/Dark"
        }
    }

    public var symbolName: String {
        switch self {
        case .lightPrevious, .lightNext:
            return "sun.max"
        case .darkPrevious, .darkNext:
            return "moon.stars"
        case .favoritePrevious, .favoriteNext:
            return "heart.fill"
        case .invertCurrent:
            return "arrow.triangle.2.circlepath"
        case .toggleAppearance:
            return "circle.lefthalf.filled"
        }
    }

    public var target: ApplyTarget? {
        switch self {
        case .lightPrevious, .lightNext:
            return .light
        case .darkPrevious, .darkNext:
            return .dark
        case .favoritePrevious, .favoriteNext:
            return nil
        case .invertCurrent, .toggleAppearance:
            return nil
        }
    }

    public var direction: ThemeCycleDirection? {
        switch self {
        case .lightPrevious, .darkPrevious, .favoritePrevious:
            return .previous
        case .lightNext, .darkNext, .favoriteNext:
            return .next
        case .invertCurrent, .toggleAppearance:
            return nil
        }
    }

    public var defaultShortcut: ThemeHotkeyShortcut? {
        switch self {
        case .lightPrevious:
            return ThemeHotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_LeftBracket),
                key: "[",
                modifiers: [.control, .option, .command]
            )
        case .lightNext:
            return ThemeHotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_RightBracket),
                key: "]",
                modifiers: [.control, .option, .command]
            )
        case .darkPrevious:
            return ThemeHotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_LeftBracket),
                key: "[",
                modifiers: [.control, .option, .shift, .command]
            )
        case .darkNext:
            return ThemeHotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_RightBracket),
                key: "]",
                modifiers: [.control, .option, .shift, .command]
            )
        case .favoritePrevious:
            return ThemeHotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_LeftBracket),
                key: "[",
                modifiers: [.control, .command]
            )
        case .favoriteNext:
            return ThemeHotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_RightBracket),
                key: "]",
                modifiers: [.control, .command]
            )
        case .invertCurrent:
            return ThemeHotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_I),
                key: "I",
                modifiers: [.control, .option, .command]
            )
        case .toggleAppearance:
            return nil
        }
    }
}

public struct ThemeHotkeyBindings: Codable, Equatable, Sendable {
    public var lightPrevious: ThemeHotkeyShortcut?
    public var lightNext: ThemeHotkeyShortcut?
    public var darkPrevious: ThemeHotkeyShortcut?
    public var darkNext: ThemeHotkeyShortcut?
    public var favoritePrevious: ThemeHotkeyShortcut?
    public var favoriteNext: ThemeHotkeyShortcut?
    public var invertCurrent: ThemeHotkeyShortcut?
    public var toggleAppearance: ThemeHotkeyShortcut?

    public init(
        lightPrevious: ThemeHotkeyShortcut? = nil,
        lightNext: ThemeHotkeyShortcut? = nil,
        darkPrevious: ThemeHotkeyShortcut? = nil,
        darkNext: ThemeHotkeyShortcut? = nil,
        favoritePrevious: ThemeHotkeyShortcut? = nil,
        favoriteNext: ThemeHotkeyShortcut? = nil,
        invertCurrent: ThemeHotkeyShortcut? = nil,
        toggleAppearance: ThemeHotkeyShortcut? = nil
    ) {
        self.lightPrevious = lightPrevious
        self.lightNext = lightNext
        self.darkPrevious = darkPrevious
        self.darkNext = darkNext
        self.favoritePrevious = favoritePrevious
        self.favoriteNext = favoriteNext
        self.invertCurrent = invertCurrent
        self.toggleAppearance = toggleAppearance
    }

    public static let defaults = ThemeHotkeyBindings(
        lightPrevious: ThemeHotkeyAction.lightPrevious.defaultShortcut,
        lightNext: ThemeHotkeyAction.lightNext.defaultShortcut,
        darkPrevious: ThemeHotkeyAction.darkPrevious.defaultShortcut,
        darkNext: ThemeHotkeyAction.darkNext.defaultShortcut,
        favoritePrevious: ThemeHotkeyAction.favoritePrevious.defaultShortcut,
        favoriteNext: ThemeHotkeyAction.favoriteNext.defaultShortcut,
        invertCurrent: ThemeHotkeyAction.invertCurrent.defaultShortcut
    )

    public subscript(action: ThemeHotkeyAction) -> ThemeHotkeyShortcut? {
        get {
            switch action {
            case .lightPrevious:
                return lightPrevious
            case .lightNext:
                return lightNext
            case .darkPrevious:
                return darkPrevious
            case .darkNext:
                return darkNext
            case .favoritePrevious:
                return favoritePrevious
            case .favoriteNext:
                return favoriteNext
            case .invertCurrent:
                return invertCurrent
            case .toggleAppearance:
                return toggleAppearance
            }
        }
        set {
            switch action {
            case .lightPrevious:
                lightPrevious = newValue
            case .lightNext:
                lightNext = newValue
            case .darkPrevious:
                darkPrevious = newValue
            case .darkNext:
                darkNext = newValue
            case .favoritePrevious:
                favoritePrevious = newValue
            case .favoriteNext:
                favoriteNext = newValue
            case .invertCurrent:
                invertCurrent = newValue
            case .toggleAppearance:
                toggleAppearance = newValue
            }
        }
    }

    public func duplicateOwner(for shortcut: ThemeHotkeyShortcut?, excluding action: ThemeHotkeyAction) -> ThemeHotkeyAction? {
        guard let shortcut else { return nil }
        for candidate in ThemeHotkeyAction.allCases where candidate != action {
            if self[candidate] == shortcut {
                return candidate
            }
        }
        return nil
    }
}

public struct ThemeHotkeyPreferences: Codable, Equatable, Sendable {
    public var hotkeysEnabled: Bool
    public var bindings: ThemeHotkeyBindings

    public init(hotkeysEnabled: Bool, bindings: ThemeHotkeyBindings) {
        self.hotkeysEnabled = hotkeysEnabled
        self.bindings = bindings
    }

    public static let defaults = ThemeHotkeyPreferences(hotkeysEnabled: true, bindings: .defaults)
}

public final class ThemeHotkeyPreferencesStore {
    public static let storageKey = "themeHotkeyPreferences"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() throws -> ThemeHotkeyPreferences? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try decoder.decode(ThemeHotkeyPreferences.self, from: data)
    }

    public func save(_ preferences: ThemeHotkeyPreferences) throws {
        defaults.set(try encoder.encode(preferences), forKey: Self.storageKey)
    }

}

public struct ThemeHotkeyDebounce {
    private var releasedAt: ContinuousClock.Instant?

    public init() {}

    public mutating func isReady(at now: ContinuousClock.Instant, modifiersHeld: Bool) -> Bool {
        if modifiersHeld {
            releasedAt = nil
            return false
        }
        let start = releasedAt ?? now
        releasedAt = start
        return now - start >= .milliseconds(275)
    }
}

public struct ThemeHotkeyApplyQueue {
    public struct Request: Identifiable, Sendable {
        public let id = UUID()
        public let entry: CustomThemeEntry
    }

    private var selection: Request?
    private var activeID: UUID?
    private var readyID: UUID?

    public init() {}

    public mutating func enqueue(_ entry: CustomThemeEntry) -> Request {
        let request = Request(entry: entry)
        selection = request
        readyID = nil
        return request
    }

    public func isCurrent(_ request: Request) -> Bool {
        selection?.id == request.id
    }

    public mutating func markReady(_ request: Request) {
        guard isCurrent(request) else { return }
        readyID = request.id
    }

    public mutating func takeReady() -> Request? {
        guard activeID == nil, let selection, readyID == selection.id else { return nil }
        activeID = selection.id
        readyID = nil
        return selection
    }

    public mutating func finish(_ request: Request) {
        guard activeID == request.id else { return }
        activeID = nil
        if isCurrent(request) { cancelPending() }
    }

    public mutating func cancelPending() {
        selection = nil
        readyID = nil
        // A dispatched apply still owns the slot until its worker actually exits.
    }
}

public enum ThemeCyclePlanner {
    public static func nextEntry(
        in entries: [CustomThemeEntry],
        currentTheme: ChromeTheme?,
        currentCodeThemeId: String? = nil,
        currentEntryID: String? = nil,
        direction: ThemeCycleDirection
    ) -> CustomThemeEntry? {
        guard !entries.isEmpty else { return nil }
        let matches: (CustomThemeEntry) -> Bool = {
            guard let currentTheme, $0.theme == currentTheme else { return false }
            return currentCodeThemeId == nil || $0.codeThemeId == currentCodeThemeId
        }
        let currentIndex = entries.firstIndex { $0.id == currentEntryID && matches($0) }
            ?? entries.firstIndex(where: matches)
        guard let currentIndex else {
            return direction == .next ? entries.first : entries.last
        }
        switch direction {
        case .next:
            return entries[(currentIndex + 1) % entries.count]
        case .previous:
            return entries[(currentIndex - 1 + entries.count) % entries.count]
        }
    }
}

public struct CodexGlobalStateSnapshot: Equatable, Sendable {
    public let appearanceTheme: String?
    public let lightChromeTheme: ChromeTheme?
    public let darkChromeTheme: ChromeTheme?
    public let lightCodeThemeId: String?
    public let darkCodeThemeId: String?

    public init(
        appearanceTheme: String?,
        lightChromeTheme: ChromeTheme?,
        darkChromeTheme: ChromeTheme?,
        lightCodeThemeId: String?,
        darkCodeThemeId: String?
    ) {
        self.appearanceTheme = appearanceTheme
        self.lightChromeTheme = lightChromeTheme
        self.darkChromeTheme = darkChromeTheme
        self.lightCodeThemeId = lightCodeThemeId
        self.darkCodeThemeId = darkCodeThemeId
    }
}

public struct ThemeBarPaths: Sendable {
    public let themeFileURL: URL
    public let themeBackupURL: URL
    public let themeDefaultsURL: URL
    public let globalStateURL: URL
    public let backupURL: URL

    public init(
        themeFileURL: URL,
        themeBackupURL: URL,
        themeDefaultsURL: URL,
        globalStateURL: URL,
        backupURL: URL
    ) {
        self.themeFileURL = themeFileURL
        self.themeBackupURL = themeBackupURL
        self.themeDefaultsURL = themeDefaultsURL
        self.globalStateURL = globalStateURL
        self.backupURL = backupURL
    }

    public func prepareThemeFile(fileManager: FileManager = .default) throws {
        guard !fileManager.fileExists(atPath: themeFileURL.path) else { return }
        let source = fileManager.fileExists(atPath: themeBackupURL.path) ? themeBackupURL : themeDefaultsURL
        try fileManager.createDirectory(at: themeFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // copyItem refuses to overwrite a personal catalog created after the existence check.
        try fileManager.copyItem(at: source, to: themeFileURL)
    }
}

public extension ThemeCatalog {
    func entries(for variant: ThemeVariant) -> [CustomThemeEntry] {
        folders(for: variant).flatMap(\.entries)
    }

    func managedRows(for variant: ThemeVariant) -> [ManagedThemeRow] {
        var index = 0
        return folders(for: variant).flatMap { folder in
            folder.entries.map { entry in
                defer { index += 1 }
                return ManagedThemeRow(variantIndex: index, folderID: folder.id, entry: entry)
            }
        }
    }

    func folders(for variant: ThemeVariant) -> [ThemeFolder] {
        folders.filter { $0.variant == variant && (!$0.isImplicitUnfiled || !$0.entries.isEmpty) }
    }

    var favoriteEntries: [CustomThemeEntry] {
        entries.filter(\.isFavorite)
    }
}
