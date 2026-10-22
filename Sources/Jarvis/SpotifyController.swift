import AppKit
import ApplicationServices
import JarvisCore

struct SpotifyController {
    static func accessibilityStatus() -> Int? {
        guard let spotify = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first else { return nil }
        let app = AXUIElementCreateApplication(spotify.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        return Int(AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value).rawValue)
    }
    static func execute(_ source: String) throws -> String? {
        var details: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw SpotifyError.message(.scriptUnavailable) }
        let result = script.executeAndReturnError(&details)
        if let details {
            throw NSError(domain: "Jarvis.Spotify", code: details[NSAppleScript.errorNumber] as? Int ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: details[NSAppleScript.errorMessage] as? String ?? "Spotify недоступен"])
        }
        return result.stringValue
    }

    static func volume() throws -> Int? {
        try execute("tell application id \"com.spotify.client\" to return sound volume").flatMap(Int.init)
    }

    static func setVolume(_ value: Int) throws {
        _ = try execute("tell application id \"com.spotify.client\" to set sound volume to \(max(0, min(100, value)))")
    }

    /// Read Spotify's native tri-state checkbox: 0=off, 1=context, 2=one track.
    /// The public AppleScript Boolean cannot select state 2.
    static func setTrackRepeat(_ action: TrackRepeatAction, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let spotify = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first else {
            completion(.failure(SpotifyError.message(.spotifyNotRunning))); return
        }
        let app = AXUIElementCreateApplication(spotify.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        // Query the actual AX operation. The trust preflight can retain stale
        // state after an app update or permission change.
        var children: CFTypeRef?
        let permission = AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children)
        if permission == .apiDisabled {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            completion(.failure(SpotifyError.message(.accessibilityRequired)))
            return
        }
        _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        do {
            guard let control = try repeatControl(in: app) else { throw SpotifyError.message(.repeatControlMissing) }
            guard let value = attribute(control, kAXValueAttribute) as? NSNumber else {
                throw SpotifyError.message(.repeatStateUnavailable)
            }
            let target = action.targetState(from: value.intValue)
            transition(control: control, target: target, remaining: 3, completion: completion)
        } catch { completion(.failure(error)) }
    }

    private static func transition(control: AXUIElement, target: Int, remaining: Int,
                                   completion: @escaping (Result<Void, Error>) -> Void) {
        guard let current = attribute(control, kAXValueAttribute) as? NSNumber, (0...2).contains(current.intValue) else {
            completion(.failure(SpotifyError.message(.repeatStateUnavailable))); return
        }
        if current.intValue == target { completion(.success(())); return }
        guard remaining > 0, AXUIElementPerformAction(control, kAXPressAction as CFString) == .success else {
            completion(.failure(SpotifyError.message(.repeatModeFailed))); return
        }
        // Wait for Spotify to publish the new checkbox state before pressing again.
        waitForChange(control: control, previous: current.intValue, retries: 8) { changed in
            guard changed else { completion(.failure(SpotifyError.message(.repeatStateUnchanged))); return }
            transition(control: control, target: target, remaining: remaining - 1, completion: completion)
        }
    }

    private static func waitForChange(control: AXUIElement, previous: Int, retries: Int, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let value = attribute(control, kAXValueAttribute) as? NSNumber, value.intValue != previous { completion(true) }
            else if retries > 0 { waitForChange(control: control, previous: previous, retries: retries - 1, completion: completion) }
            else { completion(false) }
        }
    }

    private static func repeatControl(in app: AXUIElement) throws -> AXUIElement? {
        // Search breadth first so the player controls precede long playlist rows.
        var queue = [app]
        var offset = 0
        while offset < queue.count && offset < 1800 {
            let element = queue[offset]; offset += 1
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == kAXCheckBoxRole || role == kAXButtonRole {
                let label = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute]
                    .compactMap { attribute(element, $0) as? String }.joined(separator: " ").lowercased()
                if label.contains("повтор") || label.contains("repeat") { return element }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf: children) }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

enum SpotifyError: LocalizedError {
    case message(VoiceMessage)
    var errorDescription: String? { spokenDescription(language: "ru") }
    func spokenDescription(language: String) -> String {
        switch self { case .message(let message): return message.text(language: language) }
    }
}
