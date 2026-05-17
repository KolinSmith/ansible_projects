#!/usr/bin/env bash
# Migrates a GitHub repo to Forgejo as primary, with GitHub as automatic push mirror.
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
# What it does:
#   1. Creates the repo on Forgejo via API
#   2. Pushes all local branches + tags to Forgejo
#   3. Configures Forgejo push mirror -> GitHub
#   4. Rewires local origin: fetch=GitHub HTTPS, push=Forgejo SSH
#   5. Adds a 'forgejo' remote pointing to Forgejo

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

# 1. Create repo on Forgejo
echo "--> Creating repo on Forgejo..."
RESPONSE=$(curl -s -o /tmp/forgejo_create.json -w "%{http_code}" \
  -X POST "${FORGEJO_URL}/api/v1/user/repos" \
  -H "Authorization: token ${FORGEJO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${REPO_NAME}\", \"private\": true, \"auto_init\": false}")
if [[ "$RESPONSE" != "201" ]]; then
  echo "ERROR: Failed to create repo (HTTP ${RESPONSE}):"
  cat /tmp/forgejo_create.json
  echo ""
  echo "If HTTP 409, repo may already exist on Forgejo — that's OK, continuing."
  if [[ "$RESPONSE" != "409" ]]; then
    exit 1
  fi
else
  echo "    Created: ${FORGEJO_URL}/${FORGEJO_USER}/${REPO_NAME}"
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

# 3. Configure push mirror: Forgejo -> GitHub
echo "--> Configuring push mirror: Forgejo -> GitHub..."
RESPONSE=$(curl -s -o /tmp/forgejo_mirror.json -w "%{http_code}" \
  -X POST "${FORGEJO_URL}/api/v1/repos/${FORGEJO_USER}/${REPO_NAME}/push_mirrors" \
  -H "Authorization: token ${FORGEJO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"remote_address\": \"https://github.com/${GITHUB_USER}/${REPO_NAME}.git\",
    \"remote_username\": \"${GITHUB_USER}\",
    \"remote_password\": \"${GITHUB_PAT}\",
    \"sync_on_commit\": true,
    \"interval\": \"8h0m0s\"
  }")
if [[ "$RESPONSE" != "200" && "$RESPONSE" != "201" ]]; then
  echo "ERROR: Failed to configure push mirror (HTTP ${RESPONSE}):"
  cat /tmp/forgejo_mirror.json
  echo ""
  exit 1
fi
echo "    Push mirror configured: Forgejo -> GitHub (syncs on every commit)"

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
echo "  1. Push .forgejo/workflows/validate.yml and .gitleaks.toml via PR"
echo "  2. Enable branch protection on Forgejo master"
echo "  3. Add Repository admin bypass to GitHub branch ruleset"
echo "  4. Verify mirror: push to Forgejo, confirm GitHub receives it"
