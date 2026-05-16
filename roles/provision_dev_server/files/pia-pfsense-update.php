<?php
// Usage: php pia-pfsense-update.php <server_key> <peer_ip>
if ($argc < 3) {
    fwrite(STDERR, "Usage: php pia-pfsense-update.php <server_key> <peer_ip>\n");
    exit(1);
}

require_once('/etc/inc/config.inc');
require_once('/etc/inc/interfaces.inc');
require_once('/etc/inc/util.inc');

global $config;

$new_server_key = $argv[1];
$new_peer_ip    = $argv[2];

// Update WireGuard peer public key (find by endpoint IP)
$peers = &$config['installedpackages']['wireguard']['peers']['item'];
$updated_peer = false;
foreach ($peers as $i => &$peer) {
    if (strpos($peer['endpoint'], '151.240.66.252') !== false) {
        echo "peer[$i] key: {$peer['publickey']} -> $new_server_key\n";
        $peer['publickey'] = $new_server_key;
        $updated_peer = true;
        break;
    }
}
if (!$updated_peer) {
    fwrite(STDERR, "ERROR: peer with endpoint 151.240.66.252 not found\n");
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
