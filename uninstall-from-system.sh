#!/bin/bash
# Restore original noctalia-shell files (remove labwc support)
# Run this script if you want to restore the original system installation

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

INSTALL_DIR="/etc/xdg/quickshell/noctalia-shell/Services/Compositor"

echo -e "${YELLOW}=== Noctalia Shell - Restore Original Files ===${NC}"
echo ""
echo "This script will:"
echo "  1. Restore original CompositorService.qml from backup"
echo "  2. Remove LabwcService.qml"
echo ""
echo -e "${YELLOW}Installation directory:${NC} $INSTALL_DIR"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run with sudo${NC}"
    echo "Usage: sudo bash uninstall-from-system.sh"
    exit 1
fi

# Check if backup exists
if [ ! -f "$INSTALL_DIR/CompositorService.qml.backup" ]; then
    echo -e "${RED}Error: Backup file not found: $INSTALL_DIR/CompositorService.qml.backup${NC}"
    echo "Cannot restore original file without backup."
    exit 1
fi

echo -e "${GREEN}✓${NC} Backup file found"
echo ""

# Step 1: Restore original CompositorService.qml
echo "Step 1: Restoring original CompositorService.qml..."
cp "$INSTALL_DIR/CompositorService.qml.backup" "$INSTALL_DIR/CompositorService.qml"
echo -e "${GREEN}✓${NC} Original CompositorService.qml restored"
echo ""

# Step 2: Remove LabwcService.qml
echo "Step 2: Removing LabwcService.qml..."
if [ -f "$INSTALL_DIR/LabwcService.qml" ]; then
    rm "$INSTALL_DIR/LabwcService.qml"
    echo -e "${GREEN}✓${NC} LabwcService.qml removed"
else
    echo -e "${YELLOW}  Warning: LabwcService.qml not found, skipping...${NC}"
fi
echo ""

# Verify restoration
echo "Verification:"
echo "  Current files:"
ls -lh "$INSTALL_DIR/CompositorService.qml"
echo ""
echo "  Backup file (kept for safety):"
ls -lh "$INSTALL_DIR/CompositorService.qml.backup"
echo ""

echo -e "${GREEN}=== Restoration Complete! ===${NC}"
echo ""
echo "Original noctalia-shell files restored."
echo ""
echo "Next steps:"
echo "  1. Log out of your current session"
echo "  2. Log back in"
echo "  3. noctalia-shell will run with original configuration"
echo ""
echo "Note: The backup file was kept at:"
echo "  $INSTALL_DIR/CompositorService.qml.backup"
echo ""
echo "To remove the backup:"
echo "  sudo rm $INSTALL_DIR/CompositorService.qml.backup"
echo ""
