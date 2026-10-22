import AVFoundation
import Speech
import Foundation
import JarvisCore

/// All lifecycle changes run on the main queue. The audio tap owns its request, never mutable app state.
final class VoiceListener {
    var onText: ((String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    private let configuration: Configuration
    private let recognizer: SFSpeechRecognizer
    private var engine: AVAudioEngine?
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var timer: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var generation = 0
    private var running = false
    private var failures = 0
    private var startedAt: Date?

    init(configuration: Configuration) throws {
        self.configuration = configuration
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: configuration.locale)) else {
            throw ListenerError.unavailable("Русское распознавание недоступно. Проверьте язык в настройках Jarvis.")
        }
        self.recognizer = recognizer
    }

    var usesOnDeviceRecognition: Bool { recognizer.supportsOnDeviceRecognition }

    func start() throws {
        running = true
        try begin()
    }

    func stop() {
        running = false
        retry?.cancel(); retry = nil
        tearDown()
    }

    private func tearDown() {
        generation += 1
        timer?.cancel(); timer = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        startedAt = nil
    }

    private func begin() throws {
        tearDown()
        guard running else { return }
        guard recognizer.isAvailable else { scheduleRetry(); return }
        if configuration.recognitionMode == "onDevice", !recognizer.supportsOnDeviceRecognition {
            running = false
            throw ListenerError.unavailable("Локальное распознавание этого языка недоступно. В config.json выберите automatic или установите доступные языковые данные macOS.")
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            scheduleRetry()
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.contextualStrings = configuration.wakeWords + ["пауза", "следующий трек", "некст", "next", "скип", "previous", "предыдущий", "громкость сто", "продолжи", "что играет", "что сейчас играет", "луп", "loop", "randomise", "рандомайз", "дейлист", "daylist", "любимые треки"]
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        self.engine = engine
        self.request = request
        let current = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.generation == current, self.running else { return }
                if let result {
                    self.onText?(result.bestTranscription.formattedString, result.isFinal)
                    // Processing a command may have stopped this generation already.
                    guard self.generation == current, self.running else { return }
                }
                if error != nil {
                    self.scheduleRetry()
                } else if result?.isFinal == true {
                    self.failures = 0
                    self.restartAfter(0.15)
                }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            startedAt = Date()
        } catch {
            // A disconnected microphone should recover when an input becomes available.
            scheduleRetry()
            return
        }
        // Apple's recognizer may stop after about a minute. Rotate before that limit.
        let rotate = DispatchWorkItem { [weak self] in self?.restartAfter(0.1) }
        timer = rotate
        DispatchQueue.main.asyncAfter(deadline: .now() + 50, execute: rotate)
    }

    private func scheduleRetry() {
        if let startedAt, Date().timeIntervalSince(startedAt) > 15 { failures = 0 }
        failures += 1
        if failures == 3 || failures % 10 == 0 {
            onFailure?("Распознавание временно недоступно. Проверьте микрофон и интернет; Jarvis повторит подключение.")
        }
        restartAfter(min(30, pow(2, Double(min(failures, 5)))))
    }

    private func restartAfter(_ delay: TimeInterval) {
        tearDown()
        retry?.cancel()
        guard running else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            do { try self.begin() }
            catch { self.onFailure?(error.localizedDescription) }
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

enum ListenerError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let message) = self { return message }; return nil }
}
