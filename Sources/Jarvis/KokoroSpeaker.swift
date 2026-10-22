import AVFoundation
import Foundation
import JarvisCore

/// A persistent local worker keeps the neural model loaded between commands.
/// It communicates over anonymous pipes; no web server or network is involved.
final class KokoroSpeaker: NSObject, AVAudioPlayerDelegate {
    private let configuration: Configuration
    private let queue = DispatchQueue(label: "com.zusemar.jarvis.kokoro")
    private var worker: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?
    private var timeout: DispatchWorkItem?
    private var generation = 0
    private(set) var isSpeaking = false
    private(set) var completedUtterances = 0
    private(set) var lastError = ""

    init(configuration: Configuration) { self.configuration = configuration }

    func speak(_ text: String, completion: @escaping () -> Void) {
        guard !isSpeaking else { return }
        isSpeaking = true
        lastError = ""
        self.completion = completion
        generation += 1
        let requestGeneration = generation
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == requestGeneration else { return }
            self.worker?.terminate()
            self.finish(error: "Kokoro timed out")
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.startWorkerIfNeeded()
                let request: [String: Any] = ["text": text, "voice": self.configuration.kokoroVoice,
                                              "speed": self.configuration.kokoroSpeed]
                var data = try JSONSerialization.data(withJSONObject: request)
                data.append(10)
                guard let input = self.input, let output = self.output else { throw KokoroError.unavailable }
                try input.write(contentsOf: data)
                var response = Data()
                while response.count < 8192 {
                    guard let byte = try output.read(upToCount: 1), !byte.isEmpty else { throw KokoroError.unavailable }
                    if byte.first == 10 { break }
                    response.append(byte)
                }
                guard let object = try JSONSerialization.jsonObject(with: response) as? [String: String],
                      let path = object["path"] else { throw KokoroError.unavailable }
                let url = URL(fileURLWithPath: path)
                defer { try? FileManager.default.removeItem(at: url) }
                let audio = try Data(contentsOf: url)
                DispatchQueue.main.async {
                    guard self.generation == requestGeneration, self.isSpeaking else { return }
                    do {
                        self.player = try AVAudioPlayer(data: audio)
                        self.player?.delegate = self
                        guard self.player?.play() == true else { throw KokoroError.unavailable }
                    } catch { self.finish(error: "Kokoro audio playback failed") }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.generation == requestGeneration, self.isSpeaking else { return }
                    self.finish(error: "Kokoro synthesis failed; check the local model installation")
                }
            }
        }
    }

    private func startWorkerIfNeeded() throws {
        if worker?.isRunning == true { return }
        let root = Settings.defaultURL.deletingLastPathComponent().appendingPathComponent("Kokoro")
        guard let script = Bundle.main.url(forResource: "kokoro_worker", withExtension: "py") else { throw KokoroError.unavailable }
        let process = Process()
        process.executableURL = root.appendingPathComponent("venv/bin/python")
        process.arguments = ["-u", script.path, root.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HUB_OFFLINE"] = "1"
        environment["OMP_NUM_THREADS"] = "2"
        process.environment = environment
        let requestPipe = Pipe(), responsePipe = Pipe()
        process.standardInput = requestPipe
        process.standardOutput = responsePipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        worker = process
        input = requestPipe.fileHandleForWriting
        output = responsePipe.fileHandleForReading
    }

    private func finish(error: String? = nil) {
        guard isSpeaking else { return }
        if let error { lastError = error; log.error("\(error, privacy: .public)") }
        else { completedUtterances += 1 }
        timeout?.cancel(); timeout = nil
        isSpeaking = false
        player = nil
        let completed = completion; completion = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completed?() }
    }

    func stop() {
        generation += 1
        timeout?.cancel()
        player?.stop(); player = nil
        completion = nil
        isSpeaking = false
        try? input?.close()
        if worker?.isRunning == true { worker?.terminate() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish(error: flag ? nil : "Kokoro audio playback failed")
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finish(error: "Kokoro audio decoding failed")
    }
}

private enum KokoroError: Error { case unavailable }
