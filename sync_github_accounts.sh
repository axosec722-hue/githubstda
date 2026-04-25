#!/bin/bash

# ============================================================================
# GITHUB ACCOUNT SYNC SCRIPT - With proper token handling
# ============================================================================

REPO_NAME="subdomain_checker"
BRANCH="master"
WEBHOOK="YUhSMGNITTZMeTlvYjI5cmN5NXpiR0ZqYXk1amIyMHZjMlZ5ZG1salpYTXZWREJCTTBRd1UxUTRTMFl2UWpCQlZUUTRNMUZEVUVvdldHZzVaRWRvYVdoRVExVlNTRkZ6V2xFeE5qUktWVmh2Q2c9PQo="
URLS_FILE="github_repo_urls.txt"
NEW_URLS_FILE="github_repo_new_urls.txt"

DECODED_WEBHOOK=$(echo "$WEBHOOK" | base64 -d 2>/dev/null | base64 -d 2>/dev/null)

echo "[$(date +'%H:%M:%S')] Starting GitHub account sync..."

# Check git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "[✗] Not in a git repository"
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "[✗] Uncommitted changes detected"
    exit 1
fi

# Get all users
echo "[*] Extracting GitHub users..."
users=$(gh auth status 2>&1 | grep "✓ Logged in" | awk '{print $5}' | tr -d '()')

if [ -z "$users" ]; then
    echo "[✗] No GitHub users found"
    exit 1
fi

user_count=$(echo "$users" | wc -l)
echo "[*] Found $user_count user(s)"
echo ""

# Initialize tracking
: > "$NEW_URLS_FILE"
new_count=0
existing_count=0
failed_count=0

# Process each user
while read -r user; do
    if [ -z "$user" ]; then
        continue
    fi
    
    echo "Processing: $user"
    
    # Switch account
    if ! gh auth switch -u "$user" > /dev/null 2>&1; then
        echo "  [✗] Failed to switch account"
        ((failed_count++))
        continue
    fi
    
    # Check if repo exists
    if gh repo view "$user/$REPO_NAME" --json name > /dev/null 2>&1; then
        echo "  [!] Repo already exists (existing account)"
        ((existing_count++))
    else
        echo "  [+] Creating repo..."
        
        if gh repo create "$REPO_NAME" --public --description "Subdomain checker repository" --clone=false > /dev/null 2>&1; then
            echo "  [✓] Repo created"
            ((new_count++))
            
            # Get token
            token=$(gh auth token 2>/dev/null) || token=""
            
            if [ -z "$token" ]; then
                echo "  [✗] Failed to get token"
                ((failed_count++))
                continue
            fi
            
            # Add remote
            if ! git remote get-url "$user" > /dev/null 2>&1; then
                git remote add "$user" "https://github.com/$user/$REPO_NAME.git"
                echo "  [✓] Remote added"
            fi
            
            # Push to new repo
            echo "  [*] Pushing code..."
            if git push "https://$token@github.com/$user/$REPO_NAME.git" "$BRANCH" 2>&1 | grep -qE "new branch|master ->" ; then
                echo "  [✓] Code pushed"
                
                # Save URL
                echo "https://github.com/$user/$REPO_NAME" >> "$NEW_URLS_FILE"
                echo "https://github.com/$user/$REPO_NAME" >> "$URLS_FILE"
            else
                echo "  [✗] Push failed (check if token has 'workflow' scope)"
                ((failed_count++))
            fi
        else
            echo "  [✗] Failed to create repo"
            ((failed_count++))
        fi
    fi
    
    echo ""
done <<< "$users"

# Summary
echo "==============================================="
echo "SYNC SUMMARY"
echo "==============================================="
echo "Existing accounts: $existing_count"
echo "New accounts: $new_count"
echo "Failed: $failed_count"
echo ""

# Cleanup
if [ -f "$NEW_URLS_FILE" ]; then
    echo "[*] Cleaning up temporary file..."
    rm "$NEW_URLS_FILE"
    echo "[✓] Cleanup complete"
fi

# Send Slack alert
msg="Sync complete - Existing: $existing_count, New: $new_count, Failed: $failed_count"
if [ $failed_count -gt 0 ]; then
    msg="$msg. Failures likely due to missing 'workflow' scope in tokens."
    color="warning"
else
    color="good"
fi

payload="{\"attachments\":[{\"color\":\"$color\",\"title\":\"Account Sync Report\",\"text\":\"$msg\"}]}"
curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$DECODED_WEBHOOK" > /dev/null 2>&1 || true
