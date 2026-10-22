public enum VoiceMessage: CaseIterable {
    case readyLocal, readyNetwork, goodbye, help, missingMusic, done, nothingPlaying
    case startupFailure, spotifyFailure, scriptUnavailable, accessibilityRequired
    case spotifyNotRunning, repeatControlMissing, repeatStateUnavailable, repeatModeFailed, repeatStateUnchanged

    public func text(language: String) -> String {
        let english = language == "en"
        switch self {
        case .readyLocal: return english ? "Jarvis is ready. I'm listening for Russian commands." : "Джарвис готов. Скажите: Джарвис, помощь."
        case .readyNetwork: return english ? "Jarvis is ready. Speech recognition uses Apple's service. I'm listening for Russian commands." : "Джарвис готов. Распознавание через сервис Apple. Скажите: Джарвис, помощь."
        case .goodbye: return english ? "Jarvis is shutting down." : "Джарвис завершает работу."
        case .help: return english ? "Give me commands in Russian. I can pause, resume, skip tracks, change the volume, seek, identify the song, play your daylist or liked songs. Loop toggles repeat for one track. Randomise toggles shuffle. Ask me in Russian to stop listening when you're done." : "Скажите Джарвис и команду: пауза, продолжи, следующий, предыдущий, тише, громче, громкость сто, сначала, вперед на десять секунд, что играет, loop для переключения повтора трека, randomise для переключения перемешивания, включи daylist, включи любимые треки. Для выхода: Джарвис, перестань слушать."
        case .missingMusic: return english ? "Save a link to this song or playlist in Jarvis settings first." : "Сначала сохраните ссылку на этот трек или плейлист в настройках Джарвиса."
        case .done: return english ? "Done." : "Готово"
        case .nothingPlaying: return english ? "Nothing is playing right now." : "Сейчас ничего не играет"
        case .startupFailure: return english ? "Jarvis could not start. Check microphone and speech permissions, Spotify, and the settings file. The error details are in the log." : "Не удалось запустить Джарвис. Проверьте микрофон, распознавание речи, Spotify и настройки."
        case .spotifyFailure: return english ? "I couldn't complete the Spotify command. Check Spotify and Jarvis Automation permission in macOS settings." : "Не удалось выполнить команду Spotify. Проверьте Spotify и разрешение Автоматизация для Джарвиса."
        case .scriptUnavailable: return english ? "I couldn't create the Spotify command." : "Не удалось создать команду Spotify."
        case .accessibilityRequired: return english ? "To use loop, allow Jarvis under Accessibility in macOS Privacy and Security settings. Then try the command again." : "Для loop разрешите Jarvis в разделе Универсальный доступ в настройках конфиденциальности macOS. Затем повторите команду."
        case .spotifyNotRunning: return english ? "Open Spotify on your Mac first." : "Сначала откройте Spotify на Mac."
        case .repeatControlMissing: return english ? "I couldn't find Spotify's repeat button. Open the main Spotify window and try loop again." : "Не нашел кнопку повтора в Spotify. Откройте основное окно Spotify и повторите loop."
        case .repeatStateUnavailable: return english ? "I couldn't read Spotify's repeat mode." : "Не удалось прочитать режим повтора Spotify."
        case .repeatModeFailed: return english ? "I couldn't set Spotify's repeat mode." : "Не удалось включить нужный режим повтора Spotify."
        case .repeatStateUnchanged: return english ? "Spotify did not confirm the repeat mode change." : "Spotify не подтвердил смену режима повтора."
        }
    }
}
