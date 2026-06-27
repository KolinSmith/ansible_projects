#!/bin/bash
# Backs up all Forgejo repos owned by dax to Borg's HUB drive via Tailscale.
# Runs on DMZ (Forgejo is local; Borg reachable via Tailscale at 100.72.103.67).
# Deployed and scheduled by Ansible (setup_oracle_vps role).
set -euo pipefail

SECRETS_FILE="/home/ubuntu/.secrets/forgejo-backup.env"
FORGEJO_SSH="ssh://git@127.0.0.1:222"
FORGEJO_API="http://127.0.0.1:3001/api/v1"
STAGING="/tmp/forgejo-backup-staging"
BORG_DEST="kolin@100.72.103.67:/mnt/disks/HUB/BACKUPS/forgejo_backup"
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -i /home/ubuntu/.ssh/id_ecdsa"

if [ ! -f "$SECRETS_FILE" ]; then
  echo "ERROR: secrets file not found: $SECRETS_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$SECRETS_FILE"
# Expects: FORGEJO_API_TOKEN, UPTIME_KUMA_PUSH_URL

REPOS=$(curl -sf "${FORGEJO_API}/user/repos?limit=50" \
  -H "Authorization: token ${FORGEJO_API_TOKEN}" \
  | python3 -c "import sys,json; [print(r['full_name']) for r in json.load(sys.stdin) if r['owner']['login']=='dax']")

if [ -z "$REPOS" ]; then
  echo "ERROR: no repos found via Forgejo API" >&2
  exit 1
fi

mkdir -p "$STAGING"

while IFS= read -r repo; do
  name=$(basename "$repo")
  dest="$STAGING/${name}.git"
  echo "Backing up: $repo"
  if [ -d "$dest" ]; then
    git -C "$dest" remote update --prune
  else
    git clone --bare "${FORGEJO_SSH}/${repo}.git" "$dest"
  fi
done <<< "$REPOS"

rsync -a --delete -e "ssh -i /home/ubuntu/.ssh/id_ecdsa -o StrictHostKeyChecking=accept-new" \
  "$STAGING/" "$BORG_DEST/"
rm -rf "$STAGING"

curl -fsS "${UPTIME_KUMA_PUSH_URL}?status=up&msg=OK&ping=" > /dev/null
echo "Forgejo backup complete: $(date)"
