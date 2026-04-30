#!/bin/bash

# ============================================================================
# PUSH TO ALL REMOTES SCRIPT - With Auto-Commit + Retry Logic
# Features:
# - Automatically stages and commits all changes with random message
# - Uses embedded tokens in git remotes (no gh CLI dependency)
# - Automatically retries failed pushes 3 times before marking as failed
# - Sends Slack alerts on success/failure
# ============================================================================

REPO_NAME="githubstda"
BRANCH="master"
WEBHOOK="YUhSMGNITTZMeTlvYjI5cmN5NXpiR0ZqYXk1amIyMHZjMlZ5ZG1salpYTXZWREJCTTBRd1UxUTRTMFl2UWpCQlZUUTRNMUZEVUVvdldHZzVaRWRvYVdoRVExVlNTRkZ6V2xFeE5qUktWVmh2Q2c9PQo="
MAX_RETRIES=3
RETRY_DELAY=2

# Random commit message generators
generate_commit_message() {
    local messages=(
        "Update: Auto-commit $(date +'%s')"
        "Sync changes at $(date +'%H:%M:%S')"
        "Automated push: $(date +'%Y-%m-%d')"
        "Batch update with timestamp $(date +'%s')"
        "Deploy changes: $(date +'%s | %H:%M:%S')"
        "Scheduled commit $(date +'%Y-%m-%d %H:%M:%S')"
        "Auto-sync repository $(date +'%s')"
        "Pipeline update $(date +'%Y-%m-%d')"
    )
    local index=$((RANDOM % ${#messages[@]}))
    echo "${messages[$index]}"
}

# Decode webhook
DECODED_WEBHOOK=$(echo "$WEBHOOK" | base64 -d 2>/dev/null | base64 -d 2>/dev/null)

echo "[$(date +'%H:%M:%S')] Starting auto-commit and push to all remotes..."
echo ""

# Verify branch exists
if ! git rev-parse --verify "$BRANCH" > /dev/null 2>&1; then
    echo "[✗] Branch '$BRANCH' does not exist"
    echo "Available branches:"
    git branch -a
    exit 1
fi

# Verify branch exists
if ! git rev-parse --verify "$BRANCH" > /dev/null 2>&1; then
    echo "[✗] Branch '$BRANCH' does not exist"
    echo "Available branches:"
    git branch -a
    exit 1
fi

remotes=$(git remote)

if [ -z "$remotes" ]; then
    echo "[✗] No remotes found"
    exit 1
fi

# ============================================================================
# PHASE 1: AUTO-COMMIT CHANGES
# ============================================================================

echo "==============================================="
echo "PHASE 1: GIT AUTO-COMMIT"
echo "==============================================="
echo ""

# Check if there are any changes to commit
if git diff-index --quiet HEAD -- 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "[ℹ] No changes detected - proceeding with push"
else
    echo "[*] Staging all changes..."
    git add .
    
    if [ $? -ne 0 ]; then
        echo "[✗] Failed to stage changes"
        exit 1
    fi
    
    # Generate random commit message
    COMMIT_MSG=$(generate_commit_message)
    echo "[*] Generated commit message: '$COMMIT_MSG'"
    
    # Commit changes
    git commit -m "$COMMIT_MSG" 2>&1 | sed 's/^/  /'
    
    if [ $? -ne 0 ]; then
        echo "[✗] Failed to commit changes"
        exit 1
    fi
    
    echo "[✓] Successfully committed changes"
fi

echo ""

success=0
failed=0
failed_list=""
failed_details=""

# Helper function to send Slack alert for individual remote failure
send_slack_alert() {
    local remote_name="$1"
    local error_msg="$2"
    local msg="Remote '$remote_name' failed after $MAX_RETRIES attempts"
    
    if [ -n "$error_msg" ]; then
        msg="$msg: $error_msg"
    fi
    
    # Escape special characters for JSON
    msg=$(printf '%s\n' "$msg" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
    
    payload="{\"attachments\":[{\"color\":\"danger\",\"title\":\"Push Failed - Retry Exhausted\",\"text\":\"$msg\",\"fields\":[{\"title\":\"Remote\",\"value\":\"$remote_name\",\"short\":true},{\"title\":\"Max Retries\",\"value\":\"$MAX_RETRIES\",\"short\":true},{\"title\":\"Repository\",\"value\":\"$REPO_NAME\",\"short\":true},{\"title\":\"Branch\",\"value\":\"$BRANCH\",\"short\":true}]}]}"
    
    if [ -n "$DECODED_WEBHOOK" ]; then
        curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$DECODED_WEBHOOK" > /dev/null 2>&1 || echo "[⚠] Warning: Failed to send Slack alert for $remote_name"
    fi
}

echo ""
echo "==============================================="
echo "PHASE 2: PUSH TO ALL REMOTES WITH RETRY LOGIC"
echo "==============================================="
echo ""

for remote in $remotes; do
    echo "[*] Processing remote: $remote"
    push_success=false
    
    # Try up to MAX_RETRIES times
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "  [Attempt $attempt/$MAX_RETRIES] Pushing to $remote..."
        
        # Attempt to push (use bash process substitution for non-blocking timeout on macOS)
        push_output=$(git push "$remote" "$BRANCH" 2>&1)
        push_exit=$?
        
        # Check if push was successful
        if [ $push_exit -eq 0 ]; then
            echo "  [✓] SUCCESS on attempt $attempt"
            ((success++))
            push_success=true
            break
        else
            # Extract last error line (usually more complete)
            error_msg=$(echo "$push_output" | tail -1)
            
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "  [✗] Failed on attempt $attempt, waiting ${RETRY_DELAY}s before retry..."
                echo "      Error: $error_msg"
                sleep $RETRY_DELAY
            else
                echo "  [✗] FAILED after $MAX_RETRIES attempts"
                echo "      Error: $error_msg"
            fi
        fi
    done
    
    # If all retries failed, log and alert
    if [ "$push_success" = false ]; then
        ((failed++))
        failed_list="$failed_list $remote"
        failed_details_line="  - $remote: $error_msg"
        [ -z "$failed_details" ] && failed_details="$failed_details_line" || failed_details="$failed_details"$'\n'"$failed_details_line"
        
        # Send individual Slack alert
        send_slack_alert "$remote" "$error_msg"
    fi
    
    echo ""
done

# Summary Report
echo "==============================================="
echo "EXECUTION SUMMARY"
echo "==============================================="
echo "Successful: $success / $(($success + $failed))"
echo "Failed: $failed / $(($success + $failed))"
echo "Repository: $REPO_NAME"
echo "Branch: $BRANCH"
echo "Timestamp: $(date +'%Y-%m-%d %H:%M:%S')"
echo ""

if [ $success -gt 0 ]; then
    echo "[✓] Successful pushes: $success"
fi

if [ $failed -gt 0 ]; then
    echo "[✗] Failed remotes:$failed_list"
    echo ""
    echo "Failed remote details:"
    echo -e "$failed_details"
    echo ""
    
    # Send summary Slack alert with proper formatting
    msg="Push completed with failures\\nSuccess: $success / $(($success + $failed))\\nFailed: $failed / $(($success + $failed))"
    failed_list_escaped=$(printf '%s\n' "$failed_list" | sed 's/"/\\"/g')
    payload="{\"attachments\":[{\"color\":\"danger\",\"title\":\"Push Summary - Failures Detected\",\"text\":\"$msg\",\"fields\":[{\"title\":\"Failed Remotes\",\"value\":\"$failed_list_escaped\",\"short\":false},{\"title\":\"Repository\",\"value\":\"$REPO_NAME\",\"short\":true},{\"title\":\"Branch\",\"value\":\"$BRANCH\",\"short\":true}]}]}"
    
    if [ -n "$DECODED_WEBHOOK" ]; then
        curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$DECODED_WEBHOOK" > /dev/null 2>&1 || echo "[⚠] Warning: Failed to send Slack summary alert"
    fi
    
    exit 1
else
    echo "[✓] ALL REMOTES PUSHED SUCCESSFULLY!"
    echo ""
    
    # Send success alert with rich formatting
    msg="All $success remotes pushed successfully!\\nRepository: $REPO_NAME\\nBranch: $BRANCH\\nTimestamp: $(date +'%Y-%m-%d %H:%M:%S')"
    payload="{\"attachments\":[{\"color\":\"good\",\"title\":\"Push Success\",\"text\":\"$msg\"}]}"
    
    if [ -n "$DECODED_WEBHOOK" ]; then
        curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$DECODED_WEBHOOK" > /dev/null 2>&1 || echo "[⚠] Warning: Failed to send Slack success alert"
    fi
    
    exit 0
fi
