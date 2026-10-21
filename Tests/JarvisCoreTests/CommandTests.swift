import Foundation
import JarvisCore

final class CommandTests {
    func testWakeWordIsRequiredAndHasWordBoundaries() {
        for phrase in ["пауза", "следующий трек", "суперджарвис пауза", "джарвисов следующий", "музыка играет"] {
            var gate = WakeGate()
            assertNil(gate.consume(phrase), phrase)
        }
        var gate = WakeGate()
        assertEqual(gate.consume("Эй, Джарвис! Следующий трек."), .next)
        assertEqual(gate.consume("JARVIS, пауза"), .pause)
    }

    func testWakeWordAloneArmsOnlyOneCommandForFiveSeconds() {
        var gate = WakeGate()
        let time = Date(timeIntervalSince1970: 100)
        assertNil(gate.consume("Джарвис", now: time))
        assertEqual(gate.consume("пауза", now: time.addingTimeInterval(2)), .pause)
        assertNil(gate.consume("следующий", now: time.addingTimeInterval(3)))
        assertNil(gate.consume("Джарвис", now: time))
        assertNil(gate.consume("следующий", now: time.addingTimeInterval(6)))
    }

    func testEntireCommandMustMatch() {
        assertNil(CommandParser.parse("не ставь на паузу"))
        assertNil(CommandParser.parse("следующий концерт будет завтра"))
        assertNil(CommandParser.parse("громкость 40 пожалуйста удали все"))
        assertNil(CommandParser.parse("включи трек"))
        assertNil(CommandParser.parse("выход из метро"))
    }

    func testCommandsAndRussianNumbers() {
        let examples: [(String, Command)] = [
            ("ПАУЗА!", .pause), ("продолжи", .play), ("предыдущий", .previous),
            ("сделай тише", .quieter), ("громче", .louder), ("начни сначала", .restart),
            ("громкость 40", .volume(40)), ("громкость сорок два", .volume(42)),
            ("громкость ноль", .volume(0)), ("громкость сто", .volume(100)),
            ("вперёд на десять секунд", .seek(10)), ("назад на 20 секунд", .seek(-20)),
            ("включи перемешивание", .shuffle(true)), ("выключи повтор", .repeatAll(false)),
            ("что играет", .nowPlaying), ("помощь", .help), ("перестань слушать", .stopListening),
            ("включи плейлист Моя Студия", .playSaved("моя студия"))
        ]
        for (phrase, command) in examples { assertEqual(CommandParser.parse(phrase), command, phrase) }
        for phrase in ["громкость 101", "громкость минус пять", "громкость двадцать сорок", "вперед на 500 секунд", "назад на ноль секунд"] {
            assertNil(CommandParser.parse(phrase), phrase)
        }
    }

    func testMusicNamesContainingControlWordsStayMusicNames() {
        assertEqual(CommandParser.parse("включи трек следующий"), .playSaved("следующий"))
        assertEqual(CommandParser.parse("включи плейлист пауза"), .playSaved("пауза"))
    }

    func testLastWakeWordWins() {
        var gate = WakeGate()
        assertEqual(gate.consume("джарвис пауза нет джарвис продолжи"), .play)
    }

    func testVolumeAlwaysClampedInGeneratedCommands() {
        let config = Configuration()
        assertTrue(SpotifyScript.source(for: .volume(100), configuration: config)!.contains("set sound volume to 65"))
        assertTrue(SpotifyScript.source(for: .volume(-50), configuration: config)!.contains("set sound volume to 0"))
        assertTrue(SpotifyScript.source(for: .louder, configuration: config)!.contains("clampValue((sound volume + 5), 0, 65)"))
        assertTrue(SpotifyScript.source(for: .quieter, configuration: config)!.contains("clampValue((sound volume - 5), 0, 65)"))
    }

    func testSpotifyURIValidationRejectsAppleScriptInjectionAndOtherHosts() throws {
        let id = "37i9dQZF1DXcBWIGoYBM5M"
        assertEqual(Configuration.spotifyURI("https://open.spotify.com/playlist/\(id)?si=abc"), "spotify:playlist:\(id)")
        assertEqual(Configuration.spotifyURI("spotify:track:\(id)"), "spotify:track:\(id)")
        for value in ["spotify:track:bad", "spotify:track:\(id)\"\nquit", "https://evil.com/track/\(id)",
                      "spotify:artist:\(id)", "https://open.spotify.com/track/../../\(id)", "file:///etc/passwd"] {
            assertNil(Configuration.spotifyURI(value), value)
        }
        var config = Configuration()
        config.savedMusic["студия"] = "spotify:track:\(id)\"\nquit"
        assertThrowsError(try config.validated())
        assertNil(SpotifyScript.source(for: .playSaved("студия"), configuration: config))
    }

    func testConfigValidationAndNameNormalization() throws {
        var config = Configuration()
        config.savedMusic["Моя Студия"] = "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"
        let valid = try config.validated()
        assertEqual(valid.savedMusic["моя студия"], "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M")
        config.maximumVolume = 150
        assertThrowsError(try config.validated())
        config = Configuration(); config.wakeWords = ["два слова"]
        assertThrowsError(try config.validated())
        config = Configuration(); config.recognitionMode = "magic"
        assertThrowsError(try config.validated())
    }

    func testSeekingIsBoundedAndUnsupportedMusicDoesNotBecomeAScript() {
        assertTrue(SpotifyScript.source(for: .seek(-10), configuration: Configuration())!.contains("clampValue((player position + -10), 0,"))
        assertNil(SpotifyScript.source(for: .playSaved("неизвестный"), configuration: Configuration()))
        assertNil(SpotifyScript.source(for: .help, configuration: Configuration()))
    }
}
