#!/bin/bash

# Comprehensive i18n checker for Noctalia Shell
# Finds hardcoded strings that should be internationalized

check_file() {
    local file="$1"
    
    # Check for hardcoded strings in common properties
    # Includes: label, text, title, description, tooltip, tooltipText, placeholder, placeholderText
    local property_issues=$(grep -n -E '(label|text|title|description|tooltip|tooltipText|placeholder|placeholderText):\s*"[^"]{3,}"' "$file" | grep -v 'I18n.tr')
    
    # Check for hardcoded strings in dialog titles and button texts
    local dialog_issues=$(grep -n -E '(dialog\.|Dialog\.|title:|buttonText:)\s*"[^"]{3,}"' "$file" | grep -v 'I18n.tr')
    
    # Check for hardcoded strings in model name properties (for combo boxes)
    local model_issues=$(grep -n -E 'name:\s*"[^"]{3,}"' "$file" | grep -v 'I18n.tr')
    
    # Check for hardcoded strings in common UI text patterns
    local ui_issues=$(grep -n -E '"[^"]*\b(click|open|close|enable|disable|show|hide|settings|cancel|apply|ok|save|load|start|stop|play|pause|next|previous|volume|brightness|wifi|bluetooth|notification|wallpaper|profile|power|session|menu|panel|dialog|button|toggle|slider|checkbox|radio|combo|input|search|filter|sort|refresh|update|delete|remove|add|create|edit|modify|copy|paste|cut|undo|redo|help|about|info|warning|error|success|failed|loading|connecting|connected|disconnected|scanning|pairing|recording|playing|paused|stopped|muted|unmuted|enabled|disabled|on|off|yes|no|true|false)\b[^"]*"' "$file" | grep -v 'I18n.tr' | grep -v '//' | grep -v '/*')
    
    # Combine all issues
    local all_issues="$property_issues"
    if [[ -n "$dialog_issues" ]]; then
        all_issues="$all_issues"$'\n'"$dialog_issues"
    fi
    if [[ -n "$model_issues" ]]; then
        all_issues="$all_issues"$'\n'"$model_issues"
    fi
    if [[ -n "$ui_issues" ]]; then
        all_issues="$all_issues"$'\n'"$ui_issues"
    fi
    
    # Remove empty lines and duplicates
    all_issues=$(echo "$all_issues" | grep -v '^$' | sort -u)
    
    if [[ -n "$all_issues" ]]; then
        echo "$file"
        echo "$all_issues" | while IFS= read -r line; do
            echo "  $line"
        done
        echo
    fi
}

echo "Comprehensive i18n Checker"
echo "========================="
echo "Scanning QML files for hardcoded strings..."
echo

found_issues=false

while IFS= read -r -d '' file; do
    if check_file "$file" | grep -q .; then
        check_file "$file"
        found_issues=true
    fi
done < <(find . -name "*.qml" -not -path "./Assets/*" -print0)

if [[ "$found_issues" == false ]]; then
    echo "No hardcoded strings found! All strings appear to be internationalized."
else
    echo "Note: Review each match manually - some may be false positives"
    echo "(property names, IDs, technical values, comments shouldn't be translated)"
fi
