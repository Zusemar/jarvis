#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE_LABEL="com.zusemar.jarvis"
SERVICE_DOMAIN="gui/$(id -u)"
SERVICE_TARGET="$SERVICE_DOMAIN/$SERVICE_LABEL"
APP_PATH="$HOME/Applications/Jarvis.app"
AGENT_PATH="$HOME/Library/LaunchAgents/$SERVICE_LABEL.plist"
LOG_PATH="$HOME/Library/Logs/Jarvis"

write_plist() {
    local target="$1"
    /usr/bin/plutil -create xml1 "$target"
    /usr/bin/plutil -insert Label -string "$SERVICE_LABEL" "$target"
    /usr/bin/plutil -insert ProgramArguments -array "$target"
    /usr/bin/plutil -insert ProgramArguments.0 -string "$APP_PATH/Contents/MacOS/Jarvis" "$target"
    /usr/bin/plutil -insert RunAtLoad -bool true "$target"
    /usr/bin/plutil -insert KeepAlive -dictionary "$target"
    /usr/bin/plutil -insert KeepAlive.SuccessfulExit -bool false "$target"
    /usr/bin/plutil -insert ThrottleInterval -integer 30 "$target"
    /usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$target"
    /usr/bin/plutil -insert ProcessType -string Interactive "$target"
    /usr/bin/plutil -insert AssociatedBundleIdentifiers -string "$SERVICE_LABEL" "$target"
    /usr/bin/plutil -insert WorkingDirectory -string "$HOME/Applications" "$target"
    /usr/bin/plutil -insert StandardOutPath -string "$LOG_PATH/output.log" "$target"
    /usr/bin/plutil -insert StandardErrorPath -string "$LOG_PATH/error.log" "$target"
    /usr/bin/plutil -lint "$target"
}

case "${1:-status}" in
    install)
        [[ -x dist/Jarvis.app/Contents/MacOS/Jarvis ]] || { printf 'Сначала выполните bash scripts/build-app.sh\n' >&2; exit 1; }
        /bin/launchctl print "$SERVICE_DOMAIN" >/dev/null
        /usr/bin/codesign --verify --deep --strict dist/Jarvis.app
        mkdir -p "$HOME/Applications" "$(dirname "$AGENT_PATH")" "$LOG_PATH" .build
        write_plist .build/Jarvis.LaunchAgent.plist
        if /bin/launchctl print "$SERVICE_TARGET" >/dev/null 2>&1; then
            /bin/launchctl bootout "$SERVICE_TARGET"
        fi
        BACKUP_TAG="$(date +%Y%m%d-%H%M%S)-$$"
        if [[ -e "$APP_PATH" ]]; then mv "$APP_PATH" "$APP_PATH.backup-$BACKUP_TAG"; fi
        /usr/bin/ditto dist/Jarvis.app "$APP_PATH"
        /usr/bin/codesign --verify --deep --strict "$APP_PATH"
        if [[ -e "$AGENT_PATH" ]]; then cp "$AGENT_PATH" "$AGENT_PATH.backup-$BACKUP_TAG"; fi
        cp .build/Jarvis.LaunchAgent.plist "$AGENT_PATH"
        chmod 644 "$AGENT_PATH"
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"
        /bin/launchctl enable "$SERVICE_TARGET"
        /bin/launchctl bootstrap "$SERVICE_DOMAIN" "$AGENT_PATH"
        printf '\nУстановлен: %s\nАвтозапуск: %s\nЛоги: %s\n' "$APP_PATH" "$AGENT_PATH" "$LOG_PATH"
        ;;
    start)
        if ! /bin/launchctl print "$SERVICE_TARGET" >/dev/null 2>&1; then
            /bin/launchctl enable "$SERVICE_TARGET"
            /bin/launchctl bootstrap "$SERVICE_DOMAIN" "$AGENT_PATH"
        else
            /bin/launchctl kickstart "$SERVICE_TARGET"
        fi
        ;;
    restart)
        /bin/launchctl kickstart -k "$SERVICE_TARGET"
        ;;
    test-restart)
        OLD_PID="$(/bin/launchctl print "$SERVICE_TARGET" | /usr/bin/awk '/^[[:space:]]*pid = / { print $3; exit }')"
        [[ -n "$OLD_PID" ]] || { printf 'Jarvis сейчас не запущен.\n' >&2; exit 1; }
        /bin/launchctl kill SIGKILL "$SERVICE_TARGET"
        for attempt in {1..20}; do
            sleep 2
            NEW_PID="$(/bin/launchctl print "$SERVICE_TARGET" | /usr/bin/awk '/^[[:space:]]*pid = / { print $3; exit }')"
            if [[ -n "$NEW_PID" && "$NEW_PID" != "$OLD_PID" ]]; then
                printf 'Автовосстановление подтверждено: процесс %s → %s\n' "$OLD_PID" "$NEW_PID"
                exit 0
            fi
        done
        printf 'Не удалось подтвердить восстановление за 40 секунд.\n' >&2
        exit 1
        ;;
    check)
        "$APP_PATH/Contents/MacOS/Jarvis" --check
        /usr/bin/log show --last 3m --style compact --predicate 'subsystem == "com.zusemar.jarvis"' --info
        ;;
    stop)
        # Bootout prevents an intentional stop from being mistaken for a crash.
        if /bin/launchctl print "$SERVICE_TARGET" >/dev/null 2>&1; then /bin/launchctl bootout "$SERVICE_TARGET"; fi
        printf 'Jarvis остановлен до следующего входа в macOS или команды start.\n'
        ;;
    status)
        /bin/launchctl print "$SERVICE_TARGET"
        ;;
    disable)
        if /bin/launchctl print "$SERVICE_TARGET" >/dev/null 2>&1; then /bin/launchctl bootout "$SERVICE_TARGET"; fi
        /bin/launchctl disable "$SERVICE_TARGET"
        printf 'Фоновый запуск Jarvis отключен. Для включения: bash scripts/service.sh start\n'
        ;;
    plist)
        mkdir -p .build
        write_plist .build/Jarvis.LaunchAgent.plist
        /usr/bin/plutil -p .build/Jarvis.LaunchAgent.plist
        ;;
    *)
        printf 'Использование: bash scripts/service.sh install|start|restart|stop|status|disable|check|test-restart|plist\n' >&2
        exit 2
        ;;
esac
