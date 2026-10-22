import AppKit
import AVFoundation
import Speech
import ApplicationServices
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
    private var healthTimer: Timer?
    private var kokoro: KokoroSpeaker?

    init(configuration: Configuration, startupError: String? = nil) {
        self.configuration = configuration
        gate = WakeGate(wakeWords: configuration.wakeWords)
        self.startupError = startupError
        super.init()
        synthesizer.delegate = self
        if configuration.speechEngine == "kokoro" { kokoro = KokoroSpeaker(configuration: configuration) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let startupError { fatal(startupError); return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.zusemar.jarvis")
        if others.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        writeHealth()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.writeHealth() }
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
            _ = try SpotifyController.execute("with timeout of 5 seconds\ntell application id \"com.spotify.client\" to get version\nend timeout")
            let mode = listener.usesOnDeviceRecognition ? "локальное" : "через сервис Apple"
            log.info("Распознавание: \(mode, privacy: .public). Jarvis готов.")
            if configuration.recognitionMode == "onDevice", !listener.usesOnDeviceRecognition {
                fatal("На этом Mac локальное распознавание выбранного языка недоступно. Измените recognitionMode на automatic в настройках.")
                return
            }
            let greeting = message(listener.usesOnDeviceRecognition ? .readyLocal : .readyNetwork)
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
            Settings.markStopped()
            speak(message(.goodbye)) { NSApp.terminate(nil) }
            return
        }
        if command == .help {
            speak(message(.help)) { [weak self] in self?.resetAndListen() }
            return
        }
        if let action = command.trackRepeatAction {
            SpotifyController.setTrackRepeat(action) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success: self.resetAndListen()
                case .failure(let error):
                    self.speak(self.spokenError(error)) { [weak self] in self?.resetAndListen() }
                }
            }
            return
        }
        guard let source = SpotifyScript.source(for: command, configuration: configuration) else {
            speak(message(.missingMusic)) { [weak self] in self?.resetAndListen() }
            return
        }
        do {
            let result = try SpotifyController.execute(source)
            if command == .nowPlaying {
                // Lower the music briefly so the title is audible over studio speakers.
                let originalVolume = try SpotifyController.volume()
                let ducked = min(originalVolume ?? 15, 15)
                try? SpotifyController.setVolume(ducked)
                let title = result == VoiceMessage.nothingPlaying.text(language: "ru") ? message(.nothingPlaying) : result ?? message(.nothingPlaying)
                speak(title) { [weak self] in
                    if let originalVolume, (try? SpotifyController.volume()) == ducked {
                        try? SpotifyController.setVolume(originalVolume)
                    }
                    self?.resetAndListen()
                }
            } else if configuration.spokenFeedback {
                speak(message(.done)) { [weak self] in self?.resetAndListen() }
            } else { resetAndListen() }
        } catch {
            log.error("Ошибка Spotify: \(error.localizedDescription, privacy: .public)")
            speak(spokenError(error)) { [weak self] in self?.resetAndListen() }
        }
    }

    private func message(_ message: VoiceMessage) -> String {
        message.text(language: configuration.responseLanguage)
    }

    private func writeHealth() {
        let status: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "appPath": Bundle.main.bundlePath,
            "updatedAt": Date().timeIntervalSince1970,
            "accessibility": AXIsProcessTrusted(),
            "microphone": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
            "speechRecognition": SFSpeechRecognizer.authorizationStatus().rawValue,
            "speechEngine": configuration.speechEngine,
            "voice": configuration.speechEngine == "kokoro" ? configuration.kokoroVoice : configuration.voiceIdentifier,
            "kokoroCompletedUtterances": kokoro?.completedUtterances ?? 0,
            "kokoroLastError": kokoro?.lastError ?? ""
        ]
        let url = Settings.defaultURL.deletingLastPathComponent().appendingPathComponent("runtime.json")
        if let data = try? JSONSerialization.data(withJSONObject: status, options: .sortedKeys) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func spokenError(_ error: Error) -> String {
        if let spotifyError = error as? SpotifyError { return spotifyError.spokenDescription(language: configuration.responseLanguage) }
        return configuration.responseLanguage == "en" ? message(.spotifyFailure) : "Не удалось выполнить команду Spotify. " + error.localizedDescription
    }

    private func resetAndListen() {
        guard !synthesizer.isSpeaking, kokoro?.isSpeaking != true else { return }
        pending?.cancel()
        lastTranscript = ""
        consumedTranscript = ""
        do { try listener?.start() }
        catch { fatal(error.localizedDescription) }
    }

    private func speak(_ text: String, completion: @escaping () -> Void) {
        listener?.stop()
        pending?.cancel()
        if let kokoro {
            kokoro.speak(text, completion: completion)
            return
        }
        afterSpeech = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: configuration.voiceIdentifier)
            ?? AVSpeechSynthesisVoice(language: configuration.responseLanguage == "en" ? "en-GB" : configuration.locale)
        utterance.rate = Float(configuration.speechRate)
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let completion = afterSpeech; afterSpeech = nil
        // Let the last syllable leave the speakers before opening the microphone again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion?() }
    }

    private func fatal(_ message: String) {
        Settings.markStopped()
        log.error("\(message, privacy: .public)")
        fputs("Jarvis: \(message)\n", stderr)
        speak(configuration.responseLanguage == "en" ? self.message(.startupFailure) : message) { NSApp.terminate(nil) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        healthTimer?.invalidate()
        kokoro?.stop()
        pending?.cancel()
        listener?.stop()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
