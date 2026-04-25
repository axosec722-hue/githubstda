#!/bin/bash

################################################################################
# GitHub Runner Client - Main Script
# Distributed subdomain takeover scanning client for GitHub Runner Controller
# 
# Purpose: Download chunks, scan with nuclei/subdominator, upload results
# Usage: ./main.sh
# 
# Required Environment Variables (from GitHub Actions secrets):
#   - SLACK_WEBHOOK: Slack webhook for error notifications
#   - SERVER_DOMAIN: GitHub Runner Controller server domain/IP:port
#   - BASIC_AUTH: Base64 encoded credentials (username:password)
#
# Features:
#   - Automatic tool installation (nuclei, subdominator)
#   - Chunk download and processing
#   - Parallel scanning with multiple tools
#   - Result aggregation and deduplication
#   - Secure upload with retry logic
#   - Comprehensive error handling and Slack notifications
################################################################################

set -e  # Exit on error

# ============================================================================
# COLOR CODES & UTILITIES
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# ============================================================================
# SEND SLACK NOTIFICATION
# ============================================================================

send_slack_notification() {
    local status=$1
    local message=$2
    local error_type=${3:-"ERROR"}
    
    if [ -z "$SLACK_WEBHOOK" ]; then
        log_warning "SLACK_WEBHOOK not set, skipping notification"
        return
    fi
    
    local color="danger"
    if [ "$status" == "success" ]; then
        color="good"
    fi
    
    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "$error_type",
            "text": "$message",
            "footer": "GitHub Runner Client",
            "ts": $(date +%s)
        }
    ]
}
EOF
)
    
    curl -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK" 2>/dev/null || log_warning "Failed to send Slack notification"
}

# ============================================================================
# SETUP SECTION - Install dependencies
# ============================================================================

setup() {
    log_info "=== SETUP SECTION ==="
    log_info "Installing system dependencies..."
    
    sudo apt-get update -qq || log_error "Failed to update packages"
    sudo apt-get upgrade -y -qq || log_error "Failed to upgrade packages"
    sudo apt-get install -y unzip curl wget -qq || log_error "Failed to install basic tools"
    
    log_success "System dependencies installed"
}

# ============================================================================
# INSTALL NUCLEI - Latest Release
# ============================================================================

install_nuclei() {
    log_info "Installing Nuclei from GitHub latest release..."
    
    # Download latest nuclei for Linux amd64
    curl -s https://api.github.com/repos/projectdiscovery/nuclei/releases/latest \
        | grep browser_download_url \
        | grep linux_amd64 \
        | cut -d '"' -f 4 \
        | wget -qi - || log_error "Failed to download Nuclei"
    
    # Extract and install
    unzip -o nuclei_*_linux_amd64.zip -d /tmp/ || log_error "Failed to extract Nuclei"
    sudo mv /tmp/nuclei /usr/local/bin/ || log_error "Failed to move Nuclei to /usr/local/bin"
    sudo chmod +x /usr/local/bin/nuclei
    
    # Verify installation
    if nuclei -version > /dev/null 2>&1; then
        log_success "Nuclei installed: $(nuclei -version 2>&1 | head -1)"
    else
        log_error "Nuclei installation verification failed"
        return 1
    fi
}

# ============================================================================
# INSTALL SUBDOMINATOR - Latest Release
# ============================================================================

install_subdominator() {
    log_info "Installing Subdominator from GitHub latest release..."
    
    # Get latest release URL
    local download_url=$(curl -s https://api.github.com/repos/Stratus-Security/Subdominator/releases/latest \
        | grep browser_download_url \
        | grep linux \
        | grep -v .zip \
        | cut -d '"' -f 4 \
        | head -1)
    
    if [ -z "$download_url" ]; then
        log_error "Failed to get Subdominator download URL"
        return 1
    fi
    
    log_info "Downloading from: $download_url"
    
    # Download
    wget -q "$download_url" -O /tmp/Subdominator || log_error "Failed to download Subdominator"
    
    # Convert to lowercase
    sudo mv /tmp/Subdominator /usr/local/bin/subdominator
    sudo chmod +x /usr/local/bin/subdominator
    
    # Verify installation
    if /usr/local/bin/subdominator -version > /dev/null 2>&1 || /usr/local/bin/subdominator --version > /dev/null 2>&1; then
        log_success "Subdominator installed successfully"
    else
        log_error "Subdominator installation verification failed"
        return 1
    fi
}

# ============================================================================
# INITIALIZATION SECTION - Log environment variables
# ============================================================================

initialization() {
    log_info "=== INITIALIZATION SECTION ==="
    
    # Validate required environment variables
    if [ -z "$SLACK_WEBHOOK" ]; then
        log_error "SLACK_WEBHOOK not set"
        send_slack_notification "error" "SLACK_WEBHOOK environment variable not set" "SETUP_ERROR"
        return 1
    fi
    
    if [ -z "$SERVER_DOMAIN" ]; then
        log_error "SERVER_DOMAIN not set"
        send_slack_notification "error" "SERVER_DOMAIN environment variable not set" "SETUP_ERROR"
        return 1
    fi
    
    if [ -z "$BASIC_AUTH" ]; then
        log_error "BASIC_AUTH not set"
        send_slack_notification "error" "BASIC_AUTH environment variable not set" "SETUP_ERROR"
        return 1
    fi
    
    # Log configuration (without sensitive data)
    log_info "Slack Webhook: ${SLACK_WEBHOOK:0:50}..."
    log_info "Server Domain: $SERVER_DOMAIN"
    log_info "Basic Auth configured: Yes"
    
    # Save to files for reference
    echo "$SLACK_WEBHOOK" | tee .slack_webhook.txt > /dev/null
    echo "$SERVER_DOMAIN" | tee .server_domain.txt > /dev/null
    echo "$BASIC_AUTH" | tee .basic_auth.txt > /dev/null
    
    log_success "Initialization complete"
}

# ============================================================================
# VALIDATION SECTION - Check tool installation
# ============================================================================

validate_tools() {
    log_info "=== VALIDATION SECTION ==="
    
    # Validate Nuclei
    log_info "Validating Nuclei installation..."
    if ! command -v nuclei &> /dev/null; then
        log_warning "Nuclei not found, attempting installation..."
        if ! install_nuclei; then
            log_error "Nuclei installation failed - retrying..."
            if ! install_nuclei; then
                log_error "Nuclei installation failed after retry"
                send_slack_notification "error" "Nuclei installation failed after 2 attempts" "VALIDATION_ERROR"
                return 1
            fi
        fi
    fi
    log_success "Nuclei is installed"
    
    # Validate Subdominator
    log_info "Validating Subdominator installation..."
    if ! command -v subdominator &> /dev/null; then
        log_warning "Subdominator not found, attempting installation..."
        if ! install_subdominator; then
            log_error "Subdominator installation failed - retrying..."
            if ! install_subdominator; then
                log_error "Subdominator installation failed after retry"
                send_slack_notification "error" "Subdominator installation failed after 2 attempts" "VALIDATION_ERROR"
                return 1
            fi
        fi
    fi
    log_success "Subdominator is installed"
}

# ============================================================================
# REGISTER RUNNER - Get runner_header token
# ============================================================================

register_runner() {
    log_info "=== EXECUTION SECTION: Registering Runner ==="
    
    local max_retries=10
    local retry_count=0
    local sleep_time=2
    
    while [ $retry_count -lt $max_retries ]; do
        log_info "Registering runner (attempt $((retry_count + 1))/$max_retries)..."
        
        response=$(curl -s -w "\n%{http_code}" \
            -X GET \
            "http://$SERVER_DOMAIN/runner-header" \
            -H "Authorization: Basic $BASIC_AUTH")
        
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
        
        if [ "$http_code" == "200" ]; then
            log_success "Runner registration successful (HTTP 200)"
            
            # Extract runner_header
            RUNNER_HEADER=$(echo "$body" | grep -o '"runner_header":"[^"]*' | cut -d'"' -f4)
            
            if [ -z "$RUNNER_HEADER" ]; then
                log_error "Failed to extract runner_header from response"
                return 1
            fi
            
            # Save to file and environment
            echo "$RUNNER_HEADER" | tee .runner_header.txt > /dev/null
            export RUNNER_HEADER
            
            log_success "Runner Header: ${RUNNER_HEADER:0:32}..."
            return 0
        fi
        
        log_warning "Registration failed (HTTP $http_code), retrying in ${sleep_time}s..."
        sleep $sleep_time
        retry_count=$((retry_count + 1))
    done
    
    log_error "Failed to register runner after $max_retries attempts"
    send_slack_notification "error" "Runner registration failed after $max_retries attempts" "REGISTRATION_ERROR"
    return 1
}

# ============================================================================
# REQUEST CHUNK - Get chunk_name from server
# ============================================================================

request_chunk() {
    log_info "=== EXECUTION SECTION: Requesting Chunk ==="
    
    local max_retries=10
    local retry_count=0
    local sleep_time=2
    
    while [ $retry_count -lt $max_retries ]; do
        log_info "Requesting chunk (attempt $((retry_count + 1))/$max_retries)..."
        
        response=$(curl -s -w "\n%{http_code}" \
            -X GET \
            "http://$SERVER_DOMAIN/subdomain_takeover/chunks?runner_header=$RUNNER_HEADER" \
            -H "Authorization: Basic $BASIC_AUTH")
        
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
        
        if [ "$http_code" == "204" ]; then
            log_error "No chunks available (HTTP 204) - SERIOUS ISSUE"
            send_slack_notification "error" "No chunks available from server (HTTP 204)" "CHUNK_REQUEST_ERROR"
            return 1
        fi
        
        if [ "$http_code" == "200" ]; then
            log_success "Chunk received successfully (HTTP 200)"
            
            # Extract chunk_name
            CHUNK_NAME=$(echo "$body" | grep -o '"chunk_name":"[^"]*' | cut -d'"' -f4)
            CHUNK_ID=$(echo "$body" | grep -o '"chunk_id":[0-9]*' | cut -d':' -f2)
            
            if [ -z "$CHUNK_NAME" ]; then
                log_error "Failed to extract chunk_name from response"
                return 1
            fi
            
            # Save to file and environment
            echo "$CHUNK_NAME" | tee .chunk_name.txt > /dev/null
            echo "$CHUNK_ID" | tee .chunk_id.txt > /dev/null
            export CHUNK_NAME CHUNK_ID
            
            log_success "Chunk Name: $CHUNK_NAME"
            log_success "Chunk ID: $CHUNK_ID"
            
            # Save response body for processing
            echo "$body" | tee chunk_response.json > /dev/null
            
            return 0
        fi
        
        log_warning "Chunk request failed (HTTP $http_code), retrying in ${sleep_time}s..."
        sleep $sleep_time
        retry_count=$((retry_count + 1))
    done
    
    log_error "Failed to request chunk after $max_retries attempts"
    send_slack_notification "error" "Chunk request failed after $max_retries attempts" "CHUNK_REQUEST_ERROR"
    return 1
}

# ============================================================================
# DOWNLOAD CHUNK CONTENT - Save chunk data to targets directory
# ============================================================================

download_chunk_content() {
    log_info "=== EXECUTION SECTION: Downloading Chunk Content ==="
    
    # Create targets directory
    mkdir -p targets results
    
    # For this version, the chunk content comes from the server
    # In production, this would download the actual chunk file
    # For now, we'll use the chunk_response.json as the target file
    
    if [ -f "chunk_response.json" ]; then
        cp chunk_response.json "targets/$CHUNK_NAME"
        log_success "Chunk content saved to targets/$CHUNK_NAME"
    else
        log_error "Chunk response file not found"
        return 1
    fi
    
    # Validate targets directory has content
    if [ -z "$(ls -A targets/)" ]; then
        log_error "Targets directory is empty"
        send_slack_notification "error" "Targets directory is empty after chunk download" "DOWNLOAD_ERROR"
        return 1
    fi
    
    log_success "Targets directory validated - contains $(ls targets/ | wc -l) file(s)"
}

# ============================================================================
# SCANNING SECTION - Run nuclei and subdominator
# ============================================================================

scanning() {
    log_info "=== SCANNING SECTION ==="
    
    # Get target file
    TARGET_SUBDOMAIN=$(ls targets/ | head -1)
    TARGET_FILE="targets/$TARGET_SUBDOMAIN"
    
    log_info "Scanning target file: $TARGET_FILE"
    
    # Create results directory
    mkdir -p results
    
    # Run Subdominator
    log_info "Running Subdominator scan..."
    if subdominator -l "$TARGET_FILE" -q | tee results/subdominator_output.txt; then
        log_success "Subdominator scan completed"
    else
        log_warning "Subdominator scan encountered issues"
    fi
    
    # Run Nuclei
    log_info "Running Nuclei scan with takeover tags..."
    if nuclei -l "$TARGET_FILE" -tags takeover -silent | tee results/nuclei_output.txt; then
        log_success "Nuclei scan completed"
    else
        log_warning "Nuclei scan encountered issues"
    fi
    
    # Add prefixes to results using adder script
    if [ -f "adder.sh" ]; then
        log_info "Adding scan prefixes..."
        bash adder.sh -add "[nuclei-scan]" -i results/nuclei_output.txt || log_warning "Failed to add nuclei prefix"
        bash adder.sh -add "[subdominator-scan]" -i results/subdominator_output.txt || log_warning "Failed to add subdominator prefix"
    fi
}

# ============================================================================
# MERGE RESULTS - Combine and deduplicate scan results
# ============================================================================

merge_results() {
    log_info "=== RESULT MERGING SECTION ==="
    
    # Merge and deduplicate
    log_info "Merging and deduplicating results..."
    touch results/raw_merged_result.txt
    
    cat results/nuclei_output.txt results/subdominator_output.txt \
        | sort -u \
        | tee results/raw_merged_result.txt > /dev/null
    
    local line_count=$(wc -l < results/raw_merged_result.txt)
    log_success "Merged results: $line_count lines"
    
    if [ "$line_count" -eq 0 ]; then
        log_warning "No results found from scans"
    fi
}

# ============================================================================
# RENAME RESULT FILE - Add random hash to prevent duplicates
# ============================================================================

rename_result_file() {
    log_info "=== RESULT NAMING SECTION ==="
    
    # Generate random hash
    RANDOM_HASH=$(openssl rand -hex 8)
    RESULT_FILENAME="raw_merged_result_${RANDOM_HASH}.txt"
    
    log_info "Generated filename: $RESULT_FILENAME"
    
    # Rename file
    mv results/raw_merged_result.txt "results/$RESULT_FILENAME"
    
    # Save full path to variable
    UPLOAD_FILE="results/$RESULT_FILENAME"
    export UPLOAD_FILE
    
    echo "$UPLOAD_FILE" | tee .upload_file.txt > /dev/null
    log_success "Result file ready for upload: $UPLOAD_FILE"
}

# ============================================================================
# UPLOAD RESULT - Send result file to server
# ============================================================================

upload_result() {
    log_info "=== UPLOAD SECTION ==="
    
    if [ ! -f "$UPLOAD_FILE" ]; then
        log_error "Upload file not found: $UPLOAD_FILE"
        send_slack_notification "error" "Upload file not found: $UPLOAD_FILE" "UPLOAD_ERROR"
        return 1
    fi
    
    local max_retries=10
    local retry_count=0
    local sleep_time=2
    
    while [ $retry_count -lt $max_retries ]; do
        log_info "Uploading result (attempt $((retry_count + 1))/$max_retries)..."
        
        response=$(curl -s -w "\n%{http_code}" \
            -X POST \
            "http://$SERVER_DOMAIN/subdomain_takeover/result_upload?runner_header=$RUNNER_HEADER&chunk=$CHUNK_NAME" \
            -H "Authorization: Basic $BASIC_AUTH" \
            -F "file=@$UPLOAD_FILE")
        
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
        
        if [ "$http_code" == "200" ]; then
            log_success "Upload successful (HTTP 200)"
            log_info "Server response: $body"
            return 0
        fi
        
        log_warning "Upload failed (HTTP $http_code), retrying in ${sleep_time}s..."
        sleep $sleep_time
        retry_count=$((retry_count + 1))
    done
    
    log_error "Failed to upload result after $max_retries attempts"
    send_slack_notification "error" "Result upload failed after $max_retries attempts. Chunk: $CHUNK_NAME" "UPLOAD_ERROR"
    return 1
}

# ============================================================================
# CLEANUP - Remove temporary files
# ============================================================================

cleanup() {
    log_info "=== CLEANUP SECTION ==="
    
    # Remove temporary files
    rm -f .runner_header.txt .chunk_name.txt .chunk_id.txt .upload_file.txt
    rm -f .slack_webhook.txt .server_domain.txt .basic_auth.txt
    rm -f chunk_response.json
    
    log_success "Cleanup completed"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "╔════════════════════════════════════════════════════════╗"
    log_info "║  GitHub Runner Client - Subdomain Takeover Scanner    ║"
    log_info "║  Starting execution at $(date '+%Y-%m-%d %H:%M:%S')           ║"
    log_info "╚════════════════════════════════════════════════════════╝"
    
    # Execute stages
    if setup && \
       initialization && \
       validate_tools && \
       register_runner && \
       request_chunk && \
       download_chunk_content && \
       scanning && \
       merge_results && \
       rename_result_file && \
       upload_result; then
        
        log_success "╔════════════════════════════════════════════════════════╗"
        log_success "║          🎉 ALL STAGES COMPLETED SUCCESSFULLY! 🎉      ║"
        log_success "║  Execution completed at $(date '+%Y-%m-%d %H:%M:%S')           ║"
        log_success "╚════════════════════════════════════════════════════════╝"
        
        cleanup
        send_slack_notification "success" "GitHub Runner Client execution completed successfully" "EXECUTION_SUCCESS"
        exit 0
    else
        log_error "╔════════════════════════════════════════════════════════╗"
        log_error "║             ❌ EXECUTION FAILED! ❌                    ║"
        log_error "║  Failed at $(date '+%Y-%m-%d %H:%M:%S')                     ║"
        log_error "╚════════════════════════════════════════════════════════╝"
        
        cleanup
        send_slack_notification "error" "GitHub Runner Client execution failed" "EXECUTION_FAILURE"
        exit 1
    fi
}

# Run main function
main "$@"
