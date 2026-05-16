#!/usr/bin/env bash
# pia-reregister.sh — Re-register pfSense WireGuard public key with PIA
#
# Runs daily as a cron job on Voyager. Re-registers the pfSense WireGuard
# public key with PIA, updates pfSense config when the peer IP changes,
# and syncs live WireGuard state via `wg set`.
#
# NOTE: Do NOT call rc.newwanip — it triggers a kernel panic on pfSense
# 2.7.2 / FreeBSD 14.0-CURRENT due to WireGuard interface DOWN races with
# netlink RTM_GETLINK. `wg set` alone is sufficient.

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

readonly PIA_SERVER_IP="151.240.66.252"
readonly PIA_SERVER_HOST="Server-12244-2a"
readonly PIA_SERVER_PORT="1337"
readonly PIA_CA_CERT="${HOME}/code_base/manual-connections/ca.rsa.4096.crt"
readonly PFSENSE_WG_PUBKEY="4NeVHk1cLDWfE+ahM61GfwgdMF+iNurOduFs4f4aoHE="
readonly PFSENSE_HOST="kolin@192.168.3.1"
readonly PFSENSE_WG_IFACE="tun_wg0"
readonly TOKEN_FILE="/opt/piavpn-manual/token"

# Handshake verification: poll every 5s, up to 12 tries (60s total)
readonly HANDSHAKE_POLL_INTERVAL=5
readonly HANDSHAKE_MAX_TRIES=12
# A handshake is "fresh" if it occurred within the last 120s
readonly HANDSHAKE_MAX_AGE=120

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log() {
    local msg="$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') pia-reregister: ${msg}"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Step 0: Resolve the script's own directory so relative paths work correctly
#         when called from cron (cwd may not be the script dir).
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log "Starting PIA WireGuard re-registration"
log "Script dir: ${SCRIPT_DIR}"

cd "${SCRIPT_DIR}" || die "Cannot cd to script directory: ${SCRIPT_DIR}"
[[ -f "${PIA_CA_CERT}" ]] || die "CA cert not found: ${PIA_CA_CERT}"

# ---------------------------------------------------------------------------
# Step 1: Read credentials from Ansible vault
# ---------------------------------------------------------------------------

log "Reading credentials from Ansible vault"

VAULT_FILE="${HOME}/code_base/ansible_projects/group_vars/all/vault.yml"
VAULT_PASS_FILE="${HOME}/code_base/dotfiles/.ansible_password"

[[ -f "${VAULT_FILE}" ]]      || die "Vault file not found: ${VAULT_FILE}"
[[ -f "${VAULT_PASS_FILE}" ]] || die "Vault password file not found: ${VAULT_PASS_FILE}"

_VAULT=(ansible-vault view "${VAULT_FILE}" --vault-id "${VAULT_PASS_FILE}")

PIA_USER=$("${_VAULT[@]}" | awk '/^vault_pia_user:/{print $2}') \
    || die "Failed to read vault_pia_user from vault"
PIA_PASS=$("${_VAULT[@]}" | awk "/^vault_pia_pass:/{gsub(/^'|'\$/, \"\", \$2); print \$2}") \
    || die "Failed to read vault_pia_pass from vault"

[[ -n "${PIA_USER}" ]] || die "vault_pia_user is empty — check vault contents"
[[ -n "${PIA_PASS}" ]] || die "vault_pia_pass is empty — check vault contents"

log "Credentials loaded for user: ${PIA_USER}"

# ---------------------------------------------------------------------------
# Step 2: Get a fresh PIA token
# ---------------------------------------------------------------------------

log "Obtaining fresh PIA token via get_token.sh"

sudo PIA_USER="${PIA_USER}" PIA_PASS="${PIA_PASS}" ./get_token.sh > /dev/null 2>&1 \
    || die "get_token.sh failed — check PIA credentials and network connectivity"

TOKEN=$(sudo head -1 "${TOKEN_FILE}") \
    || die "Cannot read token from ${TOKEN_FILE}"

[[ -n "${TOKEN}" ]] || die "Token is empty after get_token.sh succeeded"

TOKEN_MTIME=$(stat -c %Y "${TOKEN_FILE}" 2>/dev/null) || die "Cannot stat token file: ${TOKEN_FILE}"
TOKEN_AGE=$(( $(date +%s) - TOKEN_MTIME ))
(( TOKEN_AGE < 300 )) || die "Token file not recently updated (age: ${TOKEN_AGE}s) — get_token.sh may have failed silently (bad credentials?)"

log "Token obtained (length: ${#TOKEN})"

# ---------------------------------------------------------------------------
# Step 3: Call PIA /addKey API to register pfSense WireGuard public key
# ---------------------------------------------------------------------------

log "Calling PIA /addKey API (server: ${PIA_SERVER_HOST} / ${PIA_SERVER_IP}:${PIA_SERVER_PORT})"

ADD_KEY_RESPONSE=$(curl -s -G \
    --connect-to "${PIA_SERVER_HOST}::${PIA_SERVER_IP}:" \
    --cacert "${PIA_CA_CERT}" \
    --data-urlencode "pt=${TOKEN}" \
    --data-urlencode "pubkey=${PFSENSE_WG_PUBKEY}" \
    "https://${PIA_SERVER_HOST}:${PIA_SERVER_PORT}/addKey") \
    || die "curl to /addKey failed"

log "Raw /addKey response: ${ADD_KEY_RESPONSE}"

# ---------------------------------------------------------------------------
# Step 4: Parse the /addKey response
# ---------------------------------------------------------------------------

API_STATUS=$(echo "${ADD_KEY_RESPONSE}" | jq -r '.status // empty') \
    || die "Failed to parse /addKey response with jq"

[[ "${API_STATUS}" == "OK" ]] \
    || die "/addKey returned non-OK status: '${API_STATUS}'. Full response: ${ADD_KEY_RESPONSE}"

SERVER_KEY=$(echo "${ADD_KEY_RESPONSE}" | jq -r '.server_key // empty') \
    || die "jq failed extracting server_key"
PEER_IP=$(echo "${ADD_KEY_RESPONSE}" | jq -r '.peer_ip // empty') \
    || die "jq failed extracting peer_ip"

[[ -n "${SERVER_KEY}" ]] || die "server_key is empty in /addKey response"
[[ -n "${PEER_IP}" ]]    || die "peer_ip is empty in /addKey response"

log "server_key: ${SERVER_KEY}"
log "peer_ip:    ${PEER_IP}"

# ---------------------------------------------------------------------------
# Step 5: Update pfSense config via PHP updater script
# ---------------------------------------------------------------------------

log "Copying PHP updater to pfSense"

scp -q "${SCRIPT_DIR}/pia-pfsense-update.php" "${PFSENSE_HOST}:/tmp/pia-pfsense-update.php" \
    || die "scp of pia-pfsense-update.php to pfSense failed"

log "Running PHP updater on pfSense"

ssh "${PFSENSE_HOST}" "sudo php /tmp/pia-pfsense-update.php '${SERVER_KEY}' '${PEER_IP}'" \
    || die "PHP updater on pfSense failed"

log "pfSense config updated successfully"

# ---------------------------------------------------------------------------
# Step 6: Sync live WireGuard state with `wg set`
#         NOTE: Do NOT call rc.newwanip — kernel panic risk on pfSense 2.7.2
# ---------------------------------------------------------------------------

log "Syncing live WireGuard state on pfSense (wg set, no rc.newwanip)"

ssh "${PFSENSE_HOST}" "sudo wg set ${PFSENSE_WG_IFACE} \
    peer '${SERVER_KEY}' \
    endpoint '${PIA_SERVER_IP}:${PIA_SERVER_PORT}' \
    allowed-ips '0.0.0.0/0' \
    persistent-keepalive 25" \
    || die "wg set on pfSense failed"

log "wg set completed"

# ---------------------------------------------------------------------------
# Step 7: Verify WireGuard handshake within 60s
# ---------------------------------------------------------------------------

log "Waiting for WireGuard handshake (up to $((HANDSHAKE_MAX_TRIES * HANDSHAKE_POLL_INTERVAL))s)"

HANDSHAKE_OK=false
for (( attempt=1; attempt<=HANDSHAKE_MAX_TRIES; attempt++ )); do
    log "Handshake check attempt ${attempt}/${HANDSHAKE_MAX_TRIES}"

    # `wg show <iface> latest-handshakes` prints: <pubkey>\t<unix-epoch>
    # We match on the server key we just registered.
    HANDSHAKE_OUTPUT=$(ssh "${PFSENSE_HOST}" "sudo wg show ${PFSENSE_WG_IFACE} latest-handshakes" 2>/dev/null) \
        || { log "WARN: wg show failed on attempt ${attempt}, retrying"; sleep "${HANDSHAKE_POLL_INTERVAL}"; continue; }

    HANDSHAKE_TS=$(echo "${HANDSHAKE_OUTPUT}" \
        | awk -v key="${SERVER_KEY}" '$1 == key {print $2}')

    if [[ -z "${HANDSHAKE_TS}" || "${HANDSHAKE_TS}" == "0" ]]; then
        log "No handshake recorded yet for server_key"
        sleep "${HANDSHAKE_POLL_INTERVAL}"
        continue
    fi

    NOW=$(date +%s)
    AGE=$(( NOW - HANDSHAKE_TS ))

    log "Handshake timestamp: ${HANDSHAKE_TS} (age: ${AGE}s)"

    if (( AGE < HANDSHAKE_MAX_AGE )); then
        log "Handshake is fresh (age ${AGE}s < ${HANDSHAKE_MAX_AGE}s) — tunnel is UP"
        HANDSHAKE_OK=true
        break
    else
        log "Handshake is stale (age ${AGE}s >= ${HANDSHAKE_MAX_AGE}s), waiting"
        sleep "${HANDSHAKE_POLL_INTERVAL}"
    fi
done

if [[ "${HANDSHAKE_OK}" != "true" ]]; then
    die "No fresh WireGuard handshake after $((HANDSHAKE_MAX_TRIES * HANDSHAKE_POLL_INTERVAL))s — tunnel may be down"
fi

log "PIA WireGuard re-registration completed successfully"
