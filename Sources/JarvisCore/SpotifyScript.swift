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
            body = "set player position to my clampValue((player position + \(seconds)), 0, ((duration of current track) / 1000))"
        case .toggleShuffle: body = "set shuffling to not shuffling\nreturn (shuffling as text)"
        case .shuffle(let enabled): body = "set shuffling to \(enabled ? "true" : "false")"
        case .repeatAll(let enabled): body = "set repeating to \(enabled ? "true" : "false")"
        case .nowPlaying:
            // Spotify doesn't implement the standard AppleScript "exists" event.
            // Read properties directly and return plain text, even while paused.
            body = """
            try
                set trackTitle to (name of current track) as text
                set trackArtist to (artist of current track) as text
                if trackTitle is "" then return "Сейчас ничего не играет"
                return trackTitle & " — " & trackArtist
            on error number -1728
                return "Сейчас ничего не играет"
            end try
            """
        case .playSaved(let name):
            guard let configured = configuration.savedMusic[name], let uri = Configuration.spotifyURI(configured) else { return nil }
            body = "play track \"\(uri)\""
        case .repeatTrack, .toggleTrackRepeat, .help, .stopListening: return nil
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
