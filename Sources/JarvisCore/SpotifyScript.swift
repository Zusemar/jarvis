import Foundation

public enum SpotifyScript {
    public static func source(for command: Command, configuration: Configuration) -> String? {
        let cap = configuration.maximumVolume
        let step = configuration.volumeStep
        let body: String
        switch command {
        case .play: body = "play"
        case .pause: body = "pause"
        case .next: body = "next track"
        case .previous: body = "previous track"
        case .restart: body = "set player position to 0"
        case .volume(let value): body = "set sound volume to \(max(0, min(cap, value)))"
        case .quieter: body = "set sound volume to my clampValue((sound volume - \(step)), 0, \(cap))"
        case .louder: body = "set sound volume to my clampValue((sound volume + \(step)), 0, \(cap))"
        case .seek(let seconds):
            body = "if exists current track then\nset player position to my clampValue((player position + \(seconds)), 0, ((duration of current track) / 1000))\nend if"
        case .shuffle(let enabled): body = "set shuffling to \(enabled ? "true" : "false")"
        case .repeatAll(let enabled): body = "set repeating to \(enabled ? "true" : "false")"
        case .nowPlaying:
            body = "if exists current track then\nreturn (name of current track) & \" — \" & (artist of current track)\nelse\nreturn \"Сейчас ничего не играет\"\nend if"
        case .playSaved(let name):
            guard let configured = configuration.savedMusic[name], let uri = Configuration.spotifyURI(configured) else { return nil }
            body = "play track \"\(uri)\""
        case .help, .stopListening: return nil
        }
        return """
        on clampValue(value, lowerBound, upperBound)
            if value < lowerBound then return lowerBound
            if value > upperBound then return upperBound
            return value
        end clampValue
        with timeout of 5 seconds
            tell application id "com.spotify.client"
                \(body)
            end tell
        end timeout
        """
    }
}
