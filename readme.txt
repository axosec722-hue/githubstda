================================================================================
                  GITHUB AUTOMATION SCRIPTS DOCUMENTATION
================================================================================

This document provides comprehensive documentation for three bash scripts that
automate GitHub account management, repository creation, and code pushing
across multiple GitHub accounts.

================================================================================
                            TABLE OF CONTENTS
================================================================================

1. Overview
2. sync_github_accounts.sh
3. push_to_all.sh
4. gitautomaterviaclaude.sh
5. Input Files Required
6. Output Files Generated
7. Security Considerations
8. Common Issues and Troubleshooting
9. Quick Start Guide

================================================================================
                           1. OVERVIEW
================================================================================

These three scripts work together as part of an automated pipeline to manage code
across multiple GitHub accounts:

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    PIPELINE OVERVIEW                               │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
  │ sync_github_      │      │ gitautomater     │      │ push_to_all.sh   │
  │ accounts.sh      │ ───► │ viaclaude.sh     │ ───► │                 │
  └──────────────────┘      └──────────────────┘      └──────────────────┘
         │                           │                           │
         ▼                           ▼                           ▼
  - Uses gh CLI            - Parses credentials      - Pushes to all
  - Creates repos          - Validates tokens       - Sends Slack
  - Adds remotes           - Creates repos          notifications
                            - Adds git remotes

 Each script serves a different purpose:

  • sync_github_accounts.sh — Uses gh CLI to switch between authenticated
    accounts, create repos, and push code. Requires gh CLI to be installed
    and authenticated with multiple accounts.

  • gitautomaterviaclaude.sh — A fully autonomous pipeline that parses raw
    credentials files, validates tokens via API, creates repos, and manages
    git remotes with smart duplicate prevention.

  • push_to_all.sh — Pushes code to all configured git remotes, handling
    account switching automatically.

================================================================================
                    2. SYNC_GITHUB_ACCOUNTS.SH
================================================================================

FILE: sync_github_accounts.sh (136 lines)
PURPOSE: Sync code to all authenticated GitHub accounts using gh CLI

--------------------------------------------------------------------------------
WHAT IT DOES:

This script uses the GitHub CLI (gh) to automatically:
1. Detect all authenticated GitHub accounts
2. For each account, check if a repository exists
3. Create the repository if it doesn't exist
4. Add a git remote for the new repository
5. Push code to the new repository
6. Track new repository URLs
7. Send a summary notification to Slack

--------------------------------------------------------------------------------
CONFIGURATION:

Variable          Value                  Description
─────────────────────────────────────────────────────────────────────────────
REPO_NAME          "subdomain_checker"    Name of repo to create
BRANCH             "master"               Branch to push
WEBHOOK            (base64 encoded)      Slack webhook URL for notifications
URLS_FILE          "github_repo_urls.txt" File to store all repo URLs
NEW_URLS_FILE       "github_repo_new_urls.txt" Temporary file for new URLs

Note: The WEBHOOK variable is double-base64 encoded for security.

--------------------------------------------------------------------------------
WORKFLOW DIAGRAM:

                    ┌──────────────────────────────────────────┐
                    │  START SYNC_GITHUB_ACCOUNTS.SH          │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  Check: Is this a git repository?        │
                    └──────────────────────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
                   Yes                          No
                    │                           │
                    ▼                           ▼
          ┌─────────────────┐        ┌─────────────────────┐
          │ Check: Any      │        │Exit with error     │
          │ uncommitted     │        │"Not a git repo"     │
          │ changes?        │        └─────────────────────┘
          └─────────────────┘
                    │
          ┌─────────┴─────────┐
          │                  │
         Yes                 No
          │                  │
          ▼                  ▼
   ┌────────────┐    ┌──────────────┐
   │Exit error  │    │Get all users │
   │"Uncommit-  │    │from gh auth  │
   │ted changes"│    │status        │
   └────────────┘    └──────────────┘
                          │
                          ▼
               ┌──────────────────────────┐
               │  FOR EACH USER ACCOUNT   │
               └──────────────────────────┘
                          │
                          ▼
               ┌──────────────────────────┐
               │  gh auth switch -u user   │
               └──────────────────────────┘
                          │
              ┌────────────┴────────────┐
              │                           │
             Success                    Failed
              │                           │
              ▼                           ▼
    ┌──────────────────┐      ┌─────────────────┐
    │Check if repo     │      │Log error and    │
    │exists:           │      │increment failed  │
    │gh repo view      │      │count, continue  │
    └──────────────────┘      └─────────────────┘
              │
    ┌──────────┴──────────┐
    │                     │
   Exists              Does Not Exist
    │                     │
    ▼                     ▼
┌─────────┐        ┌─────────────────────────────────┐
│Log that │        │gh repo create REPO_NAME --public  │
│it      │        │--description "Subdomain checker"│
│already │        │--clone=false                    │
│exists  │        └─────────────────────────────────┘
└─────────┘                  │
                             │ Success
                             ▼
                   ┌─────────────────────┐
                   │Get auth token:      │
                   │gh auth token        │
                   └─────────────────────┘
                             │
                  ┌──────────┴──────────┐
                  │                     │
                 Valid              Invalid
                  │                     │
                  ▼                     ▼
         ┌──────────────┐      ┌──────────────┐
         │Add git       │      │Log error,   │
         │remote:      │      │increment    │
         │git remote   │      │failed count │
         │add user     │      │continue     │
         └──────────────┘      └──────────────┘
                  │
                  ▼
         ┌──────────────────────┐
         │Push to remote:         │
         │git push "https://     │
         │$token@github.com/   │
         │$user/repo.git"      │
         │BRANCH               │
         └──────────────────────┘
                  │
                 Success
                  │
                  ▼
         ┌───────────────────────┐
         │Save URL to files:     │
         │github_repo_urls.txt   │
         │github_repo_new_urls  │
         └───────────────────────┘
                  │
                  ▼
         ┌───────────────────────┐
         │Increment new_count    │
         └───────────────────────┘

                          │
                          ▼
               ┌──────────────────────────┐
               │  END FOR EACH USER   │
               └──────────────────────────┘
                          │
                          ▼
                    ┌──────────────────────────────────┐
                    │  SEND SLACK NOTIFICATION          │
                    │  Summary:                         │
                    │  - Existing accounts             │
                    │  - New repos created             │
                    │  - Failed operations            │
                    └──────────────────────────────────┘

--------------------------------------------------------------------------------
REQUIREMENTS:

1. GitHub CLI (gh) must be installed
2. At least one GitHub account authenticated via gh auth
3. The repository must NOT exist on any account (to create new)
4. Tokens must have 'repo' scope for creating repos
5. Tokens must have 'workflow' scope for pushing code

--------------------------------------------------------------------------------
EXIT CODES:

Exit Code    Meaning
─────────────────────────────────────────────────────────────────────────────
0           Script completed successfully
1           Error (not a git repo, no users found, uncommitted changes)

================================================================================
                      3. PUSH_TO_ALL.SH
================================================================================

FILE: push_to_all.sh (102 lines)
PURPOSE: Push code to all configured GitHub remotes

--------------------------------------------------------------------------------
WHAT IT DOES:

This script iterates through all git remotes and pushes code to each one:
1. Get list of all configured git remotes
2. For each remote, switch to that account via gh auth
3. Get a fresh authentication token for that account
4. Push code using HTTPS with embedded token
5. Track success/failure counts
6. Send summary notification to Slack

--------------------------------------------------------------------------------
CONFIGURATION:

Variable          Value                  Description
─────────────────────────────────────────────────────────────────────────────
BRANCH             "master"               Branch to push
WEBHOOK            (base64 encoded)      Slack webhook URL

--------------------------------------------------------------------------------
WORKFLOW DIAGRAM:

                    ┌──────────────────────────────────────────┐
                    │         START PUSH_TO_ALL.SH             │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  Check: Any uncommitted changes?          │
                    └──────────────────────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
                   Yes                          No
                    │                           │
                    ▼                           ▼
          ┌───��─��───────────┐        ┌─────────────────────────┐
          │Prompt user to    │        │Get all git remotes      │
          │commit changes   │        │(git remote)            │
          │and exit         │        └─────────────────────────┘
          └─────────────────┘                          │
                                      ┌─────────────┴─────────────┐
                                      │                           │
                                     Empty                       Has remotes
                                      │                           │
                                      ▼                           ▼
                            ┌────────────────┐          ┌──────────────────────┐
                            │Exit with error │          │  FOR EACH REMOTE   │
                            │"No remotes"   │          └──────────────────────┘
                            └────────────────┘                          │
                                                                      ▼
                                                            ┌──────────────────────┐
                                                            │gh auth switch -u    │
                                                            │remote (username)    │
                                                            └──────────────────────┘
                                                                      │
                                                         ┌──────────────┴──────────────┐
                                                         │                         │
                                                        Success                  Failed
                                                         │                         │
                                                         ▼                         ▼
                                               ┌──────────────────┐    ┌──────────────────┐
                                               │Get token:       │    │Log error, add to │
                                               │gh auth token   │    │failed list      │
                                               └──────────────────┘    └──────────────────┘
                                                         │
                                                ┌─────────┴─────────┐
                                                │                  │
                                               Valid             Invalid
                                                │                  │
                                                ▼                  ▼
                                      ┌─────────────────┐    ┌────────────────┐
                                      │Git push with    │    │Log error, add  │
                                      │HTTPS token:    │    │to failed list │
                                      │git push "https │    └────────────────┘
                                      │://$token@      │
                                      │github.com/..."│
                                      └─────────────────┘
                                                │
                                      ┌──────────┴──────────┐
                                      │                     │
                                     Success               Failed
                                      │                     │
                                      ▼                     ▼
                               ┌────────────┐      ┌────────────────┐
                               │Log success │      │Log error, add  │
                               │increment   │      │to failed list  │
                               │success++   │      └────────────────┘
                               └────────────┘

                                                      │
                                                      ▼
                                           ┌──────────────────────────┐
                                           │    END FOR EACH REMOTE  │
                                           └──────────────────────────┘
                                                      │
                                                      ▼
                                           ┌──────────────────────────┐
                                           │  PRINT SUMMARY REPORT    │
                                           │  - Success count       │
                                           │  - Failed count       │
                                           │  - Failed remote list│
                                           └──────────────────────────┘
                                                      │
                                                      ▼
                                           ┌──────────────────────────┐
                                           │  SEND SLACK NOTIFICATION │
                                           └──────────────────────────┘
                                                      │
                                         ┌────────────┴────────────┐
                                         │                         │
                                        All failed              Some/all success
                                         │                         │
                                         ▼                         ▼
                               ┌────────────────────┐   ┌────────────────────┐
                               │Exit with code 1     │   │Exit with code 0      │
                               │(indicates failure)  │   │(success)           │
                               └────────────────────┘   └────────────────────┘

--------------------------------------------------------------------------------
REQUIREMENTS:

1. GitHub CLI (gh) must be installed
2. Git remotes must be configured with usernames as remote names
3. Each account must be authenticated via gh auth
4. Tokens must have 'workflow' scope for pushing

--------------------------------------------------------------------------------
EXIT CODES:

Exit Code    Meaning
─────────────────────────────────────────────────────────────────────────────
0           All remotes pushed successfully
1           One or more pushes failed

================================================================================
                  4. GITAUTOMATERVIACLAUDE.SH
================================================================================

FILE: gitautomaterviaclaude.sh (386 lines)
PURPOSE: Full autonomous pipeline for GitHub account management

This is the most comprehensive script. It performs the complete workflow
from raw credentials to working git remotes, with extensive validation
and duplicate prevention.

--------------------------------------------------------------------------------
WHAT IT DOES (10 STEPS):

STEP 1: Find github_credentials.txt
STEP 2: Read and parse credentials
STEP 3: Validate + Deduplicate + Pair
STEP 4: Save github_credentials_pairs.txt
STEP 5: Create public repo for each account
STEP 6: Append new remotes to github_remote_locations.txt
STEP 7: Validate and clean github_remote_locations.txt
STEP 8: Extract existing git remote names
STEP 9: Build available origin names array
STEP 10: Add remotes to git

--------------------------------------------------------------------------------
STEP-BY-STEP BREAKDOWN:

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 1: FIND GITHUB_CREDENTIALS.TXT                                       │
└─────────────────────────────────────────────────────────────────────────────┘

The script looks for github_credentials.txt in two locations:
  1. Current directory (./github_credentials.txt)
  2. Home directory ($HOME/github_credentials.txt)

If not found, the script exits with an error.

Supported credential formats:
  username:ghp_xxxxxxxxxxxxx
  username=ghp_xxxxxxxxxxxxx
  username github_pat_xxxxxxxxxxxxx
  ghp_xxxxxxxxxxxxx (username on previous line)
  github_pat_xxxxxxxxxxxxx (username on previous line)

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 2: READ AND PARSE CREDENTIALS                                         │
└─────────────────────────────────────────────────────────────────────────────┘

The script parses the credentials file and builds an associative array
of username → token pairs. It handles multiple formats:

Format 1: username:token
  john:ghp_xxxxxxxxxxxxx

Format 2: username=token
  john=ghp_xxxxxxxxxxxxx

Format 3: username token (space-separated)
  john ghp_xxxxxxxxxxxxx

Format 4: token with username on previous line
  john
  ghp_xxxxxxxxxxxxx

The parser uses regex patterns to identify tokens:
  - ghp_* (GitHub Personal Access Token)
  - github_pat_* (GitHub Fine-Grained PAT)

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 3: VALIDATE + DEDUPLICATE + PAIR                                      │
└─────────────────────────────────────────────────────────────────────────────┘

For each username-token pair:
  1. Validate token via GitHub API (https://api.github.com/user)
  2. If HTTP 200 → token is valid
  3. For "standalone" tokens (no username), look up the username
  4. Keep only one token per username (prefer ghp_ over github_pat_)

API call used for validation:
  curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token TOKEN" \
    https://api.github.com/user

API call used for username lookup:
  curl -s -H "Authorization: token TOKEN" \
    https://api.github.com/user \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('login',''))"

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 4: SAVE GITHUB_CREDENTIALS_PAIRS.TXT                                  │
└─────────────────────────────────────────────────────────────────────────────┘

Validated username:token pairs are saved to:
  $BASE_DIR/github_credentials_pairs.txt

Format: username:token
  john:ghp_xxxxxxxxxxxxx
  jane:github_pat_xxxxxxxxxxxxx

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 5: CREATE PUBLIC REPO FOR EACH ACCOUNT                                 │
└─────────────────────────────────────────────────────────────────────────────┘

For each valid account, create a public repository via GitHub API:

API call:
  curl -s -o /dev/null -w "%{http_code}" \
    -X POST https://api.github.com/user/repos \
    -H "Authorization: token TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name":"REPO_NAME","private":false}'

Possible responses:
  - 201 Created → Repo successfully created
  - 422 Unprocessable Entity → Repo already exists (skip)
  - Other → Failed (skip)

New repos are saved to:
  $BASE_DIR/github_new_repos.txt

Format: username:token:repo_url
  john:ghp_xxxx:https://github.com/john/githubstda

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 6: APPEND NEW REMOTES TO GITHUB_REMOTE_LOCATIONS.TXT                     │
└─────────────────────────────────────────────────────────────────────────────┘

CRITICAL: This step Uses APPEND-ONLY mode (>>), never overwrites!

Rules:
  1. Load existing usernames from the file first
  2. If username already in file → skip (no duplicate)
  3. If username not in file → append new entry

Output format:
  https://TOKEN@github.com/username/repo.git

Example:
  https://ghp_xxxx@github.com/john/githubstda.git
  https://ghp_yyyy@github.com/jane/githubstda.git

This file serves as the "source of truth" for all remote URLs.

┌──────────────────────────────────────────────────��─��────────────────────────┐
│ STEP 7: VALIDATE AND CLEAN GITHUB_REMOTE_LOCATIONS.TXT                     │
└─────────────────────────────────────────────────────────────────────────────┘

For each URL in the file:
  1. Extract token and username
  2. Check for duplicate usernames (keep first occurrence)
  3. Validate token via API
  4. Remove invalid/expired tokens
  5. Write clean list back to file

This ensures:
  - No duplicate usernames
  - All tokens are valid
  - File only contains working URLs

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 8: EXTRACT EXISTING GIT REMOTE NAMES                                    │
└─────────────────────────────────────────────────────────────────────────────┘

The script gets all existing git remote names:
  git remote -v | awk '{print $1}' | sort -u

Saved to: $BASE_DIR/github_created_origin.txt

Example output:
  origin
  origin2
  origin3

This tracks which origin names are already in use.

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 9: BUILD AVAILABLE ORIGIN NAMES ARRAY                                 │
└─────────────────────────────────────────────────────────────────────────────┘

The script creates a pool of available origin names:

1. Count URLs in remote_locations file
2. Generate names: origin, origin2, origin3, ... originN
3. Load existing git remote names
4. Remove already-used names from available pool

Example:
  If remote_locations has 3 URLs and "origin" is already used:
  Available: origin2, origin3, origin4

This prevents conflicts when adding new remotes.

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 10: ADD REMOTES TO GIT                                               │
└─────────────────────────────────────────────────────────────────────────────┘

DUPLICATE PREVENTION LOGIC:
  For each URL in remote_locations file:
    1. Extract username from URL
    2. Check if username already has a git remote
    3. If YES → skip entirely (user already owns an origin)
    4. If NO → assign next available origin name
    5. Run: git remote add ORIGIN_NAME URL

This ensures:
  - ONE remote per username, always
  - No user can own multiple origins
  - Automatic conflict resolution

--------------------------------------------------------------------------------
WORKFLOW DIAGRAM (COMPLETE):

                    ┌──────────────────────────────────────────┐
                    │  START GITHUBAUTOMATERViaclaude.sh       │
                    └────────────────────────────────────────��─��
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  STEP 1: Find github_credentials.txt     │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  STEP 2: Parse credentials into pairs   │
                    │  - Handle multiple formats             │
                    │  - Build RAW_PAIRS associative array   │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  STEP 3: Validate + Deduplicate          │
                    │  - Call GitHub API for each token       │
                    │  - Remove invalid/expired tokens        │
                    │  - For standalone tokens, look up user│
                    │  - Keep one token per username         │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  STEP 4: Save to github_credentials_     │
                    │         pairs.txt                       │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  STEP 5: Create public repos             │
                    │  - POST to /user/repos API               │
                    │  - Handle 422 (repo exists)             │
                    │  - Save new repos to github_new_repos.txt│
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  STEP 6: Append to github_remote_        │
                    │         locations.txt (APPEND ONLY!)    │
                    │  - Load existing usernames first        │
                    │  - Skip if username already tracked     │
                    │  - Append new URLs                      │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  STEP 7: Validate and clean              │
                    │  - Remove duplicate usernames            │
                    │  - Remove invalid tokens                │
                    │  - Write clean list                     │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  STEP 8: Get existing git remotes        │
                    │  - git remote -v output                │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  STEP 9: Build available origin names   │
                    │  - Generate origin, origin2, ...      │
                    │  - Remove already-used names           │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  STEP 10: Add git remotes (with          │
                    │           duplicate prevention)        │
                    │  - Skip if username already has remote │
                    │  - Assign next available origin name │
                    │  - git remote add ORIGIN URL         │
                    └──────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────────────────┐
                    │  FINAL VERIFICATION                     │
                    │  - Display all git remotes             │
                    │  - List all created files              │
                    └──────────────────────────────────────────┘

--------------------------------------------------------------------------------
REQUIREMENTS:

1. github_credentials.txt file must exist
2. Each token must have 'repo' scope (for creating repos)
3. Valid JSON parsing (python3 available)

--------------------------------------------------------------------------------
EXIT CODES:

Exit Code    Meaning
─────────────────────────────────────────────────────────────────────────────
0           Script completed successfully
1           Credentials file not found or other error

================================================================================
                    5. INPUT FILES REQUIRED
================================================================================

FILE: github_credentials.txt
PURPOSE: Raw GitHub credentials (tokens)

Location: Current directory (./) or Home directory (~/)

Format (any of the following):
  username:ghp_xxxxxxxxxxxxx
  username=ghp_xxxxxxxxxxxxx
  username github_pat_xxxxxxxxxxxxx
  username
  ghp_xxxxxxxxxxxxx

Example content:
  john:ghp_abc123def456ghi789jkl012mno345pqr
  jane
  ghp_xyz789stu012vwx345yza678bcd901efg
  bob=github_pat_xxxxxxxxxxxxx
  alice github_pat_yyyyyyyyyyyyyyyyyyyyy

--------------------------------------------------------------------------------

FILE: github_remote_locations.txt
PURPOSE: Source of truth for all remote URLs

Location: Same as github_credentials.txt (./ or ~/)

Format:
  https://TOKEN@github.com/username/repo.git

Example:
  https://ghp_abc123@github.com/john/githubstda.git
  https://ghp_xyz789@github.com/jane/githubstda.git

Note: This file is created/updated by gitautomaterviaclaude.sh

================================================================================
                    6. OUTPUT FILES GENERATED
================================================================================

┌─────────────────────────────────────────────────────────────────────────────┐
│ FILE: github_credentials_pairs.txt                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ Location: ./ or ~/                                                          │
│ Purpose: Validated username:token pairs                                    │
│ Format: username:token                                                     │
│ Created by: gitautomaterviaclaude.sh (Step 4)                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ FILE: github_new_repos.txt                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│ Location: ./ or ~/                                                          │
│ Purpose: Newly created repositories                                        │
│ Format: username:token:repo_url                                            │
│ Created by: gitautomaterviaclaude.sh (Step 5)                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ FILE: github_remote_locations.txt                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│ Location: ./ or ~/                                                          │
│ Purpose: Source of truth for all remote URLs                               │
│ Format: https://token@github.com/user/repo.git                             │
│ Created by: gitautomaterviaclaude.sh (Step 6)                              │
│ Mode: Append-only, never overwrites                                         │
└──────────────────────��─��────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ FILE: github_created_origin.txt                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ Location: ./ or ~/                                                          │
│ Purpose: Tracks which origin names are in use                             │
│ Format: One remote name per line (origin, origin2, etc.)                   │
│ Created by: gitautomaterviaclaude.sh (Steps 8 & 10)                          │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ FILE: github_repo_urls.txt                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ Location: Current directory                                               │
│ Purpose: All repository URLs (for sync_github_accounts.sh)                 │
│ Format: https://github.com/username/repo                                    │
│ Created by: sync_github_accounts.sh                                         │
└─────────────────────────────────────────────────────────────────────────────┘

================================================================================
                    7. SECURITY CONSIDERATIONS
================================================================================

1. TOKEN STORAGE
   - Tokens are stored in plain text files
   - These files should be in .gitignore to prevent accidental commits
   - Consider using file permissions: chmod 600 github_credentials.txt

2. WEBHOOK SECURITY
   - Webhook URLs are double-base64 encoded in scripts
   - This provides mild obfuscation but NOT encryption
   - Anyone with access to the script can decode the webhook

3. TOKEN SCOPES
   - Tokens need 'repo' scope to create repositories
   - Tokens need 'workflow' scope to push code
   - Always use the minimum required scope

4. CREDENTIALS FILE
   - Contains sensitive tokens in plain text
   - Should be protected: owner read/write only (chmod 600)
   - Never commit to version control

RECOMMENDED .GITIGNORE ENTRIES:
  github_credentials.txt
  github_credentials_pairs.txt
  github_new_repos.txt
  github_remote_locations.txt
  github_created_origin.txt
  github_repo_urls.txt
  github_repo_new_urls.txt

================================================================================
                    8. COMMON ISSUES AND TROUBLESHOOTING
================================================================================

ISSUE: "Failed to switch account"
─────────────────────────────────────────────────────────────────────
Cause: The username doesn't match an authenticated gh account
Fix: Ensure the account is authenticated: gh auth login

ISSUE: "Push failed (check if token has 'workflow' scope)"
─────────────────────────────────────────────────────────────────────
Cause: Token missing required scope
Fix: Create new token with 'repo' and 'workflow' scopes

ISSUE: "Repo already exists"
─────────────────────────────────────────────────────────────────────
Expected behavior: Script will detect and skip creation
This is normal for existing accounts

ISSUE: "No more available origin name slots"
─────────────────────────────────────────────────────────────────────
Cause: Too many remotes configured
Fix: Clean up unused remotes or increase ARRAY_SIZE in script

ISSUE: "github_credentials.txt not found"
─────────────────────────────────────────────────────────────────────
Cause: File not in current directory or home directory
Fix: Place file in ./github_credentials.txt or ~/github_credentials.txt

ISSUE: Token validation fails with HTTP 401
─────────────────────────────────────────────────────────────────────
Cause: Token has been revoked or expired
Fix: Generate new token and update credentials file

ISSUE: API rate limiting
─────────────────────────────────────────────────────────────────────
Cause: Too many API calls in short period
Fix: Add sleep delays between API calls (not implemented in current scripts)

================================================================================
                    9. QUICK START GUIDE
================================================================================

PREREQUISITES:
  1. GitHub Personal Access Tokens (one per account)
  2. GitHub CLI installed (for sync_github_accounts.sh and push_to_all.sh)
  3. Python3 available (for gitautomaterviaclaude.sh)

QUICK START - OPTION 1: USING gh CLI
─────────────────────────────────────────────────────────────────────

Step 1: Authenticate with all accounts
  gh auth login

Step 2: Run sync script
  ./sync_github_accounts.sh

Step 3: Push to all (if needed later)
  ./push_to_all.sh

QUICK START - OPTION 2: USING CREDENTIALS FILE
─────────────────────────────────────────────────────────────────────

Step 1: Create github_credentials.txt
  echo "username:ghp_your_token_here" > github_credentials.txt

Step 2: Run automation script
  ./gitautomaterviaclaude.sh

Step 3: Push to all (if needed later)
  ./push_to_all.sh

VERIFYING SETUP:
─────────────────────────────────────────────────────────────────────

Check configured remotes:
  git remote -v

Check remote locations:
  cat github_remote_locations.txt

Test push to one remote:
  git push origin master

================================================================================
                          END OF DOCUMENTATION
================================================================================

For questions or issues, review the specific script sections above or
check the Common Issues section for troubleshooting tips.