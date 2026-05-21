#!/usr/bin/env bash
# Migrates a GitHub repo to Forgejo as primary, with GitHub as automatic push mirror.
# Idempotent — safe to re-run if a previous attempt partially completed.
#
# Usage:
#   GITHUB_PAT=<token> ./scripts/migrate-to-forgejo.sh <repo-name>
#
# Prerequisites:
#   - ~/.homelab-secrets/forgejo.env with FORGEJO_TOKEN and FORGEJO_URL
#   - GITHUB_PAT env var set to a GitHub fine-grained PAT (Contents: Read+Write)
#   - Local clone of <repo-name> at ~/code_base/<repo-name>
#   - SSH access to Forgejo at 100.86.4.29:222 via Tailscale
#
# Forgejo token scopes required:
#   - write:user       — create repos (only needed if repo doesn't exist yet)
#   - write:repository — push mirrors, branch protection
#
# What it does:
#   1. Creates the repo on Forgejo via API (skips if already exists)
#   2. Pushes all local branches + tags to Forgejo
#   3. Configures Forgejo push mirror -> GitHub (skips if already configured)
#   4. Rewires local origin: fetch=GitHub HTTPS, push=Forgejo SSH
#   5. Adds/updates a 'forgejo' remote pointing to Forgejo

set -euo pipefail

REPO_NAME="${1:?Usage: GITHUB_PAT=<token> $0 <repo-name>}"
FORGEJO_SSH="ssh://git@100.86.4.29:222"
FORGEJO_USER="dax"
GITHUB_USER="KolinSmith"
REPO_PATH="${HOME}/code_base/${REPO_NAME}"

# Load Forgejo credentials
# shellcheck source=/dev/null
source ~/.homelab-secrets/forgejo.env
: "${FORGEJO_TOKEN:?FORGEJO_TOKEN not set in ~/.homelab-secrets/forgejo.env}"
: "${FORGEJO_URL:?FORGEJO_URL not set in ~/.homelab-secrets/forgejo.env}"
: "${GITHUB_PAT:?GITHUB_PAT env var required — get from vault: anval -> vault_github_personal_access_token}"

if [ ! -d "${REPO_PATH}/.git" ]; then
  echo "ERROR: ${REPO_PATH} is not a git repository"
  exit 1
fi

echo "==> Migrating ${REPO_NAME} to Forgejo..."

# 1. Create repo on Forgejo (convert pull mirror if needed, skip if already primary)
echo "--> Checking Forgejo repo state..."
REPO_INFO=$(curl -s "${FORGEJO_URL}/api/v1/repos/${FORGEJO_USER}/${REPO_NAME}" \
  -H "Authorization: token ${FORGEJO_TOKEN}")
REPO_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  "${FORGEJO_URL}/api/v1/repos/${FORGEJO_USER}/${REPO_NAME}" \
  -H "Authorization: token ${FORGEJO_TOKEN}")
IS_MIRROR=$(echo "${REPO_INFO}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('mirror', False))" 2>/dev/null || echo "False")

if [[ "$REPO_HTTP" == "200" && "$IS_MIRROR" == "True" ]]; then
  echo "    Repo exists as a pull mirror — verifying token can create repos before deleting..."
  # Probe write:user scope with a dry-run POST to a name that won't collide
  PROBE=$(curl -s -o /tmp/forgejo_probe.json -w "%{http_code}" \
    -X POST "${FORGEJO_URL}/api/v1/user/repos" \
    -H "Authorization: token ${FORGEJO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"__probe_delete_me_${REPO_NAME}\", \"private\": true, \"auto_init\": false}")
  if [[ "$PROBE" == "403" ]]; then
    echo "ERROR: Token missing 'write:user' scope — cannot create repos."
    echo "  Regenerate at ${FORGEJO_URL}/user/settings/applications with write:user + write:repository scopes."
    echo "  Then update FORGEJO_TOKEN in ~/.homelab-secrets/forgejo.env and re-run."
    exit 1
  elif [[ "$PROBE" == "201" ]]; then
    # Clean up the probe repo immediately
    curl -s -o /dev/null -X DELETE \
      "${FORGEJO_URL}/api/v1/repos/${FORGEJO_USER}/__probe_delete_me_${REPO_NAME}" \
      -H "Authorization: token ${FORGEJO_TOKEN}"
    echo "    Token scope verified."
  fi
  # Safe to proceed: delete the pull mirror and recreate as primary
  echo "    Deleting pull mirror to recreate as primary..."
  DEL_RESPONSE=$(curl -s -o /tmp/forgejo_del.json -w "%{http_code}" \
    -X DELETE "${FORGEJO_URL}/api/v1/repos/${FORGEJO_USER}/${REPO_NAME}" \
    -H "Authorization: token ${FORGEJO_TOKEN}")
  if [[ "$DEL_RESPONSE" != "204" ]]; then
    echo "ERROR: Failed to delete pull mirror repo (HTTP ${DEL_RESPONSE}):"
    cat /tmp/forgejo_del.json
    echo ""
    exit 1
  fi
  echo "    Pull mirror deleted."
  REPO_HTTP="404"
fi

if [[ "$REPO_HTTP" == "200" ]]; then
  echo "    Repo already exists as primary on Forgejo — skipping creation."
else
  echo "--> Creating repo on Forgejo..."
  RESPONSE=$(curl -s -o /tmp/forgejo_create.json -w "%{http_code}" \
    -X POST "${FORGEJO_URL}/api/v1/user/repos" \
    -H "Authorization: token ${FORGEJO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${REPO_NAME}\", \"private\": true, \"auto_init\": false}")
  if [[ "$RESPONSE" == "201" ]]; then
    echo "    Created: ${FORGEJO_URL}/${FORGEJO_USER}/${REPO_NAME}"
  elif [[ "$RESPONSE" == "409" ]]; then
    echo "    Repo already exists (HTTP 409) — continuing."
  elif [[ "$RESPONSE" == "403" ]]; then
    echo "ERROR: HTTP 403 creating repo — token missing 'write:user' scope."
    echo "  Regenerate at ${FORGEJO_URL}/user/settings/applications with write:user + write:repository scopes."
    cat /tmp/forgejo_create.json
    echo ""
    exit 1
  else
    echo "ERROR: Failed to create repo (HTTP ${RESPONSE}):"
    cat /tmp/forgejo_create.json
    echo ""
    exit 1
  fi
fi

# 2. Push all branches and tags to Forgejo
echo "--> Pushing all branches and tags to Forgejo..."
cd "${REPO_PATH}"
if git remote get-url forgejo &>/dev/null; then
  git remote set-url forgejo "${FORGEJO_SSH}/${FORGEJO_USER}/${REPO_NAME}.git"
else
  git remote add forgejo "${FORGEJO_SSH}/${FORGEJO_USER}/${REPO_NAME}.git"
fi
git push forgejo --all
git push forgejo --tags
echo "    Pushed all branches and tags."

# 3. Configure push mirror: Forgejo -> GitHub (skip if already configured)
echo "--> Configuring push mirror: Forgejo -> GitHub..."
EXISTING_MIRROR=$(curl -s \
  "${FORGEJO_URL}/api/v1/repos/${FORGEJO_USER}/${REPO_NAME}/push_mirrors" \
  -H "Authorization: token ${FORGEJO_TOKEN}")
GITHUB_REMOTE="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
if echo "${EXISTING_MIRROR}" | grep -q "\"remote_address\":\"${GITHUB_REMOTE}\""; then
  echo "    Push mirror already configured — skipping."
else
  RESPONSE=$(curl -s -o /tmp/forgejo_mirror.json -w "%{http_code}" \
    -X POST "${FORGEJO_URL}/api/v1/repos/${FORGEJO_USER}/${REPO_NAME}/push_mirrors" \
    -H "Authorization: token ${FORGEJO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"remote_address\": \"${GITHUB_REMOTE}\",
      \"remote_username\": \"${GITHUB_USER}\",
      \"remote_password\": \"${GITHUB_PAT}\",
      \"sync_on_commit\": true,
      \"interval\": \"8h0m0s\"
    }")
  if [[ "$RESPONSE" == "200" || "$RESPONSE" == "201" ]]; then
    echo "    Push mirror configured: Forgejo -> GitHub (syncs on every commit)"
  elif [[ "$RESPONSE" == "422" ]]; then
    echo "    Push mirror already exists (HTTP 422) — skipping."
  else
    echo "ERROR: Failed to configure push mirror (HTTP ${RESPONSE}):"
    cat /tmp/forgejo_mirror.json
    echo ""
    exit 1
  fi
fi

# 4. Rewire origin remote
echo "--> Rewiring origin remote..."
git remote set-url origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
git remote set-url --push origin "${FORGEJO_SSH}/${FORGEJO_USER}/${REPO_NAME}.git"

echo ""
echo "==> Migration complete for ${REPO_NAME}!"
echo ""
echo "Remote state:"
git remote -v
echo ""
echo "Next steps:"
echo "  1. Push .forgejo/workflows/ and .gitleaks.toml via PR on Forgejo"
echo "  2. Enable branch protection on Forgejo master"
echo "  3. Add Repository admin bypass to GitHub branch ruleset"
echo "  4. Verify mirror: push to Forgejo, confirm GitHub receives it"
