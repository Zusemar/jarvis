import Foundation

public struct Configuration: Codable, Sendable {
    public var locale = "ru-RU"
    public var wakeWords = ["джарвис", "jarvis"]
    public var maximumVolume = 100
    public var volumeStep = 5
    public var recognitionMode = "automatic"
    public var spokenFeedback = false
    public var voiceIdentifier = ""
    public var responseLanguage = "ru"
    public var speechRate = 0.5
    public var speechEngine = "apple"
    public var kokoroVoice = "af_heart"
    public var kokoroSpeed = 1.0
    public var pronunciations = ["A$AP Rocky": "Ay-sap Rocky", "A$AP": "Ay-sap"]
    public var intentEngine = "rules"
    public var savedMusic: [String: String] = [:]
    public init() {}

    public func validated() throws -> Configuration {
        guard (1...100).contains(maximumVolume), (0.25...0.65).contains(speechRate), (1...20).contains(volumeStep),
              ["automatic", "onDevice"].contains(recognitionMode), ["ru", "en"].contains(responseLanguage),
              ["apple", "kokoro"].contains(speechEngine), (0.5...2.0).contains(kokoroSpeed),
              ["rules", "openclaw"].contains(intentEngine),
              Self.kokoroVoices.contains(kokoroVoice), (speechEngine != "kokoro" || responseLanguage == "en"),
              pronunciations.count <= 100, pronunciations.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 100 && !$0.value.isEmpty && $0.value.count <= 200 }),
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

    public static let kokoroVoices: Set<String> = [
        "af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky", "af_alloy", "af_aoede", "af_jessica", "af_kore", "af_nova", "af_river",
        "am_adam", "am_michael", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_onyx", "am_puck", "am_santa",
        "bf_alice", "bf_emma", "bf_isabella", "bf_lily", "bm_daniel", "bm_fable", "bm_george", "bm_lewis"
    ]

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
