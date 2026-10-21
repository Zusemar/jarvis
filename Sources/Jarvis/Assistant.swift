import AppKit
import AVFoundation
import Speech
import JarvisCore

final class Assistant: NSObject, NSApplicationDelegate, AVSpeechSynthesizerDelegate {
    private var configuration: Configuration
    private var gate: WakeGate
    private var listener: VoiceListener?
    private var pending: DispatchWorkItem?
    private var lastTranscript = ""
    private var consumedTranscript = ""
    private var synthesizer = AVSpeechSynthesizer()
    private var afterSpeech: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var startupError: String?

    init(configuration: Configuration, startupError: String? = nil) {
        self.configuration = configuration
        gate = WakeGate(wakeWords: configuration.wakeWords)
        self.startupError = startupError
        super.init()
        synthesizer.delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let startupError { fatal(startupError); return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.zusemar.jarvis")
        if others.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil else {
            fatal("Установите настольное приложение Spotify на Mac и войдите в свой аккаунт.")
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pending?.cancel(); self?.listener?.stop()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resetAndListen()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            self?.resetAndListen()
        })
        authorize()
    }

    private func authorize() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            guard allowed else {
                DispatchQueue.main.async { self?.fatal("Разрешите микрофон для Jarvis в настройках конфиденциальности macOS, затем запустите Jarvis снова.") }
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard status == .authorized else {
                        self.fatal("Разрешите распознавание речи для Jarvis в настройках конфиденциальности macOS и запустите приложение снова.")
                        return
                    }
                    self.boot()
                }
            }
        }
    }

    private func boot() {
        do {
            let listener = try VoiceListener(configuration: configuration)
            listener.onText = { [weak self] text, final in self?.receive(text, final: final) }
            listener.onFailure = { message in log.error("\(message, privacy: .public)") }
            self.listener = listener
            // Request Spotify Automation permission now, before any commands are spoken.
            _ = try executeScript("with timeout of 5 seconds\ntell application id \"com.spotify.client\" to get version\nend timeout")
            let mode = listener.usesOnDeviceRecognition ? "локальное" : "через сервис Apple"
            log.info("Распознавание: \(mode, privacy: .public). Jarvis готов.")
            if configuration.recognitionMode == "onDevice", !listener.usesOnDeviceRecognition {
                fatal("На этом Mac локальное распознавание выбранного языка недоступно. Измените recognitionMode на automatic в настройках.")
                return
            }
            let greeting = listener.usesOnDeviceRecognition
                ? "Джарвис готов. Скажите: Джарвис, помощь."
                : "Джарвис готов. Распознавание через сервис Apple. Скажите: Джарвис, помощь."
            speak(greeting) { [weak self] in self?.resetAndListen() }
        } catch { fatal(error.localizedDescription) }
    }

    private func receive(_ text: String, final: Bool) {
        let normalized = CommandParser.normalize(text)
        if normalized != lastTranscript {
            lastTranscript = normalized
            pending?.cancel()
            // Wait for a stable phrase so «громкость пятьдесят» isn't executed as «пять».
            let work = DispatchWorkItem { [weak self] in self?.process(normalized) }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
        }
        if final {
            pending?.cancel()
            process(normalized)
            lastTranscript = ""
            consumedTranscript = ""
        }
    }

    private func process(_ text: String) {
        guard text != consumedTranscript else { return }
        consumedTranscript = text
        guard let command = gate.consume(text) else { return }
        pending?.cancel()
        listener?.stop()
        if command == .stopListening {
            speak("Джарвис завершает работу.") { NSApp.terminate(nil) }
            return
        }
        if command == .help {
            speak("Скажите Джарвис и команду: пауза, продолжи, следующий, предыдущий, тише, громче, громкость сорок, сначала, вперед на десять секунд, что играет. Для выхода: Джарвис, перестань слушать.") { [weak self] in self?.resetAndListen() }
            return
        }
        guard let source = SpotifyScript.source(for: command, configuration: configuration) else {
            speak("Сначала сохраните ссылку на этот трек или плейлист в настройках Джарвиса.") { [weak self] in self?.resetAndListen() }
            return
        }
        do {
            let result = try executeScript(source)
            if command == .nowPlaying {
                speak(result ?? "Сейчас ничего не играет") { [weak self] in self?.resetAndListen() }
            } else if configuration.spokenFeedback {
                speak("Готово") { [weak self] in self?.resetAndListen() }
            } else { resetAndListen() }
        } catch {
            log.error("Ошибка Spotify: \(error.localizedDescription, privacy: .public)")
            speak("Не удалось выполнить команду. Проверьте Spotify и разрешение Автоматизация для Джарвиса.") { [weak self] in self?.resetAndListen() }
        }
    }

    private func executeScript(_ source: String) throws -> String? {
        var details: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&details)
        if let details {
            throw NSError(domain: "Jarvis.Spotify", code: details[NSAppleScript.errorNumber] as? Int ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: details[NSAppleScript.errorMessage] as? String ?? "Spotify недоступен"])
        }
        guard script != nil else { throw ListenerError.unavailable("Не удалось создать команду Spotify.") }
        return result?.stringValue
    }

    private func resetAndListen() {
        guard !synthesizer.isSpeaking else { return }
        pending?.cancel()
        lastTranscript = ""
        consumedTranscript = ""
        do { try listener?.start() }
        catch { fatal(error.localizedDescription) }
    }

    private func speak(_ text: String, completion: @escaping () -> Void) {
        listener?.stop()
        pending?.cancel()
        afterSpeech = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: configuration.locale)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let completion = afterSpeech; afterSpeech = nil
        // Let the last syllable leave the speakers before opening the microphone again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion?() }
    }

    private func fatal(_ message: String) {
        log.error("\(message, privacy: .public)")
        fputs("Jarvis: \(message)\n", stderr)
        speak(message) { NSApp.terminate(nil) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pending?.cancel()
        listener?.stop()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
