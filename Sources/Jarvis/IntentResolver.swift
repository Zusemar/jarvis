import Foundation
import JarvisCore

final class IntentResolver {
    private var process: Process?
    private(set) var isBusy = false
    private var generation = 0

    func resolve(_ phrase: String, completion: @escaping (Command?) -> Void) {
        guard !isBusy else { return }
        isBusy = true
        generation += 1
        let current = generation
        let process = Process()
        self.process = process
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/openclaw")
        process.arguments = ["--log-level", "silent", "--no-color", "agent", "--local", "--agent", "jarvis", "--session-id", UUID().uuidString,
                             "--thinking", "off", "--timeout", "20", "--message",
                             "Classify this Spotify request as one JSON object, for example {\"command\":\"предыдущий\"}. Return {\"command\":null} if unsupported. No tools or explanations. Request: " + phrase, "--json"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        // OpenClaw versions may write their JSON result to either stream.
        process.standardError = pipe
        // This dedicated agent is stateless. Never touch another agent's history.
        let sessions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".openclaw/agents/jarvis/sessions")
        try? FileManager.default.removeItem(at: sessions)
        do { try process.run() }
        catch { isBusy = false; self.process = nil; completion(nil); return }
        DispatchQueue.global(qos: .utility).async {
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            var command: Command?
            let json = output.firstIndex(of: 123).map { Data(output[$0...]) } ?? output
            if process.terminationStatus == 0,
               let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
               let payloads = object["payloads"] as? [[String: Any]], payloads.count == 1,
               let text = payloads.first?["text"] as? String {
                command = IntentReply.command(from: text)
            }
            let result = command
            DispatchQueue.main.async {
                guard self.generation == current else { return }
                try? FileManager.default.removeItem(at: sessions)
                self.isBusy = false; self.process = nil
                completion(result)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.generation == current, self.isBusy else { return }
            self.generation += 1
            if process.isRunning { process.terminate() }
            self.isBusy = false; self.process = nil
            completion(nil)
        }
    }

    func stop() {
        generation += 1
        if process?.isRunning == true { process?.terminate() }
        isBusy = false
    }
}
