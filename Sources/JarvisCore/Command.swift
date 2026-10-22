import Foundation

public enum Command: Equatable, Sendable {
    case play, pause, next, previous, restart, quieter, louder, toggleShuffle, toggleTrackRepeat
    case volume(Int), seek(Int), shuffle(Bool), repeatAll(Bool), repeatTrack(Bool)
    case playSaved(String), nowPlaying, help, stopListening

    public var trackRepeatAction: TrackRepeatAction? {
        switch self {
        case .toggleTrackRepeat: return .toggle
        case .repeatTrack(let enabled): return .set(enabled)
        default: return nil
        }
    }
}

public enum TrackRepeatAction: Equatable, Sendable {
    case toggle, set(Bool)

    public func targetState(from current: Int) -> Int {
        switch self {
        case .toggle: return current == 2 ? 0 : 2
        case .set(let enabled): return enabled ? 2 : 0
        }
    }
}

public enum CommandParser {
    public static func normalize(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        return lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func parse(_ text: String) -> Command? {
        let text = normalize(text)
        switch text {
        case "продолжи", "продолжай", "играй", "включи музыку", "включи", "сними с паузы": return .play
        case "пауза", "стоп", "останови", "останови музыку", "выключи музыку": return .pause
        case "следующий", "следующая", "следующий трек", "дальше", "переключи", "next", "next track", "некст", "некст трек", "skip", "скип", "скипни": return .next
        case "предыдущий", "предыдущий трек", "предыдущая", "назад", "previous", "previous track", "превиус", "превиос", "back", "бэк": return .previous
        case "сначала", "трек сначала", "начни сначала": return .restart
        case "тише", "потише", "сделай тише": return .quieter
        case "громче", "погромче", "сделай громче": return .louder
        case "включи перемешивание": return .shuffle(true)
        case "перемешай", "randomise", "randomize", "рандомайз", "рандомайс", "рандомизируй", "шафл": return .toggleShuffle
        case "выключи перемешивание", "randomise off", "randomize off", "выключи рандом", "выключи рандомайз": return .shuffle(false)
        case "loop", "луп": return .toggleTrackRepeat
        case "включи loop", "включи луп", "повторяй трек", "повторяй песню", "зацикли трек": return .repeatTrack(true)
        case "loop off", "выключи loop", "выключи луп", "убери луп", "сними луп": return .repeatTrack(false)
        case "включи повтор": return .repeatAll(true)
        case "выключи повтор": return .repeatAll(false)
        case "что играет", "что сейчас играет", "что за трек", "какой трек", "назови трек", "название трека": return .nowPlaying
        case "daylist", "дейлист", "дэйлист", "дей лист", "дэй лист", "включи daylist", "включи дейлист", "включи дэйлист", "включи дей лист", "включи дэй лист", "включи плейлист daylist", "включи плейлист дейлист": return .playSaved("daylist")
        case "любимые треки", "включи любимые треки", "включи любимые", "включи мои любимые треки", "включи плейлист любимые треки", "liked songs": return .playSaved("любимые треки")
        case "помощь", "что ты умеешь": return .help
        case "перестань слушать", "заверши работу", "выход": return .stopListening
        default: break
        }
        if text.hasPrefix("громкость "), let value = number(String(text.dropFirst("громкость ".count))), (0...100).contains(value) {
            return .volume(value)
        }
        for (prefix, direction) in [("вперед на ", 1), ("назад на ", -1)] {
            if text.hasPrefix(prefix) {
                var amount = String(text.dropFirst(prefix.count))
                for suffix in [" секунд", " секунды", " секунду"] where amount.hasSuffix(suffix) {
                    amount = String(amount.dropLast(suffix.count))
                }
                if let seconds = number(amount), (1...120).contains(seconds) { return .seek(seconds * direction) }
            }
        }
        for prefix in ["включи плейлист ", "включи трек ", "включи подборку "] {
            if text.hasPrefix(prefix) {
                let name = String(text.dropFirst(prefix.count))
                return name.isEmpty ? nil : .playSaved(name)
            }
        }
        return nil
    }

    private static func number(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        let small = ["ноль": 0, "один": 1, "два": 2, "три": 3, "четыре": 4, "пять": 5, "шесть": 6,
                     "семь": 7, "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11,
                     "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14, "пятнадцать": 15,
                     "шестнадцать": 16, "семнадцать": 17, "восемнадцать": 18, "девятнадцать": 19,
                     "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50,
                     "шестьдесят": 60, "семьдесят": 70, "восемьдесят": 80, "девяносто": 90, "сто": 100]
        if let value = small[text] { return value }
        let words = text.split(separator: " ").map(String.init)
        if words.count == 2, let tens = small[words[0]], let units = small[words[1]],
           (20...90).contains(tens), tens % 10 == 0, (1...9).contains(units) { return tens + units }
        return nil
    }
}

/// Accept only whole wake words. A wake word spoken alone arms one command for 5 seconds.
public struct WakeGate {
    private let wakeWords: Set<String>
    private var armedUntil: Date?
    public private(set) var unrecognizedPhrase: String?
    public init(wakeWords: [String] = ["джарвис", "jarvis"]) {
        self.wakeWords = Set(wakeWords.map(CommandParser.normalize))
    }
    public mutating func consume(_ text: String, now: Date = Date()) -> Command? {
        unrecognizedPhrase = nil
        let words = CommandParser.normalize(text).split(separator: " ").map(String.init)
        let wake = words.lastIndex(where: { wakeWords.contains($0) })
        let payload: String
        if let wake {
            payload = words.dropFirst(wake + 1).joined(separator: " ")
            armedUntil = now.addingTimeInterval(5)
        } else if let until = armedUntil, now <= until {
            payload = words.joined(separator: " ")
        } else { return nil }
        guard let command = CommandParser.parse(payload) else {
            if !payload.isEmpty { unrecognizedPhrase = payload; armedUntil = nil }
            return nil
        }
        armedUntil = nil
        return command
    }
}
