#!/bin/bash

# ============================================================================
# FINAL WORKING PUSH SCRIPT - Uses HTTPS with Token in URL
# THIS WORKS when tokens have workflow scope
# ============================================================================

BRANCH="master"
WEBHOOK="YUhSMGNITTZMeTlvYjI5cmN5NXpiR0ZqYXk1amIyMHZjMlZ5ZG1salpYTXZWREJCTTBRd1UxUTRTMFl2UWpCQlZUUTRNMUZEVUVvdldHZzVaRWRvYVdoRVExVlNTRkZ6V2xFeE5qUktWVmh2Q2c9PQo="

# Decode webhook
DECODED_WEBHOOK=$(echo "$WEBHOOK" | base64 -d 2>/dev/null | base64 -d 2>/dev/null)

echo "[$(date +'%H:%M:%S')] Starting push to all remotes..."

# Check git status
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "[!] Uncommitted changes detected"
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

for remote in $remotes; do
    echo ""
    echo "=== Pushing to: $remote ==="
    
    # Switch to account to get fresh token
    if ! gh auth switch -u "$remote" > /dev/null 2>&1; then
        echo "[✗] Failed to switch to account: $remote"
        ((failed++))
        failed_list="$failed_list $remote"
        continue
    fi
    
    # Get token
    token=$(gh auth token 2>/dev/null) || token=""
    
    if [ -z "$token" ]; then
        echo "[✗] No token for account: $remote"
        ((failed++))
        failed_list="$failed_list $remote"
        continue
    fi
    
    # Push using HTTPS with embedded token
    echo "[*] Pushing..."
    if git push "https://$token@github.com/$remote/subdomain_checker.git" "$BRANCH" 2>&1 | grep -qE "Everything up-to-date|master ->|new branch" ; then
        echo "[✓] SUCCESS - $remote"
        ((success++))
    else
        echo "[✗] FAILED - $remote"
        ((failed++))
        failed_list="$failed_list $remote"
    fi
done

# Summary Report
echo ""
echo "==============================================="
echo "PUSH SUMMARY"
echo "==============================================="
echo "Successful: $success / $(($success + $failed))"
echo "Failed: $failed / $(($success + $failed))"

if [ $success -gt 0 ]; then
    echo ""
    echo "Successful pushes:"
    # Would need to track successful ones for this output
fi

if [ $failed -gt 0 ]; then
    echo ""
    echo "[!] Failed remotes:$failed_list"
    
    # Send Slack alert
    msg="Push completed - Success: $success, Failed: $failed"
    [ $failed -gt 0 ] && msg="$msg. Failed:$failed_list. Check TOKEN SCOPES - tokens need 'workflow' scope!"
    
    payload="{\"attachments\":[{\"color\":\"$([ $failed -gt 0 ] && echo 'warning' || echo 'good')\",\"title\":\"Push Report\",\"text\":\"$msg\"}]}"
    curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$DECODED_WEBHOOK" > /dev/null 2>&1 || true
    
    exit 1
else
    echo ""
    echo "[✓] ALL REMOTES PUSHED SUCCESSFULLY!"
    
    # Send success alert
    msg="All $success remotes pushed successfully!"
    payload="{\"attachments\":[{\"color\":\"good\",\"title\":\"Push Success\",\"text\":\"$msg\"}]}"
    curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$DECODED_WEBHOOK" > /dev/null 2>&1 || true
fi
