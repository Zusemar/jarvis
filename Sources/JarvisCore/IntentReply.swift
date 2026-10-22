import Foundation

public enum IntentReply {
    /// Only a single existing music command may cross the model boundary.
    public static func command(from text: String) -> Command? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.count == 1, let value = object["command"] as? String,
              let command = CommandParser.parse(value) else { return nil }
        if case .playSaved(let name) = command, !["daylist", "любимые треки"].contains(name) { return nil }
        return command
    }
}
