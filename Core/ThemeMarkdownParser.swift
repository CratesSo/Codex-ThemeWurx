import Foundation

public enum ThemeCatalogMutationError: LocalizedError {
    case emptyName
    case duplicateFolderName
    case invalidFolderName
    case invalidFolderID
    case invalidVariantIndex

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Theme name cannot be empty."
        case .duplicateFolderName:
            return "A folder with that name already exists."
        case .invalidFolderName:
            return "Folder name is invalid."
        case .invalidFolderID:
            return "Folder could not be found in the current catalog."
        case .invalidVariantIndex:
            return "Theme could not be found in the current catalog."
        }
    }
}

public enum ThemeMarkdownParser {
    public static func parse(_ markdown: String) -> ThemeCatalog {
        let lines = markdown.components(separatedBy: .newlines)
        var folders: [ThemeFolder] = []
        var issues: [ThemeParseIssue] = []
        var currentVariant: ThemeVariant?
        var currentFolderIDByVariant: [ThemeVariant: String] = [:]
        var builderByID: [String: ThemeFolderBuilder] = [:]
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if let variant = variantHeading(from: line) {
                currentVariant = variant
                currentFolderIDByVariant[variant] = nil
                index += 1
                continue
            }
            if line.hasPrefix("## "), let currentVariant {
                let name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if isReservedFolderName(name) {
                    issues.append(ThemeParseIssue(line: index + 1, message: "Folder name \(ThemeFolder.unfiledName) is reserved."))
                    currentFolderIDByVariant[currentVariant] = nil
                    index += 1
                    continue
                }
                let id = ThemeFolder.id(for: currentVariant, name: name)
                if builderByID[id] != nil {
                    issues.append(ThemeParseIssue(line: index + 1, message: "Duplicate folder \(name) in \(currentVariant.rawValue) themes."))
                    currentFolderIDByVariant[currentVariant] = nil
                    index += 1
                    continue
                }
                builderByID[id] = ThemeFolderBuilder(
                    variant: currentVariant,
                    name: name,
                    isImplicitUnfiled: false,
                    entries: []
                )
                folders.append(ThemeFolder(variant: currentVariant, name: name, entries: []))
                currentFolderIDByVariant[currentVariant] = id
                index += 1
                continue
            }
            guard line.hasPrefix("### ") else {
                index += 1
                continue
            }

            let name = String(line.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            let headerLine = index + 1
            index += 1

            var fields: [String: String] = [:]
            var fieldLine = headerLine
            while index < lines.count {
                let current = lines[index]
                if current.hasPrefix("#") {
                    break
                }
                defer { index += 1 }
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard let separator = trimmed.firstIndex(of: ":") else {
                    issues.append(ThemeParseIssue(line: index + 1, message: "Expected KEY: `value` in \(name)."))
                    continue
                }
                let rawKey = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let key = canonicalKey(rawKey)
                let valueStart = trimmed.index(after: separator)
                fields[key] = unwrappedValue(String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines))
                fieldLine = index + 1
            }

            do {
                let payload = try payload(from: fields)
                let entry = CustomThemeEntry(name: name, payload: payload)
                let folderID = currentFolderIDByVariant[payload.variant]
                let resolvedFolderID = folderID ?? ThemeFolder.unfiledID(for: payload.variant)
                if builderByID[resolvedFolderID] == nil {
                    builderByID[resolvedFolderID] = ThemeFolderBuilder(
                        variant: payload.variant,
                        name: ThemeFolder.unfiledName,
                        isImplicitUnfiled: true,
                        entries: []
                    )
                    folders.append(ThemeFolder(variant: payload.variant, name: ThemeFolder.unfiledName, isImplicitUnfiled: true, entries: []))
                }
                builderByID[resolvedFolderID]?.entries.append(entry)
            } catch {
                issues.append(ThemeParseIssue(line: fieldLine, message: "Invalid markdown for \(name): \(error.localizedDescription)"))
            }
        }

        let resolvedFolders = folders.compactMap { folder in
            builderByID[folder.id]?.folder
        }
        return ThemeCatalog(folders: resolvedFolders, issues: issues)
    }

    public static func serialize(_ catalog: ThemeCatalog) -> String {
        ThemeVariant.allCases.map { variant in
            serializeSection(variant: variant, folders: catalog.folders(for: variant))
        }
        .joined(separator: "\n\n") + "\n"
    }

    private static func serialize(_ entry: CustomThemeEntry) -> String {
        let payload = entry.payload
        let theme = payload.theme
        let contentFontLine = theme.fonts.content.map { "\ncontent-font: `\($0)`" } ?? ""
        return """
        ### \(entry.name)
        variant: `\(payload.variant.rawValue)`
        foreground: `\(theme.foreground)`
        background: `\(theme.background)`
        accent: `\(theme.accent)`
        diff-added: `\(theme.semanticColors.diffAdded)`
        diff-removed: `\(theme.semanticColors.diffRemoved)`
        contrast: `\(theme.contrast)`
        code-font: `\(theme.fonts.code)`\(fontFaceLines(theme.fonts.codeFace, prefix: "code-font"))
        ui-font: `\(theme.fonts.ui)`\(fontFaceLines(theme.fonts.uiFace, prefix: "ui-font"))\(contentFontLine)\(fontFaceLines(theme.fonts.contentFace, prefix: "content-font"))
        opaque-window: `\(theme.opaqueWindows)`
        theme-id: `\(payload.codeThemeId)`
        favorite: `\(payload.favorite)`
        """
    }

    private static func fontFaceLines(_ face: ThemeFontFace?, prefix: String) -> String {
        guard let face else { return "" }
        return "\n\(prefix)-family: `\(face.family)`\n\(prefix)-full-name: `\(face.fullName)`\n\(prefix)-postscript-name: `\(face.postscriptName)`"
    }

    private static func serializeSection(variant: ThemeVariant, folders: [ThemeFolder]) -> String {
        var parts = [variant == .light ? "# LIGHT THEMES" : "# DARK THEMES"]
        for folder in folders {
            if folder.isImplicitUnfiled {
                parts.append(contentsOf: folder.entries.map(serialize))
            } else {
                let themes = folder.entries.map(serialize).joined(separator: "\n\n")
                parts.append(themes.isEmpty ? "## \(folder.name)" : "## \(folder.name)\n\n\(themes)")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    public static func deletingEntry(
        in catalog: ThemeCatalog,
        variant: ThemeVariant,
        variantIndex: Int
    ) throws -> ThemeCatalog {
        try updateFolders(in: catalog, variant: variant) { folders in
            let location = try entryLocation(for: variantIndex, in: folders)
            var entries = folders[location.folderIndex].entries
            entries.remove(at: location.entryIndex)
            folders[location.folderIndex] = folders[location.folderIndex].replacingEntries(entries)
        }
    }

    public static func replacingEntry(
        in catalog: ThemeCatalog,
        variant: ThemeVariant,
        variantIndex: Int,
        with replacement: CustomThemeEntry
    ) throws -> ThemeCatalog {
        try updateFolders(in: catalog, variant: variant) { folders in
            let location = try entryLocation(for: variantIndex, in: folders)
            var entries = folders[location.folderIndex].entries
            entries[location.entryIndex] = replacement
            folders[location.folderIndex] = folders[location.folderIndex].replacingEntries(entries)
        }
    }

    public static func addingEntry(
        in catalog: ThemeCatalog,
        variant: ThemeVariant,
        entry: CustomThemeEntry,
        toFolderID folderID: String? = nil
    ) throws -> ThemeCatalog {
        try updateFolders(in: catalog, variant: variant) { folders in
            let destinationIndex = try destinationFolderIndex(
                in: &folders,
                variant: variant,
                folderID: folderID ?? ThemeFolder.unfiledID(for: variant)
            )
            let folder = folders[destinationIndex]
            folders[destinationIndex] = folder.replacingEntries(folder.entries + [entry])
        }
    }

    public static func creatingFolder(in catalog: ThemeCatalog, variant: ThemeVariant, name: String) throws -> ThemeCatalog {
        try updateFolders(in: catalog, variant: variant) { folders in
            let folderName = try validatedFolderName(name)
            guard !folders.contains(where: { !$0.isImplicitUnfiled && $0.name == folderName }) else {
                throw ThemeCatalogMutationError.duplicateFolderName
            }
            folders.append(ThemeFolder(variant: variant, name: folderName, entries: []))
        }
    }

    public static func renamingFolder(in catalog: ThemeCatalog, variant: ThemeVariant, folderID: String, name: String) throws -> ThemeCatalog {
        try updateFolders(in: catalog, variant: variant) { folders in
            let folderName = try validatedFolderName(name)
            guard !folders.contains(where: { $0.id != folderID && !$0.isImplicitUnfiled && $0.name == folderName }) else {
                throw ThemeCatalogMutationError.duplicateFolderName
            }
            guard let index = folders.firstIndex(where: { $0.id == folderID && !$0.isImplicitUnfiled }) else {
                throw ThemeCatalogMutationError.invalidFolderID
            }
            let folder = folders[index]
            folders[index] = ThemeFolder(variant: variant, name: folderName, entries: folder.entries)
        }
    }

    public static func deletingFolder(in catalog: ThemeCatalog, variant: ThemeVariant, folderID: String) throws -> ThemeCatalog {
        try updateFolders(in: catalog, variant: variant) { folders in
            guard let index = folders.firstIndex(where: { $0.id == folderID && !$0.isImplicitUnfiled }) else {
                throw ThemeCatalogMutationError.invalidFolderID
            }
            let deleted = folders.remove(at: index)
            guard !deleted.entries.isEmpty else { return }
            let unfiledIndex = ensureUnfiledFolder(in: &folders, variant: variant)
            let unfiled = folders[unfiledIndex]
            folders[unfiledIndex] = unfiled.replacingEntries(unfiled.entries + deleted.entries)
        }
    }

    public static func movingFolder(in catalog: ThemeCatalog, variant: ThemeVariant, folderID: String, toOffset destination: Int) throws -> ThemeCatalog {
        try updateFolders(in: catalog, variant: variant) { folders in
            let movableIndexes = folders.indices.filter { !folders[$0].isImplicitUnfiled }
            guard let sourceIndex = folders.firstIndex(where: { $0.id == folderID && !$0.isImplicitUnfiled }) else {
                throw ThemeCatalogMutationError.invalidFolderID
            }
            guard destination >= 0, destination <= movableIndexes.count else {
                throw ThemeCatalogMutationError.invalidFolderID
            }
            let sourceMovableIndex = movableIndexes.firstIndex(of: sourceIndex)!
            guard destination != sourceMovableIndex, destination != sourceMovableIndex + 1 else { return }
            var explicitFolders = folders.filter { !$0.isImplicitUnfiled }
            let moved = explicitFolders.remove(at: sourceMovableIndex)
            let adjustedDestination = destination > sourceMovableIndex ? destination - 1 : destination
            explicitFolders.insert(moved, at: adjustedDestination)
            let unfiled = folders.first { $0.isImplicitUnfiled }
            folders = (unfiled.map { [$0] } ?? []) + explicitFolders
        }
    }

    public static func movingEntry(
        in catalog: ThemeCatalog,
        variant: ThemeVariant,
        entryID: String,
        toFolderID destinationFolderID: String,
        insertionIndex: Int
    ) throws -> ThemeCatalog {
        try updateFolders(in: catalog, variant: variant) { folders in
            var movedEntry: CustomThemeEntry?
            var sourceFolderID: String?
            var sourceEntryIndex: Int?
            for folderIndex in folders.indices {
                guard let entryIndex = folders[folderIndex].entries.firstIndex(where: { $0.id == entryID }) else { continue }
                var entries = folders[folderIndex].entries
                movedEntry = entries.remove(at: entryIndex)
                sourceFolderID = folders[folderIndex].id
                sourceEntryIndex = entryIndex
                folders[folderIndex] = folders[folderIndex].replacingEntries(entries)
                break
            }
            guard let movedEntry else {
                throw ThemeCatalogMutationError.invalidVariantIndex
            }
            let destinationIndex = try destinationFolderIndex(
                in: &folders,
                variant: variant,
                folderID: destinationFolderID
            )
            var destinationEntries = folders[destinationIndex].entries
            var boundedInsertionIndex = min(max(insertionIndex, 0), destinationEntries.count)
            if sourceFolderID == destinationFolderID,
               let sourceEntryIndex,
               insertionIndex > sourceEntryIndex {
                boundedInsertionIndex = min(max(insertionIndex - 1, 0), destinationEntries.count)
            }
            destinationEntries.insert(movedEntry, at: boundedInsertionIndex)
            folders[destinationIndex] = folders[destinationIndex].replacingEntries(destinationEntries)
        }
    }

    private static func payload(from fields: [String: String]) throws -> ThemeFilePayload {
        let variant = try required("variant", in: fields)
        guard let themeVariant = ThemeVariant(rawValue: variant) else {
            throw ThemeMarkdownParserError.invalidValue("variant")
        }
        let favorite = try fields["favorite"].map(parseBool) ?? false
        return ThemeFilePayload(
            variant: themeVariant,
            codeThemeId: try required("codeThemeId", in: fields),
            favorite: favorite,
            theme: ChromeTheme(
                accent: try required("accent", in: fields),
                contrast: try parseInt(required("contrast", in: fields)),
                fonts: ThemeFonts(
                    code: fields["fontCode"] ?? "",
                    ui: fields["fontUI"] ?? "",
                    content: fields["content-font"],
                    contentFace: try fontFace(prefix: "content-font", in: fields),
                    codeFace: try fontFace(prefix: "code-font", in: fields),
                    uiFace: try fontFace(prefix: "ui-font", in: fields)
                ),
                foreground: try required("foreground", in: fields),
                opaqueWindows: try fields["opaqueWindows"].map(parseBool) ?? true,
                semanticColors: ThemeSemanticColors(
                    diffAdded: try required("diffAdded", in: fields),
                    diffRemoved: try required("diffRemoved", in: fields)
                ),
                background: try required("background", in: fields)
            )
        )
    }

    private static func fontFace(prefix: String, in fields: [String: String]) throws -> ThemeFontFace? {
        guard let family = fields["\(prefix)-family"] else { return nil }
        return ThemeFontFace(
            family: family,
            fullName: try required("\(prefix)-full-name", in: fields),
            postscriptName: try required("\(prefix)-postscript-name", in: fields)
        )
    }

    private static func variantHeading(from line: String) -> ThemeVariant? {
        switch line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "# LIGHT THEMES": return .light
        case "# DARK THEMES": return .dark
        default: return nil
        }
    }

    private static func validatedFolderName(_ name: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ThemeCatalogMutationError.invalidFolderName
        }
        guard !isReservedFolderName(trimmedName), !trimmedName.hasPrefix("#") else {
            throw ThemeCatalogMutationError.invalidFolderName
        }
        return trimmedName
    }

    private static func isReservedFolderName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(ThemeFolder.unfiledName) == .orderedSame
    }

    private static func updateFolders(
        in catalog: ThemeCatalog,
        variant: ThemeVariant,
        mutation: (inout [ThemeFolder]) throws -> Void
    ) throws -> ThemeCatalog {
        var folders = catalog.folders
        var variantFolders = normalizedFolders(catalog.folders(for: variant), variant: variant)
        try mutation(&variantFolders)
        let insertIndex = folders.firstIndex { $0.variant == variant } ?? folders.count
        folders.removeAll { $0.variant == variant }
        folders.insert(contentsOf: variantFolders, at: min(insertIndex, folders.count))
        return ThemeCatalog(folders: folders, issues: [])
    }

    private static func normalizedFolders(_ folders: [ThemeFolder], variant: ThemeVariant) -> [ThemeFolder] {
        let explicitFolders = folders.filter { !$0.isImplicitUnfiled }
        let unfiledEntries = folders.filter(\.isImplicitUnfiled).flatMap(\.entries)
        guard !unfiledEntries.isEmpty else { return explicitFolders }
        return [ThemeFolder(variant: variant, name: ThemeFolder.unfiledName, isImplicitUnfiled: true, entries: unfiledEntries)] + explicitFolders
    }

    private static func ensureUnfiledFolder(in folders: inout [ThemeFolder], variant: ThemeVariant) -> Int {
        if let index = folders.firstIndex(where: \.isImplicitUnfiled) {
            return index
        }
        folders.insert(ThemeFolder(variant: variant, name: ThemeFolder.unfiledName, isImplicitUnfiled: true, entries: []), at: 0)
        return 0
    }

    private static func entryLocation(
        for variantIndex: Int,
        in folders: [ThemeFolder]
    ) throws -> (folderIndex: Int, entryIndex: Int) {
        var remainingIndex = variantIndex
        for folderIndex in folders.indices {
            if remainingIndex < folders[folderIndex].entries.count {
                return (folderIndex, remainingIndex)
            }
            remainingIndex -= folders[folderIndex].entries.count
        }
        throw ThemeCatalogMutationError.invalidVariantIndex
    }

    private static func destinationFolderIndex(
        in folders: inout [ThemeFolder],
        variant: ThemeVariant,
        folderID: String
    ) throws -> Int {
        if folderID == ThemeFolder.unfiledID(for: variant) {
            return ensureUnfiledFolder(in: &folders, variant: variant)
        }
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            throw ThemeCatalogMutationError.invalidFolderID
        }
        return index
    }

    private static func required(_ key: String, in fields: [String: String]) throws -> String {
        guard let value = fields[key], !value.isEmpty else {
            throw ThemeMarkdownParserError.missingField(key)
        }
        return value
    }

    private static func parseInt(_ value: String) throws -> Int {
        guard let intValue = Int(value) else {
            throw ThemeMarkdownParserError.invalidValue(value)
        }
        return intValue
    }

    private static func parseBool(_ value: String) throws -> Bool {
        switch value.lowercased() {
        case "true": return true
        case "false": return false
        default: throw ThemeMarkdownParserError.invalidValue(value)
        }
    }

    private static func canonicalKey(_ key: String) -> String {
        switch key.lowercased() {
        case "variant": return "variant"
        case "theme-id": return "codeThemeId"
        case "favorite": return "favorite"
        case "foreground": return "foreground"
        case "background": return "background"
        case "accent": return "accent"
        case "contrast": return "contrast"
        case "code-font": return "fontCode"
        case "ui-font": return "fontUI"
        case "opaque-window": return "opaqueWindows"
        case "diff-added": return "diffAdded"
        case "diff-removed": return "diffRemoved"
        default: return key.lowercased()
        }
    }

    private static func unwrappedValue(_ value: String) -> String {
        guard value.hasPrefix("`"), value.hasSuffix("`"), value.count >= 2 else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}

private enum ThemeMarkdownParserError: LocalizedError {
    case missingField(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let field):
            return "Missing \(field)."
        case .invalidValue(let value):
            return "Invalid value \(value)."
        }
    }
}

private struct ThemeFolderBuilder {
    let variant: ThemeVariant
    let name: String
    let isImplicitUnfiled: Bool
    var entries: [CustomThemeEntry]

    var folder: ThemeFolder {
        ThemeFolder(variant: variant, name: name, isImplicitUnfiled: isImplicitUnfiled, entries: entries)
    }
}

private extension ThemeFolder {
    func replacingEntries(_ entries: [CustomThemeEntry]) -> ThemeFolder {
        ThemeFolder(variant: variant, name: name, isImplicitUnfiled: isImplicitUnfiled, entries: entries)
    }
}
