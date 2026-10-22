import Foundation

@main
struct TestRunner {
    static func main() throws {
        let tests = CommandTests()
        let cases: [(String, () throws -> Void)] = [
            ("wake word boundaries", tests.testWakeWordIsRequiredAndHasWordBoundaries),
            ("wake timeout and one command", tests.testWakeWordAloneArmsOnlyOneCommandForFiveSeconds),
            ("reject partial and unrelated commands", tests.testEntireCommandMustMatch),
            ("Russian commands and numbers", tests.testCommandsAndRussianNumbers),
            ("music names containing commands", tests.testMusicNamesContainingControlWordsStayMusicNames),
            ("last wake word wins", tests.testLastWakeWordWins),
            ("volume boundaries", tests.testVolumeAlwaysClampedInGeneratedCommands),
            ("Spotify URI and injection rejection", tests.testSpotifyURIValidationRejectsAppleScriptInjectionAndOtherHosts),
            ("config validation", tests.testConfigValidationAndNameNormalization),
            ("seek and unknown music", tests.testSeekingIsBoundedAndUnsupportedMusicDoesNotBecomeAScript),
            ("English commands and transliterations", tests.testEnglishCommandsAndTransliterations),
            ("personal playlist aliases", tests.testPersonalPlaylistAliases),
            ("volume 100", tests.testDefaultVolumeCanReachOneHundred),
            ("now playing text reply", tests.testNowPlayingReadsPropertiesWithoutUnsupportedExists),
            ("voice settings", tests.testSpeechSettingsValidation),
            ("loop toggle transitions", tests.testLoopTogglesOffAndOnAndExplicitOffStaysOff),
            ("English replies with Russian commands", tests.testEnglishRepliesKeepRussianRecognitionIndependent),
            ("local Kokoro configuration", tests.testKokoroRequiresEnglishRepliesAndKeepsRussianCommands)
        ]
        for (name, test) in cases { try test(); print("PASS: \(name)") }
        print("\(cases.count) tests, \(assertionCount) assertions passed")
    }
}
