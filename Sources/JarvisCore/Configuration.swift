import Foundation

public struct Configuration: Codable, Sendable {
    public var locale = "ru-RU"
    public var wakeWords = ["джарвис", "jarvis"]
    public var maximumVolume = 65
    public var volumeStep = 5
    public var recognitionMode = "automatic"
    public var spokenFeedback = false
    public var savedMusic: [String: String] = [:]
    public init() {}

    public func validated() throws -> Configuration {
        guard (1...100).contains(maximumVolume), (1...20).contains(volumeStep),
              ["automatic", "onDevice"].contains(recognitionMode),
              !wakeWords.isEmpty, wakeWords.allSatisfy({ !$0.isEmpty && CommandParser.normalize($0).split(separator: " ").count == 1 }),
              !locale.isEmpty else { throw ConfigError.invalid }
        var result = self
        result.savedMusic = [:]
        for (name, value) in savedMusic {
            let key = CommandParser.normalize(name)
            guard !key.isEmpty, result.savedMusic[key] == nil, let uri = Self.spotifyURI(value) else { throw ConfigError.invalid }
            result.savedMusic[key] = uri
        }
        return result
    }

    /// Keep only Spotify IDs; never interpolate arbitrary configuration text into AppleScript.
    public static func spotifyURI(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var kind: String
        var id: String
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0] == "spotify" {
            kind = String(parts[1]); id = String(parts[2])
        } else if let url = URL(string: value), url.scheme == "https", url.host == "open.spotify.com" {
            let path = url.path.split(separator: "/")
            guard path.count == 2 else { return nil }
            kind = String(path[0]); id = String(path[1])
        } else { return nil }
        guard ["track", "playlist", "album"].contains(kind), id.count == 22,
              id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").contains($0) }) else { return nil }
        return "spotify:\(kind):\(id)"
    }
}

public enum ConfigError: LocalizedError {
    case invalid
    public var errorDescription: String? { "Проверьте настройки Jarvis: громкость 1–100, шаг 1–20, режим automatic/onDevice и ссылки Spotify." }
}
