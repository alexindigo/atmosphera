#!/bin/bash

# JSON Language File Comparison Script
# Compares language files against en.json reference and generates a report

set -euo pipefail

# Configuration
FOLDER_PATH="Assets/Translations"
REFERENCE_FILE="en.json"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if jq is installed
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        print_color $RED "Error: 'jq' is required but not installed. Please install jq first." >&2
        print_color $YELLOW "On Ubuntu/Debian: sudo apt-get install jq" >&2
        print_color $YELLOW "On CentOS/RHEL: sudo yum install jq" >&2
        print_color $YELLOW "On macOS: brew install jq" >&2
        exit 1
    fi
}

# Function to extract all keys from a JSON file recursively
extract_keys() {
    local json_file=$1
    
    if [[ ! -f "$json_file" ]]; then
        echo "Error: File $json_file not found" >&2
        return 1
    fi
    
    # Extract all keys recursively using jq
    jq -r '
        def keys_recursive:
            if type == "object" then
                keys[] as $k |
                if (.[$k] | type) == "object" then
                    ($k + "." + (.[$k] | keys_recursive))
                else
                    $k
                end
            else
                empty
            end;
        keys_recursive
    ' "$json_file" 2>/dev/null | sort
}

# Function to get language files
get_language_files() {
    find "$FOLDER_PATH" -maxdepth 1 -name "*.json" -type f | sort
}

# Function to generate report header
generate_header() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat << EOF
================================================================================
                     LANGUAGE FILE COMPARISON REPORT
================================================================================
Generated: $timestamp
Reference file: $REFERENCE_FILE
Folder: $(realpath "$FOLDER_PATH")

This report compares all language JSON files against the English reference file
and identifies missing keys and extra keys in each language.

EOF
}

# Function to compare keys and generate report section
compare_language() {
    local lang_file=$1
    local lang_name=$2
    local ref_keys_file=$3
    
    local lang_keys_file=$(mktemp)
    extract_keys "$lang_file" > "$lang_keys_file"
    
    local missing_keys=$(comm -23 "$ref_keys_file" "$lang_keys_file")
    local extra_keys=$(comm -13 "$ref_keys_file" "$lang_keys_file")
    
    local missing_count=$(echo "$missing_keys" | grep -v '^$' | wc -l)
    local extra_count=$(echo "$extra_keys" | grep -v '^$' | wc -l)
    local total_ref_keys=$(wc -l < "$ref_keys_file")
    local total_lang_keys=$(wc -l < "$lang_keys_file")
    
    # Calculate completion percentage
    local completion_percentage=0
    if [[ $total_ref_keys -gt 0 ]]; then
        completion_percentage=$(( (total_ref_keys - missing_count) * 100 / total_ref_keys ))
    fi
    
    cat << EOF
================================================================================
LANGUAGE: $lang_name
================================================================================
File: $lang_file
Total keys in reference (en): $total_ref_keys
Total keys in $lang_name: $total_lang_keys
Translation completion: ${completion_percentage}%

SUMMARY:
- Missing keys (exist in English but not in $lang_name): $missing_count
- Extra keys (exist in $lang_name but not in English): $extra_count

EOF

    if [[ $missing_count -gt 0 ]]; then
        cat << EOF
MISSING KEYS IN $lang_name:
$(echo "$missing_keys" | grep -v '^$' | sed 's/^/  /')

EOF
    else
        echo "✅ No missing keys in $lang_name"
        echo ""
    fi
    
    if [[ $extra_count -gt 0 ]]; then
        cat << EOF
EXTRA KEYS IN $lang_name (not in English):
$(echo "$extra_keys" | grep -v '^$' | sed 's/^/  /')

EOF
    else
        echo "✅ No extra keys in $lang_name"
        echo ""
    fi
    
    # Clean up
    rm -f "$lang_keys_file"
}

# Main function
main() {
    print_color $BLUE "Starting language file comparison..." >&2
    
    # Check dependencies
    check_dependencies
    
    # Validate folder path
    if [[ ! -d "$FOLDER_PATH" ]]; then
        print_color $RED "Error: Folder '$FOLDER_PATH' does not exist" >&2
        exit 1
    fi
    
    # Check if reference file exists
    local ref_file_path="$FOLDER_PATH/$REFERENCE_FILE"
    if [[ ! -f "$ref_file_path" ]]; then
        print_color $RED "Error: Reference file '$ref_file_path' does not exist" >&2
        exit 1
    fi
    
    print_color $GREEN "Reference file found: $ref_file_path" >&2
    
    # Extract keys from reference file
    local ref_keys_file=$(mktemp)
    extract_keys "$ref_file_path" > "$ref_keys_file"
    local total_ref_keys=$(wc -l < "$ref_keys_file")
    
    print_color $BLUE "Extracted $total_ref_keys keys from reference file" >&2
    
    # Get all language files
    local language_files=($(get_language_files))
    
    if [[ ${#language_files[@]} -eq 0 ]]; then
        print_color $RED "Error: No JSON files found in $FOLDER_PATH" >&2
        rm -f "$ref_keys_file"
        exit 1
    fi
    
    print_color $BLUE "Found ${#language_files[@]} JSON files to process" >&2
    echo "" >&2
    
    # Generate report header
    generate_header
    
    local processed=0
    for lang_file in "${language_files[@]}"; do
        local filename=$(basename "$lang_file")
        local lang_name="${filename%.json}"
        
        # Skip the reference file
        if [[ "$filename" == "$REFERENCE_FILE" ]]; then
            continue
        fi
        
        print_color $YELLOW "Processing: $filename" >&2
        
        # Validate JSON syntax
        if ! jq empty "$lang_file" 2>/dev/null; then
            print_color $RED "Warning: $lang_file contains invalid JSON syntax. Skipping..." >&2
            echo "ERROR: $lang_file contains invalid JSON syntax and was skipped."
            echo ""
            continue
        fi
        
        compare_language "$lang_file" "$lang_name" "$ref_keys_file"
        processed=$((processed + 1))
    done
    
    # Add summary at the end
    cat << EOF
================================================================================
SUMMARY
================================================================================
Total files processed: $processed
Reference file: $REFERENCE_FILE (English)
Report generated: $(date '+%Y-%m-%d %H:%M:%S')

Notes:
- Keys are compared recursively through all nested JSON objects
- Missing keys indicate incomplete translations
- Extra keys might indicate deprecated keys or translation-specific additions
- Translation completion percentage is calculated based on English reference

================================================================================
EOF
    
    # Clean up
    rm -f "$ref_keys_file"
    
    print_color $GREEN "Comparison completed: Processed $processed language files against English reference" >&2
}

# Usage information
show_usage() {
    echo "Usage: $0" >&2
    echo "" >&2
    echo "This script compares JSON language files in '$FOLDER_PATH' against the English reference." >&2
    echo "" >&2
    echo "Configuration:" >&2
    echo "  - Folder path: $FOLDER_PATH (hardcoded)" >&2
    echo "  - Reference file: $REFERENCE_FILE" >&2
    echo "" >&2
    echo "Requirements:" >&2
    echo "  - jq must be installed" >&2
    echo "  - $REFERENCE_FILE must exist in $FOLDER_PATH" >&2
    echo "" >&2
    echo "Output:" >&2
    echo "  - Comparison report is printed to stdout" >&2
    echo "  - Progress messages are printed to stderr" >&2
}

# Handle command line arguments
if [[ $# -gt 0 ]]; then
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    else
        echo "Error: This script does not accept arguments." >&2
        echo "" >&2
        show_usage
        exit 1
    fi
fi

# Run main function
main