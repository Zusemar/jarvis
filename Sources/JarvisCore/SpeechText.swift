import Foundation

public enum SpeechText {
    public static func prepare(_ text: String, configuration: Configuration) -> String {
        guard configuration.responseLanguage == "en" else { return text }
        var result = text
        for key in configuration.pronunciations.keys.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: key, with: configuration.pronunciations[key]!, options: .caseInsensitive)
        }
        if text.range(of: "A$AP Rocky", options: .caseInsensitive) != nil {
            result = result.replacingOccurrences(of: "(?i)\\bLVL\\b", with: "Level", options: .regularExpression)
        }
        return result
    }
}
