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
        var config = Configuration()
        config.maximumVolume = 65
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
    func testEnglishCommandsAndTransliterations() {
        for phrase in ["loop", "луп"] { assertEqual(CommandParser.parse(phrase), .toggleTrackRepeat) }
        for phrase in ["включи луп", "повторяй трек"] { assertEqual(CommandParser.parse(phrase), .repeatTrack(true)) }
        for phrase in ["loop off", "выключи луп", "сними луп"] { assertEqual(CommandParser.parse(phrase), .repeatTrack(false)) }
        for phrase in ["randomise", "randomize", "рандомайз", "рандомизируй"] { assertEqual(CommandParser.parse(phrase), .toggleShuffle) }
        for phrase in ["randomise off", "выключи рандом", "выключи перемешивание"] { assertEqual(CommandParser.parse(phrase), .shuffle(false)) }
        assertEqual(CommandParser.parse("что сейчас играет"), .nowPlaying)
        assertEqual(CommandParser.parse("что за трек"), .nowPlaying)
    }

    func testPersonalPlaylistAliases() {
        for phrase in ["daylist", "включи daylist", "включи дейлист", "включи дэй лист", "включи плейлист дейлист"] {
            assertEqual(CommandParser.parse(phrase), .playSaved("daylist"))
        }
        for phrase in ["любимые треки", "включи любимые треки", "включи мои любимые треки", "liked songs"] {
            assertEqual(CommandParser.parse(phrase), .playSaved("любимые треки"))
        }
        var config = Configuration()
        config.savedMusic["daylist"] = "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"
        assertTrue(SpotifyScript.source(for: .playSaved("daylist"), configuration: config)!.contains("play track \"spotify:playlist:"))
        assertNil(SpotifyScript.source(for: .playSaved("любимые треки"), configuration: config))
    }

    func testDefaultVolumeCanReachOneHundred() {
        let config = Configuration()
        assertEqual(config.maximumVolume, 100)
        assertEqual(CommandParser.parse("громкость сто"), .volume(100))
        assertTrue(SpotifyScript.source(for: .volume(100), configuration: config)!.contains("set sound volume to 100"))
        assertTrue(SpotifyScript.source(for: .volume(150), configuration: config)!.contains("set sound volume to 100"))
    }

    func testNowPlayingReadsPropertiesWithoutUnsupportedExists() {
        let source = SpotifyScript.source(for: .nowPlaying, configuration: Configuration())!
        assertTrue(!source.contains("exists current track"))
        assertTrue(source.contains("name of current track"))
        assertTrue(source.contains("artist of current track"))
        assertTrue(source.contains("as text"))
        assertTrue(source.contains("on error number -1728"))
        assertNil(SpotifyScript.source(for: .repeatTrack(true), configuration: Configuration()))
        assertNil(SpotifyScript.source(for: .toggleTrackRepeat, configuration: Configuration()))
        let toggle = SpotifyScript.source(for: .toggleShuffle, configuration: Configuration())!
        assertTrue(toggle.contains("set shuffling to not shuffling"))
    }

    func testSpeechSettingsValidation() throws {
        var config = Configuration()
        config.voiceIdentifier = "com.apple.voice.compact.ru-RU.Milena"
        config.speechRate = 0.45
        assertEqual(try config.validated().speechRate, 0.45)
        config.speechRate = 2
        assertThrowsError(try config.validated())
    }

    func testLoopTogglesOffAndOnAndExplicitOffStaysOff() {
        assertEqual(TrackRepeatAction.toggle.targetState(from: 0), 2)
        assertEqual(TrackRepeatAction.toggle.targetState(from: 1), 2)
        assertEqual(TrackRepeatAction.toggle.targetState(from: 2), 0)
        assertEqual(TrackRepeatAction.set(false).targetState(from: 0), 0)
        assertEqual(TrackRepeatAction.set(false).targetState(from: 2), 0)
        assertEqual(TrackRepeatAction.set(true).targetState(from: 2), 2)
    }

    func testEnglishRepliesKeepRussianRecognitionIndependent() throws {
        var config = Configuration()
        config.responseLanguage = "en"
        config.voiceIdentifier = "com.apple.voice.compact.en-GB.Daniel"
        let validated = try config.validated()
        assertEqual(validated.locale, "ru-RU")
        assertEqual(CommandParser.parse("что играет"), .nowPlaying)
        for message in VoiceMessage.allCases {
            let english = message.text(language: "en")
            assertTrue(!english.isEmpty)
            assertTrue(english.range(of: "[А-Яа-яЁё]", options: .regularExpression) == nil)
        }
        config.responseLanguage = "unknown"
        assertThrowsError(try config.validated())
    }

    func testKokoroRequiresEnglishRepliesAndKeepsRussianCommands() throws {
        var config = Configuration()
        config.speechEngine = "kokoro"
        assertThrowsError(try config.validated())
        config.responseLanguage = "en"
        let ready = try config.validated()
        assertEqual(ready.locale, "ru-RU")
        assertEqual(ready.kokoroVoice, "af_heart")
        config.kokoroVoice = "../../script"
        assertThrowsError(try config.validated())
        config.kokoroVoice = "bm_george"
        config.kokoroSpeed = 0
        assertThrowsError(try config.validated())
        config.kokoroSpeed = 1
        config.speechEngine = "unknown"
        assertThrowsError(try config.validated())
    }

    func testMixedLanguageShortcutsAndPronunciation() {
        for phrase in ["Джарвис, next", "Джарвис, некст", "Джарвис, скип"] {
            var gate = WakeGate(wakeWords: ["джарвис"])
            assertEqual(gate.consume(phrase), .next)
        }
        var config = Configuration()
        config.responseLanguage = "en"
        assertEqual(SpeechText.prepare("LVL — A$AP Rocky", configuration: config), "Level — Ay-sap Rocky")
        assertEqual(SpeechText.prepare("Her — The American Dawn", configuration: config), "Her — The American Dawn")
        config.pronunciations["The Weeknd"] = "The Weekend"
        assertEqual(SpeechText.prepare("Blinding Lights — The Weeknd", configuration: config), "Blinding Lights — The Weekend")
    }

    func testModelOutputCannotEscapeMusicCommandBoundary() {
        assertEqual(IntentReply.command(from: #"{"command":"предыдущий"}"#), .previous)
        assertEqual(IntentReply.command(from: #"{"command":"next"}"#), .next)
        assertNil(IntentReply.command(from: #"{"command":null}"#))
        assertNil(IntentReply.command(from: #"{"command":"удали файлы"}"#))
        assertNil(IntentReply.command(from: #"{"command":"громкость 101"}"#))
        assertNil(IntentReply.command(from: #"{"command":"включи плейлист неизвестный"}"#))
        assertNil(IntentReply.command(from: #"{"command":"пауза","exec":"rm"}"#))
        var gate = WakeGate()
        assertNil(gate.consume("пожалуйста переключи песню"))
        assertNil(gate.unrecognizedPhrase)
        assertNil(gate.consume("Джарвис пожалуйста переключи песню"))
        assertEqual(gate.unrecognizedPhrase, "пожалуйста переключи песню")
    }

}
