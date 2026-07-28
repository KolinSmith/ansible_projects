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
# SERVER SELECTION (rewritten 2026-07-27)
# ----------------------------------------
# Originally this script targeted one hardcoded PIA server. On 2026-07-27,
# PIA silently decommissioned that server (Server-12244-2a) — it dropped off
# PIA's public server list with no notice. The cron kept "succeeding" as long
# as the dead server still accepted addKey calls; once PIA fully pulled it,
# every attempt started timing out at the TCP level and the tunnel died with
# no automatic recovery. A hand-picked replacement server was found to
# already be absent from PIA's *current* published list within hours of being
# chosen — proof a single hardcoded server is fundamentally fragile.
#
# Now the script pulls PIA's live server list for the Texas region
# (closest to this deployment) at every run and tries candidates in order:
#   1. The last server that worked (persisted in PIA_SERVER_STATE_FILE)
#   2. Every other WireGuard server PIA currently publishes for the region
# If a candidate's addKey call fails, or the handshake never comes up fresh,
# the script automatically moves to the next candidate in the same run —
# no more silent, invisible failures. The winning server is persisted for
# next time so happy-path runs don't re-shop the whole region.
#
# HOW IT WORKS
# ------------
# pfSense's WireGuard UI has a bug: it silently ignores pasted private keys and
# keeps its own internally generated key. You CANNOT manage keys through the UI.
# Instead, we:
#
#   1. Read PIA credentials from Ansible vault (never stored in plaintext)
#   2. Call PIA's get_token.sh to obtain a fresh one-time auth token
#   3. Fetch PIA's live server list and build a candidate order (see above)
#   4. For each candidate, call PIA's /addKey API with pfSense's actual public
#      key (read directly from /usr/local/etc/wireguard/tun_wg0.conf on pfSense)
#   5. SCP a PHP script to pfSense and run it to update config.xml in-place
#      (peer public key, peer endpoint, interface tunnel IP)
#   6. Run `wg set` on pfSense to sync the live WireGuard peer state
#      WITHOUT restarting the interface (see CRITICAL NOTE below)
#   7. Update the live interface inet address on pfSense to match peer_ip
#      (`wg set` updates the peer but not the interface IP — if peer_ip changed,
#      PIA routes return traffic to the new IP, not the old one on the interface)
#   8. Verify the tunnel by polling `wg show` for a fresh handshake; if this
#      fails, move on to the next candidate server instead of giving up
#   9. Once a candidate succeeds: persist it, remove stale WireGuard peers
#      left over from past registrations, reload pf rules, flush pf states
#  10. Ping Uptime Kuma on success; absence of ping = Kuma alerts on failure
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
# State file (last-good server, not committed): /opt/piavpn-manual/pia-current-server.env
# Uptime Kuma monitor:        Push monitor; alerts if no heartbeat in 26h
#
# CREDENTIALS
# -----------
# PIA credentials (vault_pia_user, vault_pia_pass) and the Uptime Kuma push
# URL (vault_uptime_kuma_pia_push_url) are read from Ansible vault at runtime.
# Nothing sensitive is stored on disk or committed to git.
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

readonly PIA_REGION="us_south_west"   # PIA's region id for US Texas (closest to this deployment)
readonly PIA_SERVERLIST_URL="https://serverlist.piaservers.net/vpninfo/servers/v6"
readonly PIA_SERVER_PORT="1337"
readonly PIA_SERVER_STATE_FILE="${HOME}/.cache/pia-current-server.env"
readonly PIA_MANUAL_CONNECTIONS_DIR="${HOME}/code_base/manual-connections"
readonly PIA_CA_CERT="${PIA_MANUAL_CONNECTIONS_DIR}/ca.rsa.4096.crt"
readonly GET_TOKEN_SCRIPT="${PIA_MANUAL_CONNECTIONS_DIR}/get_token.sh"
readonly PFSENSE_WG_PUBKEY="4NeVHk1cLDWfE+ahM61GfwgdMF+iNurOduFs4f4aoHE="
readonly PFSENSE_HOST="kolin@192.168.3.1"
readonly PFSENSE_WG_IFACE="tun_wg0"
readonly PFSENSE_GW_MONITOR_IP="1.1.1.1"
readonly TOKEN_FILE="/opt/piavpn-manual/token"

# Handshake verification: poll every 5s, up to 12 tries (60s total) per candidate
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
# Step 3: Build the candidate server list
#
# Fetch PIA's live, official server list and take every WireGuard server
# currently published for our region. Try the last-known-good server first
# (if we have one) so happy-path runs don't reshuffle candidates for no
# reason; fall through to the rest of the region on failure.
# ---------------------------------------------------------------------------

log "Fetching current PIA server list for region ${PIA_REGION}"

SERVER_LIST_JSON=$(curl -s --max-time 15 "${PIA_SERVERLIST_URL}" | head -1)
[[ ${#SERVER_LIST_JSON} -gt 1000 ]] || die "PIA server list response looks truncated/invalid (got ${#SERVER_LIST_JSON} bytes)"

REGION_CANDIDATES=$(echo "${SERVER_LIST_JSON}" \
    | jq -r --arg region "${PIA_REGION}" \
      '.regions[] | select(.id==$region) | .servers.wg[] | .ip+" "+.cn')
[[ -n "${REGION_CANDIDATES}" ]] || die "No WireGuard servers found for region ${PIA_REGION} — PIA may have renamed/dropped it"

LAST_GOOD=""
if [[ -f "${PIA_SERVER_STATE_FILE}" ]]; then
    LAST_GOOD=$(cat "${PIA_SERVER_STATE_FILE}" 2>/dev/null || true)
fi

# last-known-good first, then the rest of the region, de-duplicated
CANDIDATES=$(
    { [[ -n "${LAST_GOOD}" ]] && echo "${LAST_GOOD}"; echo "${REGION_CANDIDATES}"; } \
    | awk '!seen[$0]++'
)

CANDIDATE_COUNT=$(echo "${CANDIDATES}" | wc -l)
log "Candidate servers this run (${CANDIDATE_COUNT}): $(echo "${CANDIDATES}" | tr '\n' ',' | sed 's/,$//')"

# ---------------------------------------------------------------------------
# Step 4: Try each candidate until one works
#
# try_candidate registers pfSense's public key against a single PIA server
# and verifies the handshake comes up fresh. It returns 1 (instead of dying)
# on any failure so the caller can move on to the next candidate.
# Sets SERVER_KEY / PEER_IP / WINNING_IP / WINNING_CN on success.
# ---------------------------------------------------------------------------

try_candidate() {
    local candidate_ip="$1"
    local candidate_cn="$2"

    log "--- Trying candidate: ${candidate_cn} / ${candidate_ip}:${PIA_SERVER_PORT} ---"

    local add_key_response
    add_key_response=$(curl -s -G --max-time 15 \
        --connect-to "${candidate_cn}::${candidate_ip}:" \
        --cacert "${PIA_CA_CERT}" \
        --data-urlencode "pt=${TOKEN}" \
        --data-urlencode "pubkey=${PFSENSE_WG_PUBKEY}" \
        "https://${candidate_cn}:${PIA_SERVER_PORT}/addKey")
    if [[ $? -ne 0 || -z "${add_key_response}" ]]; then
        log "WARN: curl to /addKey failed for ${candidate_cn}"
        return 1
    fi

    log "Raw /addKey response: ${add_key_response}"

    local api_status
    api_status=$(echo "${add_key_response}" | jq -r '.status // empty')
    if [[ "${api_status}" != "OK" ]]; then
        log "WARN: /addKey returned non-OK status '${api_status}' for ${candidate_cn}"
        return 1
    fi

    SERVER_KEY=$(echo "${add_key_response}" | jq -r '.server_key // empty')
    PEER_IP=$(echo "${add_key_response}" | jq -r '.peer_ip // empty')

    if [[ -z "${SERVER_KEY}" || -z "${PEER_IP}" ]]; then
        log "WARN: server_key or peer_ip missing in /addKey response for ${candidate_cn}"
        return 1
    fi

    log "server_key: ${SERVER_KEY}"
    log "peer_ip:    ${PEER_IP}"

    # Update pfSense config.xml (peer key, peer endpoint, interface tunnel IP)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    log "Copying PHP updater to pfSense"
    scp -q "${script_dir}/pia-pfsense-update.php" "${PFSENSE_HOST}:/tmp/pia-pfsense-update.php" || {
        log "WARN: scp of pia-pfsense-update.php to pfSense failed"
        return 1
    }

    log "Running PHP updater on pfSense"
    ssh "${PFSENSE_HOST}" "sudo php /tmp/pia-pfsense-update.php '${SERVER_KEY}' '${PEER_IP}' '${candidate_ip}' '${PIA_SERVER_PORT}'" || {
        log "WARN: PHP updater on pfSense failed for ${candidate_cn}"
        return 1
    }
    log "pfSense config updated successfully"

    # Sync live WireGuard state with `wg set`. Do NOT use rc.newwanip — see
    # header comment (kernel panic on this pfSense/FreeBSD combination).
    log "Syncing live WireGuard state on pfSense (wg set, no rc.newwanip)"
    ssh "${PFSENSE_HOST}" "sudo wg set ${PFSENSE_WG_IFACE} \
        peer '${SERVER_KEY}' \
        endpoint '${candidate_ip}:${PIA_SERVER_PORT}' \
        allowed-ips '0.0.0.0/0' \
        persistent-keepalive 25" || {
        log "WARN: wg set on pfSense failed for ${candidate_cn}"
        return 1
    }
    log "wg set completed"

    # Update live interface IP if peer_ip changed. wg set updates the peer
    # but not the interface's inet address.
    log "Updating live interface IP on pfSense (${PFSENSE_WG_IFACE} -> ${PEER_IP})"
    # shellcheck disable=SC2087  # intentional: client expands ${PEER_IP} etc, server expands \${CURR}
    ssh "${PFSENSE_HOST}" /bin/sh <<EOF || { log "WARN: ifconfig update on pfSense failed for ${candidate_cn}"; return 1; }
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
    sudo nohup /usr/local/bin/dpinger -S -r 0 -i PIA_OVER_WIREGUARD \
        -B "${PEER_IP}" \
        -p "/var/run/dpinger_PIA_OVER_WIREGUARD~${PEER_IP}~${PFSENSE_GW_MONITOR_IP}.pid" \
        -u "/var/run/dpinger_PIA_OVER_WIREGUARD~${PEER_IP}~${PFSENSE_GW_MONITOR_IP}.sock" \
        -C /etc/rc.gateway_alarm \
        -d 1 -s 500 -l 2000 -t 60000 -A 1000 -D 500 -L 20 \
        "${PFSENSE_GW_MONITOR_IP}" </dev/null >/dev/null 2>&1 &
fi
EOF
    log "Interface IP update complete"

    # Verify handshake within 60s
    log "Waiting for WireGuard handshake (up to $((HANDSHAKE_MAX_TRIES * HANDSHAKE_POLL_INTERVAL))s)"
    local handshake_ok=false
    local attempt
    for (( attempt=1; attempt<=HANDSHAKE_MAX_TRIES; attempt++ )); do
        log "Handshake check attempt ${attempt}/${HANDSHAKE_MAX_TRIES}"

        local handshake_output
        handshake_output=$(ssh "${PFSENSE_HOST}" "sudo wg show ${PFSENSE_WG_IFACE} latest-handshakes" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            log "WARN: wg show failed on attempt ${attempt}, retrying"
            sleep "${HANDSHAKE_POLL_INTERVAL}"
            continue
        fi

        local handshake_ts
        handshake_ts=$(echo "${handshake_output}" | awk -v key="${SERVER_KEY}" '$1 == key {print $2}')

        if [[ -z "${handshake_ts}" || "${handshake_ts}" == "0" ]]; then
            log "No handshake recorded yet for server_key"
            sleep "${HANDSHAKE_POLL_INTERVAL}"
            continue
        fi

        local now age
        now=$(date +%s)
        age=$(( now - handshake_ts ))
        log "Handshake timestamp: ${handshake_ts} (age: ${age}s)"

        if (( age < HANDSHAKE_MAX_AGE )); then
            log "Handshake is fresh (age ${age}s < ${HANDSHAKE_MAX_AGE}s) — tunnel is UP"
            handshake_ok=true
            break
        else
            log "Handshake is stale (age ${age}s >= ${HANDSHAKE_MAX_AGE}s), waiting"
            sleep "${HANDSHAKE_POLL_INTERVAL}"
        fi
    done

    if [[ "${handshake_ok}" != "true" ]]; then
        log "WARN: no fresh handshake for ${candidate_cn} after $((HANDSHAKE_MAX_TRIES * HANDSHAKE_POLL_INTERVAL))s"
        return 1
    fi

    WINNING_IP="${candidate_ip}"
    WINNING_CN="${candidate_cn}"
    return 0
}

WINNER_FOUND=false
while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    candidate_ip="${line%% *}"
    candidate_cn="${line#* }"
    if try_candidate "${candidate_ip}" "${candidate_cn}"; then
        WINNER_FOUND=true
        break
    fi
done <<< "${CANDIDATES}"

[[ "${WINNER_FOUND}" == "true" ]] || die "Every candidate server failed — tunnel is down. Candidates tried: $(echo "${CANDIDATES}" | tr '\n' ',' | sed 's/,$//')"

if [[ -n "${LAST_GOOD}" && "${LAST_GOOD}" != "${WINNING_IP} ${WINNING_CN}" ]]; then
    log "NOTE: rotated away from previous server (${LAST_GOOD}) to ${WINNING_CN} / ${WINNING_IP}"
fi

mkdir -p "$(dirname "${PIA_SERVER_STATE_FILE}")" 2>/dev/null
echo "${WINNING_IP} ${WINNING_CN}" > "${PIA_SERVER_STATE_FILE}" \
    || log "WARN: failed to persist winning server to ${PIA_SERVER_STATE_FILE} (next run will re-shop the region)"

log "Registered successfully against ${WINNING_CN} / ${WINNING_IP}"

# ---------------------------------------------------------------------------
# Step 5: Clean up stale WireGuard peers
#
# `wg set ... peer <key> ...` only adds/updates a peer — it never removes
# old ones. Every past re-registration (including server rotations) left its
# previous peer entry live in the kernel. Remove anything that isn't the
# peer we just verified.
# ---------------------------------------------------------------------------

log "Cleaning up stale WireGuard peers"

while IFS= read -r stale_key; do
    [[ -n "${stale_key}" && "${stale_key}" != "${SERVER_KEY}" ]] || continue
    log "  Removing stale peer ${stale_key}"
    ssh -n "${PFSENSE_HOST}" "sudo wg set ${PFSENSE_WG_IFACE} peer '${stale_key}' remove" 2>/dev/null \
        || log "  WARN: failed to remove stale peer ${stale_key} (non-fatal)"
done < <(ssh -n "${PFSENSE_HOST}" "sudo wg show ${PFSENSE_WG_IFACE} peers" 2>/dev/null)

log "Stale peer cleanup complete"

# ---------------------------------------------------------------------------
# Step 6: Reload pfSense pf rules
#
# `wg set` and `ifconfig` update live kernel state but do NOT cause pfSense
# to regenerate its pf ruleset. Policy-based routing rules use `route-to
# (tun_wg0 <peer_ip>)` — if peer_ip changed, or if the rules were generated
# while the gateway was down (omitting route-to entirely), hosts in
# pia_redirect_group silently fall back to WAN despite the tunnel being up.
#
# filter_configure_sync reloads pf rules from config.xml without touching
# the WireGuard interface (no rc.newwanip, no kernel panic).
#
# We also flush states for pia_redirect_group so existing WAN-pinned
# connections immediately re-route through the tunnel on reconnect.
# ---------------------------------------------------------------------------

log "Reloading pfSense pf rules (filter_configure_sync)"

ssh "${PFSENSE_HOST}" "sudo /etc/rc.filter_configure_sync" \
    || log "WARN: filter_configure_sync failed — policy routing may be stale until next pfSense rule save"

log "Flushing pf states for pia_redirect_group"

# Flush states for each host in the alias so they re-route through PIA immediately.
# pfctl -k <addr> kills all states where addr is the source — brief TCP disruption
# is acceptable since connections will re-establish over the tunnel.
while IFS= read -r host; do
    [[ -n "${host}" ]] || continue
    log "  Flushing states for ${host}"
    ssh -n "${PFSENSE_HOST}" "sudo pfctl -k ${host}" 2>/dev/null \
        || log "  WARN: pfctl -k ${host} failed (non-fatal)"
done < <(ssh -n "${PFSENSE_HOST}" "sudo pfctl -t pia_redirect_group -T show" 2>/dev/null)

log "pf rules reloaded and states flushed"

# ---------------------------------------------------------------------------
# Step 7: Ping Uptime Kuma healthcheck
#
# The Uptime Kuma push monitor expects a heartbeat within its configured
# window (set to 26h to give the 2 AM cron a 2h grace period). A missing
# heartbeat means every candidate server failed and Kuma will alert.
# ---------------------------------------------------------------------------

log "Pinging Uptime Kuma healthcheck"

curl -fsS --max-time 10 "${UPTIME_KUMA_URL}" > /dev/null \
    || log "WARN: Uptime Kuma ping failed — tunnel is up but healthcheck not confirmed"

log "PIA WireGuard re-registration completed successfully"
