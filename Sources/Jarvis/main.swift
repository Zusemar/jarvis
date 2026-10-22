import AppKit
import AVFoundation
import Speech
import JarvisCore

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") {
    print("""
    Jarvis — голосовое управление Spotify на Mac без окон и сервера.
    Запуск: откройте Jarvis.app. Команда: «Джарвис, следующий».
    --list-voices           Показать голоса: --list-voices ru / en / all.
    --check                 Проверить разрешения, язык и наличие Spotify; не слушать микрофон.
    --execute 'фраза'       Выполнить команду без микрофона (для проверки).
    --dry-run 'фраза'       Показать команду; не управлять Spotify и не слушать микрофон.
    --config /path/to.json  Использовать свой файл настроек.
    --help                  Эта справка.
    """)
    exit(0)
}

let configURL: URL
if let index = args.firstIndex(of: "--config") {
    guard args.indices.contains(index + 1) else { fputs("После --config нужен путь.\n", stderr); exit(2) }
    configURL = URL(fileURLWithPath: args[index + 1])
} else { configURL = Settings.defaultURL }

if let index = args.firstIndex(of: "--list-voices") {
    let prefix = args.indices.contains(index + 1) && !args[index + 1].hasPrefix("--") ? args[index + 1] : "ru"
    let voices = AVSpeechSynthesisVoice.speechVoices().filter { prefix == "all" || $0.language.hasPrefix(prefix) }
    for voice in voices {
        let gender = voice.gender == .male ? "мужской" : voice.gender == .female ? "женский" : "нейтральный"
        let quality = voice.quality == .default ? "standard" : voice.quality == .enhanced ? "enhanced" : "premium"
        print("\(voice.name) | \(gender) | \(voice.language) | \(quality) | \(voice.identifier)")
    }
    if voices.isEmpty { print("Голосов для \(prefix) нет. Загрузите голос в настройках озвучивания macOS.") }
    exit(0)
}

if args.contains("--check") {
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    print("Spotify установлен: \(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil)")
    print("Микрофон: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (3 = разрешено)")
    print("Распознавание речи: \(SFSpeechRecognizer.authorizationStatus().rawValue) (3 = разрешено)")
    print("Локальное распознавание ru-RU: \(recognizer?.supportsOnDeviceRecognition ?? false)")
    print("Настройки: \(configURL.path)")
    exit(0)
}

var configuration = Configuration()
var configurationError: String?
do { configuration = try Settings.load(from: configURL) }
catch { configurationError = "Не удалось прочитать \(configURL.path). \(error.localizedDescription)" }

if let index = args.firstIndex(of: "--dry-run") {
    if let configurationError { fputs("\(configurationError)\n", stderr); exit(2) }
    guard args.indices.contains(index + 1) else { fputs("После --dry-run нужна фраза.\n", stderr); exit(2) }
    var gate = WakeGate(wakeWords: configuration.wakeWords)
    guard let command = gate.consume(args[index + 1]) else { print("Команда не распознана. Начните с «Джарвис»."); exit(1) }
    print("Распознано: \(command)")
    print(SpotifyScript.source(for: command, configuration: configuration) ?? "Локальная команда или несохраненная музыка.")
    exit(0)
}

if let index = args.firstIndex(of: "--execute") {
    if let configurationError { fputs("\(configurationError)\n", stderr); exit(2) }
    guard args.indices.contains(index + 1) else { fputs("После --execute нужна фраза.\n", stderr); exit(2) }
    var gate = WakeGate(wakeWords: configuration.wakeWords)
    guard let command = gate.consume(args[index + 1]) else { fputs("Команда не распознана.\n", stderr); exit(1) }
    if let action = command.trackRepeatAction {
        SpotifyController.setTrackRepeat(action) { result in
            switch result {
            case .success: print("Режим повтора одного трека обновлен"); exit(0)
            case .failure(let error): fputs("\(error.localizedDescription)\n", stderr); exit(1)
            }
        }
        RunLoop.main.run()
    } else if let source = SpotifyScript.source(for: command, configuration: configuration) {
        do { print(try SpotifyController.execute(source) ?? "Готово") }
        catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    } else { fputs("Нет сохраненной ссылки или команда требует голосового режима.\n", stderr); exit(1) }
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let assistant = Assistant(configuration: configuration, startupError: configurationError)
application.delegate = assistant
application.run()
