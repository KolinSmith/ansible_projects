#!/usr/bin/env bash
# =============================================================================
# pia-reregister.sh — Daily PIA WireGuard key re-registration for pfSense
# =============================================================================
#
# PROBLEM THIS SOLVES
# -------------------
# PIA (Private Internet Access) WireGuard uses short-lived key registrations.
# When you connect to a PIA WireGuard server, you call their /addKey API with:
#   - A one-time token (obtained from PIA's token API using your credentials)
#   - Your WireGuard public key
#
# PIA responds with:
#   - server_key: the PIA server's WireGuard public key (changes per registration)
#   - peer_ip:    the tunnel IP assigned to your side (e.g. 10.237.0.50)
#
# These registrations expire after an unknown period (observed: hours to days).
# When a registration expires:
#   - The WireGuard handshake goes stale (wg show: "latest handshake: never")
#   - Traffic stops routing through the VPN silently
#   - pfSense shows the interface as up but no data flows
#
# This script re-registers daily at 2 AM so the tunnel never expires.
#
# HOW IT WORKS
# ------------
# pfSense's WireGuard UI has a bug: it silently ignores pasted private keys and
# keeps its own internally generated key. You CANNOT manage keys through the UI.
# Instead, we:
#
#   1. Read PIA credentials from Ansible vault (never stored in plaintext)
#   2. Call PIA's get_token.sh to obtain a fresh one-time auth token
#   3. Call PIA's /addKey API with pfSense's actual public key (read directly
#      from /usr/local/etc/wireguard/tun_wg0.conf on pfSense)
#   4. SCP a PHP script to pfSense and run it to update config.xml in-place
#      (updating the peer's public key and the interface's tunnel IP)
#   5. Run `wg set` on pfSense to sync the live WireGuard peer state
#      WITHOUT restarting the interface (see CRITICAL NOTE below)
#   6. Update the live interface inet address on pfSense to match peer_ip
#      (`wg set` updates the peer but not the interface IP — if peer_ip changed,
#      PIA routes return traffic to the new IP, not the old one on the interface)
#   7. Verify the tunnel by polling `wg show` for a fresh handshake
#   8. Ping Uptime Kuma on success; absence of ping = Kuma alerts on failure
#
# CRITICAL NOTE: rc.newwanip MUST NOT BE CALLED
# ----------------------------------------------
# Calling `rc.newwanip opt6` (the normal pfSense way to apply interface changes)
# triggers a kernel panic on pfSense 2.7.2 / FreeBSD 14.0-CURRENT. The panic
# is a page fault in ifc_find_cloner() caused by a race between:
#   - WireGuard interface going DOWN during reconfiguration
#   - netlink RTM_GETLINK scanning the interface list simultaneously
# pfSense auto-reboots from the panic, but this is a ~2 minute outage.
# Using `wg set` directly updates the live kernel WireGuard state safely.
#
# DEPLOYMENT
# ----------
# Managed by Ansible role: provision_dev_server
# Script location on Voyager: /home/dax/.scripts/pia-reregister.sh
# Companion script:           /home/dax/.scripts/pia-pfsense-update.php
# Cron (Voyager, user dax):   0 2 * * * /home/dax/.scripts/pia-reregister.sh
# Log file:                   /var/log/pia-reregister.log
# Uptime Kuma monitor:        Push monitor; alerts if no heartbeat in 26h
#
# CREDENTIALS
# -----------
# PIA credentials (vault_pia_user, vault_pia_pass) and the Uptime Kuma push
# URL (vault_uptime_kuma_pia_push_url) are read from Ansible vault at runtime.
# Nothing sensitive is stored on disk or committed to git.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

readonly PIA_SERVER_IP="151.240.66.252"
readonly PIA_SERVER_HOST="Server-12244-2a"
readonly PIA_SERVER_PORT="1337"
readonly PIA_MANUAL_CONNECTIONS_DIR="${HOME}/code_base/manual-connections"
readonly PIA_CA_CERT="${PIA_MANUAL_CONNECTIONS_DIR}/ca.rsa.4096.crt"
readonly GET_TOKEN_SCRIPT="${PIA_MANUAL_CONNECTIONS_DIR}/get_token.sh"
readonly PFSENSE_WG_PUBKEY="4NeVHk1cLDWfE+ahM61GfwgdMF+iNurOduFs4f4aoHE="
readonly PFSENSE_HOST="kolin@192.168.3.1"
readonly PFSENSE_WG_IFACE="tun_wg0"
readonly PFSENSE_GW_MONITOR_IP="1.1.1.1"
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
# Step 1: Read credentials from Ansible vault
# ---------------------------------------------------------------------------

log "Starting PIA WireGuard re-registration"
log "Reading credentials from Ansible vault"

VAULT_FILE="${HOME}/code_base/ansible_projects/group_vars/all/vault.yml"
VAULT_PASS_FILE="${HOME}/code_base/dotfiles/.ansible_password"

[[ -f "${VAULT_FILE}" ]]      || die "Vault file not found: ${VAULT_FILE}"
[[ -f "${VAULT_PASS_FILE}" ]] || die "Vault password file not found: ${VAULT_PASS_FILE}"
[[ -f "${PIA_CA_CERT}" ]]     || die "CA cert not found: ${PIA_CA_CERT}"
[[ -f "${GET_TOKEN_SCRIPT}" ]] || die "get_token.sh not found: ${GET_TOKEN_SCRIPT}"

_VAULT=(ansible-vault view "${VAULT_FILE}" --vault-id "${VAULT_PASS_FILE}")

PIA_USER=$("${_VAULT[@]}" | awk '/^vault_pia_user:/{print $2}') \
    || die "Failed to read vault_pia_user from vault"
PIA_PASS=$("${_VAULT[@]}" | awk "/^vault_pia_pass:/{gsub(/^'|'\$/, \"\", \$2); print \$2}") \
    || die "Failed to read vault_pia_pass from vault"
UPTIME_KUMA_URL=$("${_VAULT[@]}" | awk '/^vault_uptime_kuma_pia_push_url:/{gsub(/^"|"$/, "", $2); print $2}') \
    || die "Failed to read vault_uptime_kuma_pia_push_url from vault"

[[ -n "${PIA_USER}" ]]         || die "vault_pia_user is empty"
[[ -n "${PIA_PASS}" ]]         || die "vault_pia_pass is empty"
[[ -n "${UPTIME_KUMA_URL}" ]]  || die "vault_uptime_kuma_pia_push_url is empty"

log "Credentials loaded for user: ${PIA_USER}"

# ---------------------------------------------------------------------------
# Step 2: Get a fresh PIA token
#
# get_token.sh calls PIA's auth API and writes a one-time token to
# /opt/piavpn-manual/token. Tokens are single-use — each /addKey call
# consumes one. Requires sudo because it writes to /opt/piavpn-manual/.
# ---------------------------------------------------------------------------

log "Obtaining fresh PIA token via get_token.sh"

sudo PIA_USER="${PIA_USER}" PIA_PASS="${PIA_PASS}" "${GET_TOKEN_SCRIPT}" > /dev/null 2>&1 \
    || die "get_token.sh failed — check PIA credentials and network connectivity"

TOKEN=$(sudo head -1 "${TOKEN_FILE}") \
    || die "Cannot read token from ${TOKEN_FILE}"

[[ -n "${TOKEN}" ]] || die "Token is empty after get_token.sh succeeded"

TOKEN_MTIME=$(stat -c %Y "${TOKEN_FILE}" 2>/dev/null) || die "Cannot stat token file: ${TOKEN_FILE}"
TOKEN_AGE=$(( $(date +%s) - TOKEN_MTIME ))
(( TOKEN_AGE < 300 )) || die "Token file not recently updated (age: ${TOKEN_AGE}s) — get_token.sh may have failed silently"

log "Token obtained (length: ${#TOKEN})"

# ---------------------------------------------------------------------------
# Step 3: Call PIA /addKey API to register pfSense's WireGuard public key
#
# We use --connect-to to route the HTTPS request to the server's IP directly
# while presenting the hostname in SNI (required for TLS cert validation against
# PIA's CA). The server responds with a new server_key and peer_ip.
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
# Step 5: Update pfSense config.xml via PHP script
#
# pia-pfsense-update.php updates three values in pfSense's config.xml:
#   - The WireGuard peer's public key (server_key)
#   - The WireGuard interface's tunnel address (peer_ip)
#   - The PIA_OVER_WIREGUARD gateway IP (peer_ip)
# It calls pfSense's write_config() to persist the changes and trigger
# config sync. The PHP script is SCP'd fresh each run so it stays in sync
# with any updates deployed by Ansible.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "Copying PHP updater to pfSense"

scp -q "${SCRIPT_DIR}/pia-pfsense-update.php" "${PFSENSE_HOST}:/tmp/pia-pfsense-update.php" \
    || die "scp of pia-pfsense-update.php to pfSense failed"

log "Running PHP updater on pfSense"

ssh "${PFSENSE_HOST}" "sudo php /tmp/pia-pfsense-update.php '${SERVER_KEY}' '${PEER_IP}'" \
    || die "PHP updater on pfSense failed"

log "pfSense config updated successfully"

# ---------------------------------------------------------------------------
# Step 6: Sync live WireGuard state with `wg set`
#
# config.xml is now updated but the live WireGuard kernel state still has the
# old peer key and endpoint. `wg set` updates the kernel state atomically
# without taking the interface down.
#
# IMPORTANT: Do NOT use rc.newwanip — it triggers a kernel panic on pfSense
# 2.7.2 / FreeBSD 14.0-CURRENT (page fault in ifc_find_cloner via netlink
# RTM_GETLINK racing against WireGuard interface DOWN). See header comment.
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
# Step 6b: Update live interface IP on pfSense
#
# `wg set` updates the WireGuard peer (public key, endpoint, allowed IPs) but
# does NOT update the inet address on tun_wg0. If peer_ip changed between
# re-registrations, the interface keeps the old IP. PIA assigns return traffic
# to the new peer_ip — packets leave pfSense fine but responses are dropped
# because the old IP is no longer the registered address for this peer key.
#
# We also update the gateway monitor's host route for PFSENSE_GW_MONITOR_IP
# to use the new interface IP as its gateway. Deleting the route is avoided
# because dpinger (in "down" state) may not re-add it, causing a chicken-and-
# egg situation where pings can't flow without the route to add the route.
# ---------------------------------------------------------------------------

log "Updating live interface IP on pfSense (${PFSENSE_WG_IFACE} -> ${PEER_IP})"

ssh "${PFSENSE_HOST}" /bin/sh <<EOF || die "ifconfig update on pfSense failed"
CURR=\$(ifconfig ${PFSENSE_WG_IFACE} | awk '/inet /{print \$2; exit}')
if [ "\${CURR}" = "${PEER_IP}" ]; then
    echo "Interface IP already ${PEER_IP} -- no update needed"
else
    echo "Updating interface IP: \${CURR} -> ${PEER_IP}"
    [ -n "\${CURR}" ] && sudo ifconfig ${PFSENSE_WG_IFACE} inet "\${CURR}" delete
    sudo ifconfig ${PFSENSE_WG_IFACE} inet "${PEER_IP}" netmask 0xffffffff
    sudo route -q change -host ${PFSENSE_GW_MONITOR_IP} ${PEER_IP} 2>/dev/null || \
        sudo route -q add -host ${PFSENSE_GW_MONITOR_IP} ${PEER_IP} 2>/dev/null || true
    OLD_PID_FILE="/var/run/dpinger_PIA_OVER_WIREGUARD~\${CURR}~${PFSENSE_GW_MONITOR_IP}.pid"
    [ -f "\${OLD_PID_FILE}" ] && sudo kill "\$(cat \${OLD_PID_FILE})" 2>/dev/null || true
    sudo /usr/local/bin/dpinger -S -r 0 -i PIA_OVER_WIREGUARD \
        -B "${PEER_IP}" \
        -p "/var/run/dpinger_PIA_OVER_WIREGUARD~${PEER_IP}~${PFSENSE_GW_MONITOR_IP}.pid" \
        -u "/var/run/dpinger_PIA_OVER_WIREGUARD~${PEER_IP}~${PFSENSE_GW_MONITOR_IP}.sock" \
        -C /etc/rc.gateway_alarm \
        -d 1 -s 500 -l 2000 -t 60000 -A 1000 -D 500 -L 20 \
        "${PFSENSE_GW_MONITOR_IP}"
fi
EOF

log "Interface IP update complete"

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

# ---------------------------------------------------------------------------
# Step 8: Ping Uptime Kuma healthcheck
#
# The Uptime Kuma push monitor expects a heartbeat within its configured
# window (set to 26h to give the 2 AM cron a 2h grace period). A missing
# heartbeat means the script failed somewhere above and Kuma will alert.
# ---------------------------------------------------------------------------

log "Pinging Uptime Kuma healthcheck"

curl -fsS --max-time 10 "${UPTIME_KUMA_URL}" > /dev/null \
    || log "WARN: Uptime Kuma ping failed — tunnel is up but healthcheck not confirmed"

log "PIA WireGuard re-registration completed successfully"
