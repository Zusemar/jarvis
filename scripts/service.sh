#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE_LABEL="com.zusemar.jarvis"
SERVICE_DOMAIN="gui/$(id -u)"
SERVICE_TARGET="$SERVICE_DOMAIN/$SERVICE_LABEL"
APP_PATH="$HOME/Applications/Jarvis.app"
AGENT_PATH="$HOME/Library/LaunchAgents/$SERVICE_LABEL.plist"
LOG_PATH="$HOME/Library/Logs/Jarvis"
HELPER_PATH="$APP_PATH/Contents/Helpers/JarvisSupervisor"

bootstrap_service() {
    # launchd can briefly retain the old job after bootout returns.
    mkdir -p .build
    for attempt in {1..10}; do
        if /bin/launchctl bootstrap "$SERVICE_DOMAIN" "$AGENT_PATH" >.build/launch-bootstrap.log 2>&1; then return 0; fi
        sleep 1
    done
    cat .build/launch-bootstrap.log >&2
    return 1
}

stop_service() {
    if /bin/launchctl print "$SERVICE_TARGET" >/dev/null 2>&1; then
        /bin/launchctl bootout "$SERVICE_TARGET"
    fi
    if [[ -x "$HELPER_PATH" ]]; then "$HELPER_PATH" --terminate; fi
}

write_plist() {
    local target="$1"
    /usr/bin/plutil -create xml1 "$target"
    /usr/bin/plutil -insert Label -string "$SERVICE_LABEL" "$target"
    /usr/bin/plutil -insert ProgramArguments -array "$target"
    /usr/bin/plutil -insert ProgramArguments.0 -string "$HELPER_PATH" "$target"
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
        stop_service
        BACKUP_TAG="$(date +%Y%m%d-%H%M%S)-$$"
        if [[ -e "$APP_PATH" ]]; then mv "$APP_PATH" "$APP_PATH.backup-$BACKUP_TAG"; fi
        /usr/bin/ditto dist/Jarvis.app "$APP_PATH"
        /usr/bin/codesign --verify --deep --strict "$APP_PATH"
        if [[ -e "$AGENT_PATH" ]]; then cp "$AGENT_PATH" "$AGENT_PATH.backup-$BACKUP_TAG"; fi
        cp .build/Jarvis.LaunchAgent.plist "$AGENT_PATH"
        chmod 644 "$AGENT_PATH"
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"
        /bin/launchctl enable "$SERVICE_TARGET"
        bootstrap_service
        printf '\nУстановлен: %s\nАвтозапуск: %s\nЛоги: %s\n' "$APP_PATH" "$AGENT_PATH" "$LOG_PATH"
        ;;
    configure)
        [[ $# -eq 2 && -f "$2" ]] || { printf 'Нужен путь к JSON с настройками.\n' >&2; exit 2; }
        "$APP_PATH/Contents/MacOS/Jarvis" --config "$2" --dry-run 'Джарвис, громкость сто' >/dev/null
        CONFIG_PATH="$HOME/Library/Application Support/Jarvis/config.json"
        mkdir -p "$(dirname "$CONFIG_PATH")"
        if [[ -f "$CONFIG_PATH" ]]; then cp "$CONFIG_PATH" "$CONFIG_PATH.backup-$(date +%Y%m%d-%H%M%S)-$$"; fi
        cp "$2" "$CONFIG_PATH"
        chmod 600 "$CONFIG_PATH"
        printf 'Настройки сохранены. Для применения перезапустите Jarvis.\n'
        ;;
    start)
        if ! /bin/launchctl print "$SERVICE_TARGET" >/dev/null 2>&1; then
            /bin/launchctl enable "$SERVICE_TARGET"
            bootstrap_service
        else
            /bin/launchctl kickstart "$SERVICE_TARGET"
        fi
        ;;
    restart)
        stop_service
        bootstrap_service
        ;;
    test-restart)
        OLD_PID="$("$HELPER_PATH" --test-crash)"
        for attempt in {1..20}; do
            sleep 2
            NEW_PID="$(/usr/bin/pgrep -x Jarvis || true)"
            if [[ -n "$NEW_PID" && "$NEW_PID" != "$OLD_PID" ]]; then
                printf 'Автовосстановление подтверждено: процесс %s → %s\n' "$OLD_PID" "$NEW_PID"
                exit 0
            fi
        done
        printf 'Не удалось подтвердить восстановление за 40 секунд.\n' >&2
        exit 1
        ;;
    command)
        [[ $# -eq 2 ]] || { printf 'Нужна фраза команды.\n' >&2; exit 2; }
        "$APP_PATH/Contents/MacOS/Jarvis" --execute "$2"
        ;;
    check)
        # A separate CLI process may inherit its terminal's privacy permissions.
        # Inspect the heartbeat produced by the actual listening application.
        /usr/bin/plutil -p "$HOME/Library/Application Support/Jarvis/runtime.json"
        /usr/bin/log show --last 3m --style compact --predicate 'subsystem == "com.zusemar.jarvis"' --info
        ;;
    stop)
        # Bootout prevents an intentional stop from being mistaken for a crash.
        stop_service
        printf 'Jarvis остановлен до следующего входа в macOS или команды start.\n'
        ;;
    status)
        /bin/launchctl print "$SERVICE_TARGET"
        ;;
    disable)
        stop_service
        /bin/launchctl disable "$SERVICE_TARGET"
        printf 'Фоновый запуск Jarvis отключен. Для включения: bash scripts/service.sh start\n'
        ;;
    plist)
        mkdir -p .build
        write_plist .build/Jarvis.LaunchAgent.plist
        /usr/bin/plutil -p .build/Jarvis.LaunchAgent.plist
        ;;
    *)
        printf 'Использование: bash scripts/service.sh install|configure FILE|start|restart|stop|status|disable|command PHRASE|check|test-restart|plist\n' >&2
        exit 2
        ;;
esac
