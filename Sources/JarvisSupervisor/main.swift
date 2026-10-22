import AppKit
import Darwin

// launchd supervises this helper. LaunchServices launches the actual app so that
// macOS attributes microphone, Automation and Accessibility access to Jarvis.app.
let identifier = "com.zusemar.jarvis"
let files = FileManager.default
let support = files.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jarvis")
let stopped = support.appendingPathComponent("stopped")
let appURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

func running() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
}

if CommandLine.arguments.contains("--terminate") {
    for app in running() { app.terminate() }
    let deadline = Date().addingTimeInterval(5)
    while !running().isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    if !running().isEmpty { fputs("Jarvis did not terminate.\n", stderr); exit(1) }
    exit(0)
}
if CommandLine.arguments.contains("--test-crash") {
    guard let app = running().first else { fputs("Jarvis is not running.\n", stderr); exit(1) }
    print(app.processIdentifier)
    exit(kill(app.processIdentifier, SIGKILL) == 0 ? 0 : 1)
}

try? files.createDirectory(at: support, withIntermediateDirectories: true)
try? files.removeItem(at: stopped)
var child: NSRunningApplication?
var opening = false
var retryAfter = Date.distantPast
var stopping = false

func stop() {
    guard !stopping else { return }
    stopping = true
    for app in running() { app.terminate() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
}
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
term.setEventHandler(handler: stop)
interrupt.setEventHandler(handler: stop)
term.resume(); interrupt.resume()

let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    guard !stopping else { return }
    if let current = child {
        guard current.isTerminated else { return }
        child = nil
        if files.fileExists(atPath: stopped.path) { exit(0) }
        retryAfter = Date().addingTimeInterval(30)
        fputs("Jarvis exited unexpectedly; restarting in 30 seconds.\n", stderr)
    }
    guard !opening, Date() >= retryAfter else { return }
    if let current = running().first { child = current; return }
    opening = true
    let options = NSWorkspace.OpenConfiguration()
    options.activates = false
    options.hides = true
    NSWorkspace.shared.openApplication(at: appURL, configuration: options) { app, error in
        DispatchQueue.main.async {
            opening = false
            if stopping { app?.terminate(); return }
            if let error { fputs("LaunchServices: \(error.localizedDescription)\n", stderr) }
            child = app
            retryAfter = Date().addingTimeInterval(30)
        }
    }
}
timer.fire()
RunLoop.main.run()
