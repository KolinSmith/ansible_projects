#!/bin/bash

# Stop services
systemctl stop tor
systemctl stop upnp-forward-ports.timer
systemctl stop upnp-forward-ports.service

# Remove packages
apt remove --purge -y tor tor-arm tor-geoipdb
apt autoremove -y

# Remove configurations
rm -rf /var/lib/tor
rm -rf /var/log/tor
rm -rf /usr/local/etc/tor
rm -f /etc/security/limits.d/debian-tor.conf
rm -rf /etc/systemd/system/tor.service.d
rm -f /etc/systemd/system/upnp-forward-ports.*
rm -f /usr/local/bin/update-upnp-forwards

# Remove aliases
sed -i '/alias status/d' ~/.bashrc
sed -i '/alias status/d' ~/.zshrc

systemctl daemon-reload

# Optional: Remove debian-tor user
deluser debian-tor
