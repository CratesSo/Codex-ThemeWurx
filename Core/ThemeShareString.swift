import Foundation

public enum ThemeShareString {
    public static let prefix = "codex-theme-v1:"

    public static func encode(_ payload: ThemeFilePayload) throws -> String {
        guard let theme = payload.theme.codexPatchObject() else {
            throw EncodingError.invalidValue(
                payload.theme,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Theme cannot be represented as a Codex share payload."
                )
            )
        }
        let object: [String: Any] = [
            "codeThemeId": payload.codeThemeId,
            "favorite": payload.favorite,
            "theme": theme,
            "variant": payload.variant.rawValue
        ]
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return prefix + String(decoding: data, as: UTF8.self)
    }
}
