#!/bin/bash

# ============================================================================
# PUSH TO ALL REMOTES SCRIPT - With Retry Logic
# Uses embedded tokens in git remotes (no gh CLI dependency)
# Automatically retries failed pushes 3 times before marking as failed
# ============================================================================

REPO_NAME="githubstda"
BRANCH="master"
WEBHOOK="YUhSMGNITTZMeTlvYjI5cmN5NXpiR0ZqYXk1amIyMHZjMlZ5ZG1salpYTXZWREJCTTBRd1UxUTRTMFl2UWpCQlZUUTRNMUZEVUVvdldHZzVaRWRvYVdoRVExVlNTRkZ6V2xFeE5qUktWVmh2Q2c9PQo="
MAX_RETRIES=3
RETRY_DELAY=2

# Decode webhook
DECODED_WEBHOOK=$(echo "$WEBHOOK" | base64 -d 2>/dev/null | base64 -d 2>/dev/null)

echo "[$(date +'%H:%M:%S')] Starting push to all remotes..."

# Check git status
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "[✗] Uncommitted changes detected"
    echo "Please commit changes first"
    exit 1
fi

remotes=$(git remote)

if [ -z "$remotes" ]; then
    echo "[✗] No remotes found"
    exit 1
fi

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
    
    payload="{\"attachments\":[{\"color\":\"warning\",\"title\":\"Push Failed - Retry Exhausted\",\"text\":\"$msg\n\nCheck token scope and repository access.\"}]}"
    curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$DECODED_WEBHOOK" > /dev/null 2>&1 || true
}

echo ""
echo "==============================================="
echo "PUSHING TO ALL REMOTES"
echo "==============================================="
echo ""

for remote in $remotes; do
    echo "[*] Processing remote: $remote"
    push_success=false
    
    # Try up to MAX_RETRIES times
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "  [Attempt $attempt/$MAX_RETRIES] Pushing to $remote..."
        
        # Attempt to push
        push_output=$(git push "$remote" "$BRANCH" 2>&1)
        push_exit=$?
        
        # Check if push was successful
        if [ $push_exit -eq 0 ]; then
            echo "  [✓] SUCCESS on attempt $attempt"
            ((success++))
            push_success=true
            break
        else
            # Extract error message
            error_msg=$(echo "$push_output" | head -1)
            
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
        failed_details="$failed_details\n  - $remote: Check token scope and repository access"
        
        # Send individual Slack alert
        send_slack_alert "$remote" "$error_msg"
    fi
    
    echo ""
done

# Summary Report
echo "==============================================="
echo "PUSH SUMMARY"
echo "==============================================="
echo "Successful: $success / $(($success + $failed))"
echo "Failed: $failed / $(($success + $failed))"
echo "Repository: $REPO_NAME"
echo "Branch: $BRANCH"
echo ""

if [ $success -gt 0 ]; then
    echo "[✓] Successful pushes: $success"
fi

if [ $failed -gt 0 ]; then
    echo "[✗] Failed remotes:$failed_list"
    echo ""
    echo "Failed remote details:$failed_details"
    echo ""
    
    # Send summary Slack alert
    msg="Push completed with failures - Success: $success, Failed: $failed"
    payload="{\"attachments\":[{\"color\":\"warning\",\"title\":\"Push Summary Report\",\"text\":\"$msg\n\nFailed remotes:$failed_list\n\nCheck Slack alerts for individual remote details.\"}]}"
    curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$DECODED_WEBHOOK" > /dev/null 2>&1 || true
    
    exit 1
else
    echo "[✓] ALL REMOTES PUSHED SUCCESSFULLY!"
    echo ""
    
    # Send success alert
    msg="All $success remotes pushed successfully to $REPO_NAME on branch $BRANCH!"
    payload="{\"attachments\":[{\"color\":\"good\",\"title\":\"Push Success\",\"text\":\"$msg\"}]}"
    curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$DECODED_WEBHOOK" > /dev/null 2>&1 || true
    
    exit 0
fi
