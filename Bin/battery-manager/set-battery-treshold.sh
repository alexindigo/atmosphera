#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_error() {
    echo -e "$1" >&2
}

print_info() {
    echo -e "$1"
}

send_notification() {
    local urgency="$1"
    local title="$2"
    local message="$3"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" "$title" "$message"
    fi
}

if [ "$#" -ne 1 ]; then
    print_error "Battery level not specified"
    echo "Usage: $0 <number>" >&2
    exit 1
fi

if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -gt 100 ] || [ "$1" -lt 0 ]; then
    print_error "Battery level must be a number between 0-100"
    echo "Usage: $0 <number>" >&2
    exit 1
fi

BATTERY_LEVEL="$1"

CURRENT_USER="$USER"
if [ -z "$CURRENT_USER" ]; then
    CURRENT_USER="$(whoami)"
fi

BATTERY_MANAGER_PATH="/usr/bin/battery-manager-$CURRENT_USER"

if [ ! -f "$BATTERY_MANAGER_PATH" ]; then
    print_error "Battery manager components missing for user $CURRENT_USER!"
    send_notification "critical" "Battery Manager Setup Required" \
        "Battery manager needs to be set up for user $CURRENT_USER. Please authenticate when prompted."

    print_info "Running installer (authentication required)..."

    if pkexec "$SCRIPT_DIR/install-battery-manager.sh"; then
        print_info "Installation completed successfully!"
        send_notification "normal" "Battery Manager Installed" \
            "Battery manager has been set up successfully for $CURRENT_USER."
    else
        print_error "Installation failed or was cancelled"
        send_notification "critical" "Installation Failed" \
            "Battery manager installation failed or was cancelled."
        exit 1
    fi
fi

print_info "Setting battery charging threshold to $BATTERY_LEVEL% for user $CURRENT_USER..."

if pkexec "$BATTERY_MANAGER_PATH" "$BATTERY_LEVEL"; then
    print_info "Battery charging threshold set to $BATTERY_LEVEL%"
    send_notification "normal" "Battery Threshold Updated" \
        "Battery charging threshold has been set to $BATTERY_LEVEL%"
else
    print_error "Failed to set battery charging threshold"
    send_notification "critical" "Battery Threshold Failed" \
        "Failed to set battery charging threshold to $BATTERY_LEVEL%"
    exit 1
fi
