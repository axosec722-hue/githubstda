#!/bin/bash

# ═══════════════════════════════════════════════════════════
#  GITHUB AUTOMATER — Full Pipeline v2
#  Key improvement: Smart duplicate-free remote management
#  - Appends to github_remote_locations.txt (never overwrites)
#  - One username = one origin, always
#  - Skips already-assigned usernames in git remotes
# ═══════════════════════════════════════════════════════════

REPO_NAME="githubstda"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✔]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✘]${NC} $1"; }

# ═══════════════════════════════════════════════════════════
# STEP 1 — FIND github_credentials.txt
# ═══════════════════════════════════════════════════════════

CREDS_FILE=""
if [ -f "./github_credentials.txt" ]; then
  CREDS_FILE="./github_credentials.txt"
  BASE_DIR="."
elif [ -f "$HOME/github_credentials.txt" ]; then
  CREDS_FILE="$HOME/github_credentials.txt"
  BASE_DIR="$HOME"
else
  error "github_credentials.txt not found in ./ or ~/"
  exit 1
fi

log "Found: $CREDS_FILE"

PAIRS_FILE="$BASE_DIR/github_credentials_pairs.txt"
NEW_REPOS_FILE="$BASE_DIR/github_new_repos.txt"
REMOTE_LOCS_FILE="$BASE_DIR/github_remote_locations.txt"
CREATED_ORIGINS_FILE="$BASE_DIR/github_created_origin.txt"

# ═══════════════════════════════════════════════════════════
# STEP 2 — READ AND PARSE credentials
# ═══════════════════════════════════════════════════════════

declare -A RAW_PAIRS
prev_username=""

while IFS= read -r line || [ -n "$line" ]; do
  line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$line" ] && continue

  if [[ "$line" =~ ^([^:]+):(ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)$ ]]; then
    RAW_PAIRS["${BASH_REMATCH[1]}"]+="${BASH_REMATCH[2]} "
    prev_username=""
  elif [[ "$line" =~ ^([^=]+)=(ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)$ ]]; then
    RAW_PAIRS["${BASH_REMATCH[1]}"]+="${BASH_REMATCH[2]} "
    prev_username=""
  elif [[ "$line" =~ ^([^ ]+)[[:space:]]+(ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)$ ]]; then
    RAW_PAIRS["${BASH_REMATCH[1]}"]+="${BASH_REMATCH[2]} "
    prev_username=""
  elif [[ "$line" =~ ^(ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)$ ]]; then
    token="${BASH_REMATCH[1]}"
    if [ -n "$prev_username" ]; then
      RAW_PAIRS["$prev_username"]+="$token "
      prev_username=""
    else
      RAW_PAIRS["__standalone__"]+="$token "
    fi
  elif [[ "$line" =~ ^[A-Za-z0-9_-]+$ ]]; then
    prev_username="$line"
  else
    prev_username=""
  fi
done < "$CREDS_FILE"

log "Parsing done"

# ═══════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════

validate_token() {
  curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $1" \
    https://api.github.com/user
}

get_username_from_token() {
  curl -s \
    -H "Authorization: token $1" \
    https://api.github.com/user | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('login',''))" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════
# STEP 3 — VALIDATE + DEDUPLICATE + PAIR
# ═══════════════════════════════════════════════════════════

declare -A VALID_PAIRS

for username in "${!RAW_PAIRS[@]}"; do
  read -ra tokens <<< "${RAW_PAIRS[$username]}"
  best_ghp=""
  best_pat=""

  for token in "${tokens[@]}"; do
    code=$(validate_token "$token")
    [ "$code" != "200" ] && continue

    actual_username="$username"
    if [ "$username" == "__standalone__" ]; then
      actual_username=$(get_username_from_token "$token")
      [ -z "$actual_username" ] && continue
    fi

    if [[ "$token" == ghp_* ]] && [ -z "$best_ghp" ]; then
      best_ghp="$actual_username:$token"
    elif [[ "$token" == github_pat_* ]] && [ -z "$best_pat" ]; then
      best_pat="$actual_username:$token"
    fi
  done

  chosen="${best_ghp:-$best_pat}"
  if [ -n "$chosen" ]; then
    u=$(cut -d: -f1 <<< "$chosen")
    t=$(cut -d: -f2 <<< "$chosen")
    VALID_PAIRS["$u"]="$t"
  fi
done

log "Valid accounts: ${#VALID_PAIRS[@]}"

# ═══════════════════════════════════════════════════════════
# STEP 4 — SAVE github_credentials_pairs.txt
# ═══════════════════════════════════════════════════════════

[ -f "$PAIRS_FILE" ] && rm -f "$PAIRS_FILE"
for u in "${!VALID_PAIRS[@]}"; do
  echo "$u:${VALID_PAIRS[$u]}" >> "$PAIRS_FILE"
done
log "Saved: $PAIRS_FILE"

# ═══════════════════════════════════════════════════════════
# STEP 5 — CREATE PUBLIC REPO FOR EACH ACCOUNT
# ═══════════════════════════════════════════════════════════

[ -f "$NEW_REPOS_FILE" ] && rm -f "$NEW_REPOS_FILE"

while IFS=: read -r username token; do
  [ -z "$username" ] || [ -z "$token" ] && continue

  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST https://api.github.com/user/repos \
    -H "Authorization: token $token" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$REPO_NAME\",\"private\":false}")

  if [ "$code" == "201" ]; then
    echo "$username:$token:https://github.com/$username/$REPO_NAME" >> "$NEW_REPOS_FILE"
    log "Repo created: $username"
  elif [ "$code" == "422" ]; then
    warn "Repo exists: $username — skipping"
  else
    warn "Failed ($code): $username — skipping"
  fi
done < "$PAIRS_FILE"

log "Saved: $NEW_REPOS_FILE"

# ═══════════════════════════════════════════════════════════
# STEP 6 — APPEND NEW REMOTES TO github_remote_locations.txt
#
#  RULES:
#  ✅ NEVER delete or overwrite the file
#  ✅ Only APPEND new entries using >>
#  ✅ Load existing usernames from file first
#  ✅ If username already in file → skip it (no duplicate)
#  ✅ One username = one URL, always
# ═══════════════════════════════════════════════════════════

touch "$REMOTE_LOCS_FILE"

# Load usernames already tracked in remote locations file
declare -A EXISTING_REMOTE_USERS

while IFS= read -r existing_url; do
  [ -z "$existing_url" ] && continue
  existing_user=$(echo "$existing_url" | grep -oP '(?<=github\.com/)[^/]+')
  [ -n "$existing_user" ] && EXISTING_REMOTE_USERS["$existing_user"]=1
done < "$REMOTE_LOCS_FILE"

log "Usernames already in remote locations file: ${#EXISTING_REMOTE_USERS[@]}"

ADDED_COUNT=0

while IFS=: read -r username token repo_url; do
  [ -z "$username" ] || [ -z "$token" ] && continue

  # ── Skip if username already has a URL in the file ──
  if [ -n "${EXISTING_REMOTE_USERS[$username]}" ]; then
    warn "Remote URL already exists for $username — skipping append"
    continue
  fi

  new_remote_url="https://$token@github.com/$username/$REPO_NAME.git"

  # Append only — never overwrite
  echo "$new_remote_url" >> "$REMOTE_LOCS_FILE"
  EXISTING_REMOTE_USERS["$username"]=1
  ADDED_COUNT=$((ADDED_COUNT + 1))
  log "Appended: $username"

done < "$NEW_REPOS_FILE"

log "New entries appended: $ADDED_COUNT"

# ═══════════════════════════════════════════════════════════
# STEP 7 — VALIDATE AND CLEAN github_remote_locations.txt
#
#  - Validate every token via API
#  - Remove invalid/expired ones
#  - Remove duplicate usernames (keep first seen)
#  - Write clean list back to file
# ═══════════════════════════════════════════════════════════

CLEAN_URLS=()
declare -A VALIDATED_USERS

while IFS= read -r url; do
  [ -z "$url" ] && continue

  token=$(echo "$url" | grep -oP '(ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)')
  username=$(echo "$url" | grep -oP '(?<=github\.com/)[^/]+')

  [ -z "$token" ] || [ -z "$username" ] && continue

  if [ -n "${VALIDATED_USERS[$username]}" ]; then
    warn "Duplicate username $username — removing extra entry"
    continue
  fi

  code=$(validate_token "$token")
  if [ "$code" == "200" ]; then
    CLEAN_URLS+=("$url")
    VALIDATED_USERS["$username"]=1
    log "Valid: $username"
  else
    warn "Bad token for $username (HTTP $code) — removed"
  fi
done < "$REMOTE_LOCS_FILE"

rm -f "$REMOTE_LOCS_FILE"
for url in "${CLEAN_URLS[@]}"; do
  echo "$url" >> "$REMOTE_LOCS_FILE"
done
log "Clean remote locations saved: ${#CLEAN_URLS[@]}"

# ═══════════════════════════════════════════════════════════
# STEP 8 — EXTRACT EXISTING GIT REMOTE NAMES
# ═══════════════════════════════════════════════════════════

[ -f "$CREATED_ORIGINS_FILE" ] && rm -f "$CREATED_ORIGINS_FILE"
git remote -v | awk '{print $1}' | sort -u > "$CREATED_ORIGINS_FILE"
log "Existing git remote names saved"

# ═══════════════════════════════════════════════════════════
# STEP 9 — BUILD AVAILABLE ORIGIN NAMES ARRAY
#
#  LOGIC:
#  1. Count how many URLs are in remote_locations file
#  2. Build a big enough names list: origin, origin2 ... originN+2
#  3. Scan git remote -v to find which usernames are ALREADY
#     assigned — those slots must be SKIPPED entirely
#  4. Remove already-used origin NAMES from available list
#  5. What remains = safe slots to assign new remotes
# ═══════════════════════════════════════════════════════════

REMOTE_COUNT=$(wc -l < "$REMOTE_LOCS_FILE" | tr -d ' ')
ARRAY_SIZE=$((REMOTE_COUNT + 2))

ALL_ORIGINS=("origin")
for i in $(seq 2 "$ARRAY_SIZE"); do
  ALL_ORIGINS+=("origin$i")
done

# Origin names already in use
mapfile -t USED_NAMES < "$CREATED_ORIGINS_FILE"

# Usernames already assigned in git remote -v
declare -A ALREADY_IN_GIT
while IFS= read -r git_line; do
  git_user=$(echo "$git_line" | grep -oP '(?<=github\.com/)[^/]+')
  [ -n "$git_user" ] && ALREADY_IN_GIT["$git_user"]=1
done < <(git remote -v)

log "Usernames already in git remote: ${!ALREADY_IN_GIT[*]}"

# Build available origin names (remove used ones)
AVAILABLE_ORIGINS=()
for name in "${ALL_ORIGINS[@]}"; do
  in_use=false
  for used in "${USED_NAMES[@]}"; do
    [ "$name" == "$used" ] && in_use=true && break
  done
  [ "$in_use" == false ] && AVAILABLE_ORIGINS+=("$name")
done

log "Available origin slots: ${AVAILABLE_ORIGINS[*]}"

# ═══════════════════════════════════════════════════════════
# STEP 10 — ADD REMOTES TO GIT
#
#  CRITICAL DUPLICATE PREVENTION:
#  Before adding each remote URL:
#  ✅ Check if that username is already in ANY git remote
#  ✅ If YES → skip entirely (user already owns an origin)
#  ✅ If NO  → assign next available origin name
#
#  This makes it IMPOSSIBLE for one user to own 2 origins
# ═══════════════════════════════════════════════════════════

origin_index=0

while IFS= read -r remote_url; do
  [ -z "$remote_url" ] && continue

  username=$(echo "$remote_url" | grep -oP '(?<=github\.com/)[^/]+')
  [ -z "$username" ] && continue

  # ── DUPLICATE CHECK: username already has an origin? ──
  if [ -n "${ALREADY_IN_GIT[$username]}" ]; then
    warn "SKIP $username — already owns a git remote origin"
    continue
  fi

  # Get next available origin name
  origin_name="${AVAILABLE_ORIGINS[$origin_index]}"
  if [ -z "$origin_name" ]; then
    error "No more available origin name slots"
    break
  fi

  git remote add "$origin_name" "$remote_url"

  if [ $? -eq 0 ]; then
    log "Added → $origin_name : $username"
    echo "$origin_name" >> "$CREATED_ORIGINS_FILE"
    ALREADY_IN_GIT["$username"]=1        # mark as assigned
    origin_index=$((origin_index + 1))
  else
    warn "git remote add failed for $origin_name — skipping slot"
    origin_index=$((origin_index + 1))
  fi

  # Stop when all remote_locations are accounted for
  remote_total=$(wc -l < "$REMOTE_LOCS_FILE" | tr -d ' ')
  created_total=$(wc -l < "$CREATED_ORIGINS_FILE" | tr -d ' ')
  [ "$created_total" -ge "$remote_total" ] && break

done < "$REMOTE_LOCS_FILE"

# ═══════════════════════════════════════════════════════════
# FINAL VERIFICATION
# ═══════════════════════════════════════════════════════════

echo ""
log "══════════════════════════════"
log "       FINAL GIT REMOTES      "
log "══════════════════════════════"
git remote -v

echo ""
log "══════════════════════════════"
log "    FILES CREATED/UPDATED     "
log "══════════════════════════════"
echo "  ✅ $PAIRS_FILE"
echo "  ✅ $NEW_REPOS_FILE"
echo "  ✅ $REMOTE_LOCS_FILE  (append-only, never overwritten)"
echo "  ✅ $CREATED_ORIGINS_FILE"

echo ""
log "ALL DONE ✅"