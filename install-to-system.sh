#!/bin/bash
# Install labwc support to system noctalia-shell installation
# Run this script to test your changes on the installed system

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

INSTALL_DIR="/etc/xdg/quickshell/noctalia-shell/Services/Compositor"
SOURCE_DIR="/home/brad/Documents/Solosturm/noctalia-shell-main/Services/Compositor"

echo -e "${YELLOW}=== Noctalia Shell - Install LabWC Support ===${NC}"
echo ""
echo "This script will:"
echo "  1. Backup original CompositorService.qml"
echo "  2. Copy modified CompositorService.qml to $INSTALL_DIR"
echo "  3. Copy new LabwcService.qml to $INSTALL_DIR"
echo ""
echo -e "${YELLOW}Installation directory:${NC} $INSTALL_DIR"
echo ""

# Check if source files exist
if [ ! -f "$SOURCE_DIR/CompositorService.qml" ]; then
    echo -e "${RED}Error: Source file not found: $SOURCE_DIR/CompositorService.qml${NC}"
    exit 1
fi

if [ ! -f "$SOURCE_DIR/LabwcService.qml" ]; then
    echo -e "${RED}Error: Source file not found: $SOURCE_DIR/LabwcService.qml${NC}"
    exit 1
fi

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run with sudo${NC}"
    echo "Usage: sudo bash install-to-system.sh"
    exit 1
fi

echo -e "${GREEN}✓${NC} Source files found"
echo ""

# Step 1: Backup original
echo "Step 1: Backing up original CompositorService.qml..."
if [ -f "$INSTALL_DIR/CompositorService.qml.backup" ]; then
    echo -e "${YELLOW}  Warning: Backup already exists, skipping...${NC}"
else
    cp "$INSTALL_DIR/CompositorService.qml" "$INSTALL_DIR/CompositorService.qml.backup"
    echo -e "${GREEN}✓${NC} Backup created: CompositorService.qml.backup"
fi
echo ""

# Step 2: Copy modified CompositorService.qml
echo "Step 2: Installing modified CompositorService.qml..."
cp "$SOURCE_DIR/CompositorService.qml" "$INSTALL_DIR/CompositorService.qml"
chown root:root "$INSTALL_DIR/CompositorService.qml"
chmod 644 "$INSTALL_DIR/CompositorService.qml"
echo -e "${GREEN}✓${NC} CompositorService.qml updated"
echo ""

# Step 3: Copy new LabwcService.qml
echo "Step 3: Installing new LabwcService.qml..."
cp "$SOURCE_DIR/LabwcService.qml" "$INSTALL_DIR/LabwcService.qml"
chown root:root "$INSTALL_DIR/LabwcService.qml"
chmod 644 "$INSTALL_DIR/LabwcService.qml"
echo -e "${GREEN}✓${NC} LabwcService.qml installed"
echo ""

# Verify installation
echo "Verification:"
echo "  Installed files:"
ls -lh "$INSTALL_DIR/CompositorService.qml"
ls -lh "$INSTALL_DIR/LabwcService.qml"
echo ""
echo "  Backup file:"
ls -lh "$INSTALL_DIR/CompositorService.qml.backup"
echo ""

echo -e "${GREEN}=== Installation Complete! ===${NC}"
echo ""
echo "Next steps:"
echo "  1. Log out of your current session"
echo "  2. Log back into labwc"
echo "  3. noctalia-shell should auto-start with labwc support"
echo ""
echo "Check logs with:"
echo "  journalctl --user -u quickshell -f"
echo "Or:"
echo "  tail -f ~/.local/state/quickshell/by-id/*/log.qslog"
echo ""
echo "To restore original files:"
echo "  sudo cp $INSTALL_DIR/CompositorService.qml.backup $INSTALL_DIR/CompositorService.qml"
echo "  sudo rm $INSTALL_DIR/LabwcService.qml"
echo ""
