#!/bin/bash
# Backs up all Forgejo repos accessible to the dax user to Borg's HUB drive.
# Runs on Voyager (has Forgejo SSH key + Borg SSH access).
# Rendered secrets file provides the Forgejo API token for repo discovery.
# Schedule: daily at 5:30am via cron.
set -euo pipefail

SECRETS_FILE="/home/dax/.secrets/forgejo-backup.env"
FORGEJO_SSH="ssh://git@100.86.4.29:222"
FORGEJO_API="http://100.86.4.29:3001/api/v1"
STAGING="/tmp/forgejo-backup-staging"
BORG_DEST="kolin@192.168.9.7:/mnt/disks/HUB/BACKUPS/forgejo_backup"

if [ ! -f "$SECRETS_FILE" ]; then
  echo "ERROR: secrets file not found: $SECRETS_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$SECRETS_FILE"
# Expects: FORGEJO_API_TOKEN, UPTIME_KUMA_PUSH_URL

# Discover all repos owned by dax (not mirrors or other users' repos)
REPOS=$(curl -sf "${FORGEJO_API}/user/repos?limit=50" \
  -H "Authorization: token ${FORGEJO_API_TOKEN}" \
  | python3 -c "import sys,json; [print(r['full_name']) for r in json.load(sys.stdin) if r['owner']['login']=='dax']")

if [ -z "$REPOS" ]; then
  echo "ERROR: no repos found via Forgejo API" >&2
  exit 1
fi

echo "Repos to back up:"
echo "$REPOS"

mkdir -p "$STAGING"

while IFS= read -r repo; do
  name=$(basename "$repo")
  dest="$STAGING/${name}.git"
  echo "--- Backing up: $repo"
  if [ -d "$dest" ]; then
    git -C "$dest" remote update --prune
  else
    git clone --bare "${FORGEJO_SSH}/${repo}.git" "$dest"
  fi
done <<< "$REPOS"

rsync -a --delete "$STAGING/" "$BORG_DEST/"
rm -rf "$STAGING"

curl -fsS "${UPTIME_KUMA_PUSH_URL}?status=up&msg=OK&ping=" > /dev/null
echo "Forgejo backup complete: $(date)"
