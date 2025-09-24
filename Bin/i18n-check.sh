#!/bin/bash

# Noctalia Shell i18n Checker
# Scans for hardcoded strings that need internationalization

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}Noctalia Shell i18n Checker${NC}"
echo -e "${BLUE}===========================${NC}"

files_with_issues=0

# Check a single file
check_file() {
    local file="$1"
    local issues=$(grep -n -E '(label|text|title|description|tooltip|placeholder):\s*"[^"]{3,}"' "$file" | grep -v 'I18n.tr')
    
    if [[ -n "$issues" ]]; then
        echo -e "${YELLOW}$file${NC}"
        echo "$issues" | sed 's/^/  /'
        echo ""
        return 1
    fi
    return 0
}

echo "Scanning QML files..."
echo ""

# Find and check QML files
qml_files=$(find . -name "*.qml" -type f \
    ! -path "./Assets/*" \
    ! -path "./Bin/*" \
    ! -path "./Shaders/*" \
    ! -path "./Helpers/*" \
    ! -path "./.git/*")

total_files=$(echo "$qml_files" | wc -l)

for file in $qml_files; do
    if ! check_file "$file"; then
        ((files_with_issues++))
    fi
done

# Summary
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}=======${NC}"
echo -e "Files scanned: $total_files"
echo -e "Files needing i18n: $files_with_issues"

if [[ $files_with_issues -eq 0 ]]; then
    echo -e "${GREEN}All files use I18n.tr() properly!${NC}"
else
    echo -e "${YELLOW}$files_with_issues files have potential hardcoded strings${NC}"
fi