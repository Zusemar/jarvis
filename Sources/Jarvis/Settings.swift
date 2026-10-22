import Foundation
import JarvisCore
import OSLog

let log = Logger(subsystem: "com.zusemar.jarvis", category: "assistant")

struct Settings {
    static func markStopped() {
        let url = defaultURL.deletingLastPathComponent().appendingPathComponent("stopped")
        try? Data().write(to: url, options: .atomic)
    }
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Jarvis/config.json")
    }

    static func load(from url: URL) throws -> Configuration {
        if !FileManager.default.fileExists(atPath: url.path) {
            let config = Configuration()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(config).write(to: url, options: .atomic)
            return config
        }
        // Allow partial settings: omitted keys keep their documented defaults.
        let encoder = JSONEncoder()
        let defaults = try JSONSerialization.jsonObject(with: encoder.encode(Configuration())) as! [String: Any]
        guard let supplied = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw ConfigError.invalid
        }
        guard Set(supplied.keys).isSubset(of: Set(defaults.keys)) else { throw ConfigError.invalid }
        let merged = defaults.merging(supplied) { _, new in new }
        return try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: merged)).validated()
    }
}
