import Foundation

enum CodexGlobalStateStoreError: LocalizedError {
    case invalidRootObject
    case invalidThemePayload
    case invalidAppearanceConfig

    var errorDescription: String? {
        switch self {
        case .invalidRootObject:
            return "Global state root is not a JSON object."
        case .invalidThemePayload:
            return "Theme payload could not be encoded."
        case .invalidAppearanceConfig:
            return "Codex desktop appearance configuration is unavailable or malformed."
        }
    }
}

public final class CodexGlobalStateStore {
    private let stateURL: URL
    private let backupURL: URL
    private let fileManager: FileManager

    public init(stateURL: URL, backupURL: URL, fileManager: FileManager = .default) {
        self.stateURL = stateURL
        self.backupURL = backupURL
        self.fileManager = fileManager
    }

    public func loadSnapshot() throws -> CodexGlobalStateSnapshot {
        let data = try Data(contentsOf: stateURL)
        if stateURL.pathExtension == "toml" {
            return try CodexDesktopAppearanceConfig(data: data).snapshot()
        }
        let root = try loadRoot(from: data)
        return CodexGlobalStateSnapshot(
            appearanceTheme: root["appearanceTheme"] as? String,
            lightChromeTheme: decodeTheme(root["appearanceLightChromeTheme"]),
            darkChromeTheme: decodeTheme(root["appearanceDarkChromeTheme"]),
            lightCodeThemeId: root["appearanceLightCodeThemeId"] as? String,
            darkCodeThemeId: root["appearanceDarkCodeThemeId"] as? String
        )
    }

    @discardableResult
    public func apply(payload: ThemeFilePayload) throws -> CodexGlobalStateSnapshot {
        if stateURL.pathExtension == "toml" {
            let data = try Data(contentsOf: stateURL)
            let config = try CodexDesktopAppearanceConfig(data: data)
            let updated = try config.applying(payload)
            try backup(data: data)
            try updated.write(to: stateURL, options: .atomic)
            return try loadSnapshot()
        }
        return try apply(theme: payload.theme, codeThemeId: payload.codeThemeId, to: ApplyTarget(payload.variant))
    }

    @discardableResult
    public func setAppearanceMode(_ mode: ApplyTarget) throws -> CodexGlobalStateSnapshot {
        let data = try Data(contentsOf: stateURL)
        if stateURL.pathExtension == "toml" {
            let updated = try CodexDesktopAppearanceConfig(data: data).settingMode(mode)
            try backup(data: data)
            try updated.write(to: stateURL, options: .atomic)
            return try loadSnapshot()
        }
        var root = try loadRoot(from: data)
        try backup(data: data)
        root["appearanceTheme"] = mode.rawValue
        try write(root: root, to: stateURL)
        return try loadSnapshot()
    }

    @discardableResult
    private func apply(theme: ChromeTheme, codeThemeId: String?, to target: ApplyTarget) throws -> CodexGlobalStateSnapshot {
        let data = try Data(contentsOf: stateURL)
        var root = try loadRoot(from: data)
        guard let themeObject = encodeTheme(theme) else {
            throw CodexGlobalStateStoreError.invalidThemePayload
        }
        try backup(data: data)

        switch target {
        case .light:
            root["appearanceTheme"] = "light"
            root["appearanceLightChromeTheme"] = themeObject
            if let codeThemeId {
                root["appearanceLightCodeThemeId"] = codeThemeId
            }
        case .dark:
            root["appearanceTheme"] = "dark"
            root["appearanceDarkChromeTheme"] = themeObject
            if let codeThemeId {
                root["appearanceDarkCodeThemeId"] = codeThemeId
            }
        }

        try write(root: root, to: stateURL)
        return try loadSnapshot()
    }

    private func backup(data: Data) throws {
        try fileManager.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: backupURL.path) {
            _ = fileManager.createFile(atPath: backupURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        try data.write(to: backupURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
    }

    private func write(root: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func loadRoot(from data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexGlobalStateStoreError.invalidRootObject
        }
        return root
    }

    private func decodeTheme(_ object: Any?) -> ChromeTheme? {
        guard let object else { return nil }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let theme = try? JSONDecoder().decode(ChromeTheme.self, from: data) else {
            return nil
        }
        return theme
    }

    private func encodeTheme(_ theme: ChromeTheme) -> [String: Any]? {
        theme.codexPatchObject()
    }
}


struct CodexDesktopAppearanceConfig {
    private let lines: [String]

    init(data: Data) throws {
        guard let source = String(data: data, encoding: .utf8) else {
            throw CodexGlobalStateStoreError.invalidAppearanceConfig
        }
        lines = source.components(separatedBy: "\n")
    }

    func snapshot() -> CodexGlobalStateSnapshot {
        var tables: [String: [String: Any]] = [:]
        var table = ""
        for line in lines {
            if let heading = Self.heading(in: line) {
                table = heading
                continue
            }
            guard table == "desktop" || table.hasPrefix("desktop.appearanceLightChromeTheme") || table.hasPrefix("desktop.appearanceDarkChromeTheme"),
                  let (key, tokenRange) = Self.assignment(in: line),
                  let value = Self.scalar(String(line[tokenRange])) else { continue }
            tables[table, default: [:]][key] = value
        }

        return CodexGlobalStateSnapshot(
            appearanceTheme: tables["desktop"]?["appearanceTheme"] as? String,
            lightChromeTheme: Self.theme(named: "appearanceLightChromeTheme", in: tables),
            darkChromeTheme: Self.theme(named: "appearanceDarkChromeTheme", in: tables),
            lightCodeThemeId: tables["desktop"]?["appearanceLightCodeThemeId"] as? String,
            darkCodeThemeId: tables["desktop"]?["appearanceDarkCodeThemeId"] as? String
        )
    }

    func settingMode(_ mode: ApplyTarget) throws -> Data {
        guard snapshot().appearanceTheme.flatMap(ApplyTarget.init(rawValue:)) != nil else {
            throw CodexGlobalStateStoreError.invalidAppearanceConfig
        }
        var updated = lines
        try Self.setDesktopValue("appearanceTheme", to: mode.rawValue, in: &updated, insertIfMissing: false)
        return Data(updated.joined(separator: "\n").utf8)
    }

    func applying(_ payload: ThemeFilePayload) throws -> Data {
        guard payload.theme.codexPatchObject() != nil else {
            throw CodexGlobalStateStoreError.invalidThemePayload
        }
        let themeName = payload.variant == .light ? "appearanceLightChromeTheme" : "appearanceDarkChromeTheme"
        let prefix = "desktop.\(themeName)"
        var updated: [String] = []
        var table = ""
        var insertionIndex: Int?
        for line in lines {
            if let heading = Self.heading(in: line) { table = heading }
            if table == prefix || table.hasPrefix(prefix + ".") {
                if insertionIndex == nil { insertionIndex = updated.count }
            } else {
                updated.append(line)
            }
        }
        updated.insert(contentsOf: Self.renderTheme(payload.theme, named: prefix), at: insertionIndex ?? updated.count)
        try Self.setDesktopValue("appearanceTheme", to: payload.variant.rawValue, in: &updated, insertIfMissing: true)
        let codeThemeKey = payload.variant == .light ? "appearanceLightCodeThemeId" : "appearanceDarkCodeThemeId"
        try Self.setDesktopValue(codeThemeKey, to: payload.codeThemeId, in: &updated, insertIfMissing: true)
        return Data(updated.joined(separator: "\n").utf8)
    }

    private static func theme(named name: String, in tables: [String: [String: Any]]) -> ChromeTheme? {
        let prefix = "desktop.\(name)"
        guard var object = tables[prefix], var fonts = tables[prefix + ".fonts"],
              let semanticColors = tables[prefix + ".semanticColors"] else { return nil }
        if let contentFace = tables[prefix + ".fonts.contentFace"] {
            fonts["contentFace"] = contentFace
        }
        object["fonts"] = fonts
        object["semanticColors"] = semanticColors
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(ChromeTheme.self, from: data)
    }

    private static func heading(in line: String) -> String? {
        let value = line.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("["), let end = value.firstIndex(of: "]") else { return nil }
        return String(value[value.index(after: value.startIndex)..<end])
    }

    private static func assignment(in line: String) -> (String, Range<String.Index>)? {
        guard let equal = line.firstIndex(of: "="), !line[..<equal].contains("#") else { return nil }
        let key = line[..<equal].trimmingCharacters(in: .whitespaces)
        var start = line.index(after: equal)
        while start < line.endIndex && line[start].isWhitespace { start = line.index(after: start) }
        guard start < line.endIndex else { return nil }
        let quote = line[start]
        if quote == "\"" || quote == "'" {
            var cursor = line.index(after: start)
            while cursor < line.endIndex {
                if quote == "\"" && line[cursor] == "\\" {
                    cursor = line.index(after: cursor)
                    guard cursor < line.endIndex else { return nil }
                } else if line[cursor] == quote {
                    return (key, start..<line.index(after: cursor))
                }
                cursor = line.index(after: cursor)
            }
            return nil
        }
        let end = line[start...].firstIndex(of: "#") ?? line.endIndex
        let token = line[start..<end].trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty, let range = line.range(of: token, range: start..<end) else { return nil }
        return (key, range)
    }

    private static func scalar(_ token: String) -> Any? {
        if token.hasPrefix("\"") { return try? JSONDecoder().decode(String.self, from: Data(token.utf8)) }
        if token.hasPrefix("'") && token.hasSuffix("'") { return String(token.dropFirst().dropLast()) }
        if token == "true" { return true }
        if token == "false" { return false }
        return Int(token)
    }

    private static func setDesktopValue(_ key: String, to value: String, in lines: inout [String], insertIfMissing: Bool) throws {
        guard let desktopIndex = lines.firstIndex(where: { heading(in: $0) == "desktop" }) else {
            throw CodexGlobalStateStoreError.invalidAppearanceConfig
        }
        let end = lines[(desktopIndex + 1)...].firstIndex(where: { heading(in: $0) != nil }) ?? lines.count
        let encoded = quoted(value)
        for index in (desktopIndex + 1)..<end {
            guard let (name, range) = assignment(in: lines[index]), name == key else { continue }
            lines[index].replaceSubrange(range, with: encoded)
            return
        }
        guard insertIfMissing else { throw CodexGlobalStateStoreError.invalidAppearanceConfig }
        lines.insert("\(key) = \(encoded)", at: desktopIndex + 1)
    }

    private static func renderTheme(_ theme: ChromeTheme, named prefix: String) -> [String] {
        var result = [
            "[\(prefix)]",
            "accent = \(quoted(theme.accent))",
            "contrast = \(theme.contrast)",
            "ink = \(quoted(theme.foreground))",
            "opaqueWindows = \(theme.opaqueWindows)",
            "surface = \(quoted(theme.background))",
            "",
            "[\(prefix).fonts]",
            "code = \(quoted(theme.fonts.code))",
            "ui = \(quoted(theme.fonts.ui))"
        ]
        if let content = theme.fonts.content { result.append("content = \(quoted(content))") }
        if let face = theme.fonts.contentFace {
            result += [
                "", "[\(prefix).fonts.contentFace]",
                "family = \(quoted(face.family))",
                "fullName = \(quoted(face.fullName))",
                "postscriptName = \(quoted(face.postscriptName))"
            ]
        }
        result += [
            "", "[\(prefix).semanticColors]",
            "diffAdded = \(quoted(theme.semanticColors.diffAdded))",
            "diffRemoved = \(quoted(theme.semanticColors.diffRemoved))",
            "skill = \(quoted(theme.accent))",
            ""
        ]
        return result
    }

    private static func quoted(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
