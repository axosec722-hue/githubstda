#!/bin/bash

################################################################################
# Adder Script - Add prefixes/suffixes to file content
# 
# Purpose: Add prefixes to scan results for identification
# Usage: ./adder.sh -add "[prefix]" -i input_file
################################################################################

set -e

# ============================================================================
# COLORS & UTILITIES
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

PREFIX=""
INPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -add)
            PREFIX="$2"
            shift 2
            ;;
        -i)
            INPUT_FILE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: ./adder.sh -add \"[prefix]\" -i input_file"
            exit 1
            ;;
    esac
done

# ============================================================================
# VALIDATION
# ============================================================================

if [ -z "$PREFIX" ]; then
    log_error "Prefix not specified"
    echo "Usage: ./adder.sh -add \"[prefix]\" -i input_file"
    exit 1
fi

if [ -z "$INPUT_FILE" ]; then
    log_error "Input file not specified"
    echo "Usage: ./adder.sh -add \"[prefix]\" -i input_file"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    log_error "Input file not found: $INPUT_FILE"
    exit 1
fi

# ============================================================================
# ADD PREFIX TO EACH LINE
# ============================================================================

log_info "Adding prefix \"$PREFIX\" to $INPUT_FILE..."

# Create temporary file
TEMP_FILE="${INPUT_FILE}.tmp"

# Add prefix to each non-empty line
while IFS= read -r line; do
    if [ -n "$line" ]; then
        echo "$PREFIX $line" >> "$TEMP_FILE"
    fi
done < "$INPUT_FILE"

# Replace original file
mv "$TEMP_FILE" "$INPUT_FILE"

log_success "Prefix added successfully"
log_info "Lines processed: $(wc -l < "$INPUT_FILE")"

exit 0
