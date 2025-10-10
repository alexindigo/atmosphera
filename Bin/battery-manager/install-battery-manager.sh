#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_error() {
    echo -e "$1" >&2
}

print_info() {
    echo -e "$1"
}

if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run with root privileges"
    exit 1
fi

print_info "Installing Battery Manager..."
echo

if [ -n "$PKEXEC_UID" ]; then
    ACTUAL_USER=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
else
    ACTUAL_USER="$SUDO_USER"
fi

if [ -z "$ACTUAL_USER" ]; then
    print_error "Could not determine the actual user"
    exit 1
fi

print_info "Installing for user: $ACTUAL_USER"
echo

print_info "Creating configuration directory..."
mkdir -p /etc/battery-manager

if [ -f "$SCRIPT_DIR/battery-paths.conf" ]; then
    cp "$SCRIPT_DIR/battery-paths.conf" /etc/battery-manager/paths.conf
    print_info "Paths configuration copied from $SCRIPT_DIR/battery-paths.conf"
else
    print_error "battery-paths.conf not found in $SCRIPT_DIR"
    exit 1
fi

chmod 755 /etc/battery-manager
chmod 644 /etc/battery-manager/paths.conf
print_info "Configuration created at /etc/battery-manager/paths.conf"

print_info "Installing battery manager script..."

BATTERY_MANAGER_PATH="/usr/bin/battery-manager-$ACTUAL_USER"

if [ -f "$SCRIPT_DIR/battery-manager.sh" ]; then
    cp "$SCRIPT_DIR/battery-manager.sh" "$BATTERY_MANAGER_PATH"
    chmod +x "$BATTERY_MANAGER_PATH"
    print_info "Battery manager script copied from $SCRIPT_DIR/battery-manager.sh"
else
    print_error "battery-manager.sh not found in $SCRIPT_DIR"
    exit 1
fi

print_info "Script installed at $BATTERY_MANAGER_PATH"

print_info "Creating log file..."
touch /var/log/battery-manager.log
chmod 644 /var/log/battery-manager.log
print_info "Log file created at /var/log/battery-manager.log"

print_info "Creating polkit policy..."

POLICY_FILE="/usr/share/polkit-1/actions/com.local.battery-manager.$ACTUAL_USER.policy"

if [ -f "$SCRIPT_DIR/battery-manager.policy" ]; then
    sed -e "s|/home/damian/Projects/noctalia/battery-charging-treshold/Bin/install-battery-manager.sh|$SCRIPT_DIR/install-battery-manager.sh|g" \
        -e "s/ACTUAL_USER_PLACEHOLDER/$ACTUAL_USER/g" \
        "$SCRIPT_DIR/battery-manager.policy" > "$POLICY_FILE"
    print_info "Polkit policy copied from $SCRIPT_DIR/battery-manager.policy"
else
    print_error "battery-manager.policy not found in $SCRIPT_DIR"
    exit 1
fi

print_info "Polkit policy created at $POLICY_FILE"

print_info "Creating polkit rule..."

RULES_FILE="/etc/polkit-1/rules.d/50-battery-manager-$ACTUAL_USER.rules"

if [ -f "$SCRIPT_DIR/battery-manager.rules" ]; then
    sed "s/ACTUAL_USER_PLACEHOLDER/$ACTUAL_USER/g" \
        "$SCRIPT_DIR/battery-manager.rules" > "$RULES_FILE"
    print_info "Polkit rule copied from $SCRIPT_DIR/battery-manager.rules"
else
    print_error "battery-manager.rules not found in $SCRIPT_DIR"
    exit 1
fi

print_info "Polkit rule created for user: $ACTUAL_USER at $RULES_FILE"

print_info "Restarting polkit..."
if systemctl restart polkit 2>/dev/null; then
    print_info "Polkit restarted"
else
    print_info "Could not restart polkit automatically, you may need to reboot"
fi

echo
print_info "Installation complete!"
echo
print_info "Configuration file: /etc/battery-manager/paths.conf"
print_info "Log file: /var/log/battery-manager.log"
print_info "User-specific script: /usr/bin/battery-manager-$ACTUAL_USER"
print_info "User-specific policy: /usr/share/polkit-1/actions/com.local.battery-manager.$ACTUAL_USER.policy"
print_info "User-specific rules: /etc/polkit-1/rules.d/50-battery-manager-$ACTUAL_USER.rules"
