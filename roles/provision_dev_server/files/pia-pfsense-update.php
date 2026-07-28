<?php
// Usage: php pia-pfsense-update.php <server_key> <peer_ip> <endpoint_ip> <endpoint_port>
if ($argc < 5) {
    fwrite(STDERR, "Usage: php pia-pfsense-update.php <server_key> <peer_ip> <endpoint_ip> <endpoint_port>\n");
    exit(1);
}

require_once('/etc/inc/config.inc');
require_once('/etc/inc/interfaces.inc');
require_once('/etc/inc/util.inc');

global $config;

$new_server_key    = $argv[1];
$new_peer_ip        = $argv[2];
$new_endpoint_ip    = $argv[3];
$new_endpoint_port  = $argv[4];

// Update the WireGuard peer (matched by description, not endpoint — the PIA
// tunnel is the only peer with this description. Matching by endpoint IP
// broke silently for months: it never updated the endpoint field, so
// config.xml kept pointing at whatever server was configured the very first
// time, even as `wg set` kept the live kernel state current. A pfSense
// reboot would have reloaded config.xml and dialed that stale server.)
$peers = &$config['installedpackages']['wireguard']['peers']['item'];
$updated_peer = false;
foreach ($peers as $i => &$peer) {
    if (stripos($peer['descr'], 'PIA') !== false) {
        echo "peer[$i] key: {$peer['publickey']} -> $new_server_key\n";
        echo "peer[$i] endpoint: {$peer['endpoint']}:{$peer['port']} -> {$new_endpoint_ip}:{$new_endpoint_port}\n";
        $peer['publickey'] = $new_server_key;
        $peer['endpoint']  = $new_endpoint_ip;
        $peer['port']      = $new_endpoint_port;
        $updated_peer = true;
        break;
    }
}
if (!$updated_peer) {
    fwrite(STDERR, "ERROR: WireGuard peer with descr containing 'PIA' not found\n");
    exit(1);
}

// Update interface IP (opt6 / tun_wg0)
$updated_iface = false;
if (isset($config['interfaces']['opt6'])) {
    echo "opt6 ipaddr: {$config['interfaces']['opt6']['ipaddr']} -> $new_peer_ip\n";
    $config['interfaces']['opt6']['ipaddr'] = $new_peer_ip;
    $updated_iface = true;
}
if (!$updated_iface) {
    fwrite(STDERR, "ERROR: opt6 interface not found in config\n");
    exit(1);
}

// Update gateway
$updated_gw = false;
foreach ($config['gateways']['gateway_item'] as $i => &$gw) {
    if ($gw['name'] === 'PIA_OVER_WIREGUARD') {
        echo "gateway: {$gw['gateway']} -> $new_peer_ip\n";
        $gw['gateway'] = $new_peer_ip;
        $updated_gw = true;
        break;
    }
}
if (!$updated_gw) {
    fwrite(STDERR, "ERROR: PIA_OVER_WIREGUARD gateway not found\n");
    exit(1);
}

// Suppress backup_config() failure (backup dir may not be writable)
// write_config() itself still succeeds and persists config.xml
@write_config('PIA WireGuard re-registration');
echo "config written\n";
