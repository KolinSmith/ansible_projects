#!/bin/bash

# check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# update software
echo "===== Updating software"
apt update -y
apt upgrade -y
apt dist-upgrade -y
apt autoclean -y
apt autoremove -y

########################################
# left this out since the repository doesn't have an arm image (need to test if arm)
########################################
# add official Tor repository
# apt-get install -y deb.torproject.org-keyring
# if ! grep -q "https://deb.torproject.org/torproject.org" /etc/apt/sources.list; then
#     echo "===== Adding the official Tor repository"
#     echo "deb https://deb.torproject.org/torproject.org/dists/ `lsb_release -cs` main" >> /etc/apt/sources.list
#     gpg --keyserver keys.gnupg.net --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
#     gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -
#     apt-get update
# fi
########################################

#another way to add the key
#wget -q https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc -O- | sudo apt-key add -

# install tor and related packages
echo "===== Installing Tor and related packages"
#apt-key adv --recv-keys --keyserver keys.gnupg.net 74A941BA219EC810
curl -sSL https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --import -
apt install -y tor tor-arm tor-geoipdb bc
service tor stop

#prompt user for tor node name
read -p "===== Enter in a name for the tor node (this name will be publicly visible): " tor_node_name
tor_node_name=${tor_node_name:-"ididntchangethename"}

########################################
# another way I tried initially
########################################
# mapfile -t speeds < <(
#     curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py |
#     python - |
#     grep -oP '(Up|Down)load: \K[\d.]+'
# )
# upload_speed_max=${speed[1]}
# upload_speed=${speeds[1] / 12}
# download_speed=${speeds[1] / 10}
########################################

#check for python before running

#run speedtest and pull the speed values from it to use in torrc
echo "===== Beginning speedtest"
result=$(curl https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python -)
if [[ $result =~ 'Download: '([[:digit:].]+)' Mbit' ]]; then
    actual_download_speed=${BASH_REMATCH[1]}
fi
if [[ $result =~ 'Upload: '([[:digit:].]+)' Mbit' ]]; then
    actual_upload_speed=${BASH_REMATCH[1]}
fi

echo "===== Setting the variables"
upload_speed=$(echo "scale=0;$actual_upload_speed/10" | bc)
if
   [[ "$upload_speed" == 0 ]]; then
     upload_speed=1
fi
download_speed=$(( upload_speed + 1 ))

#prompt user for tor node ports
read -p "===== ControlPort Number [9051]: " control_port
control_port=${control_port:-9051}

read -p "===== ORPort Number [8443]: " orport
orport=${orport:-8443}

read -p "===== DirPort Number [8444]: " dirport
dirport=${dirport:-8444}

#create torrc file
echo '===== Creating torrc file'
cat <<EOF >/etc/tor/torrc
## Configuration file for a typical Tor user
## Last updated 28 February 2019 for Tor 0.3.5.1-alpha.
## (may or may not work for much older or much newer versions of Tor.)
##
## Lines that begin with "## " try to explain what's going on. Lines
## that begin with just "#" are disabled commands: you can enable them
## by removing the "#" symbol.
##
## See 'man tor', or https://www.torproject.org/docs/tor-manual.html,
## for more options you can use in this file.
##
## Tor will look for this file in various places based on your platform:
## https://www.torproject.org/docs/faq#torrc

## Tor opens a SOCKS proxy on port 9050 by default -- even if you don't
## configure one below. Set "SOCKSPort 0" if you plan to run Tor only
## as a relay, and not make any local application connections yourself.
SOCKSPort 0 # Default: Bind to localhost:9050 for local connections.
#SOCKSPort 192.168.0.1:9100 # Bind to this address:port too.

## Entry policies to allow/deny SOCKS requests based on IP address.
## First entry that matches wins. If no SOCKSPolicy is set, we accept
## all (and only) requests that reach a SOCKSPort. Untrusted users who
## can access your SOCKSPort may be able to learn about the connections
## you make.
#SOCKSPolicy accept 192.168.0.0/16
#SOCKSPolicy accept6 FC00::/7
SOCKSPolicy reject *

## Logs go to stdout at level "notice" unless redirected by something
## else, like one of the below lines. You can have as many Log lines as
## you want.
##
## We advise using "notice" in most cases, since anything more verbose
## may provide sensitive information to an attacker who obtains the logs.
##
## Send all messages of level 'notice' or higher to @LOCALSTATEDIR@/log/tor/notices.log
Log notice file /var/log/tor/notices.log
## Send every possible message to @LOCALSTATEDIR@/log/tor/debug.log
#Log debug file @LOCALSTATEDIR@/log/tor/debug.log
## Use the system log instead of Tor's logfiles
#Log notice syslog
## To send all messages to stderr:
#Log debug stderr

## Uncomment this to start the process in the background... or use
## --runasdaemon 1 on the command line. This is ignored on Windows;
## see the FAQ entry if you want Tor to run as an NT service.
RunAsDaemon 1

## The directory for keeping all the keys/etc. By default, we store
## things in $HOME/.tor on Unix, and in Application Data\tor on Windows.
DataDirectory /var/lib/tor

## The port on which Tor will listen for local connections from Tor
## controller applications, as documented in control-spec.txt.
ControlPort $control_port
## If you enable the controlport, be sure to enable one of these
## authentication methods, to prevent attackers from accessing it.
#HashedControlPassword 16:872860B76453A77D60CA2BB8C1A7042072093276A3D701AD684053EC4C
CookieAuthentication 1

############### This section is just for location-hidden services ###

## Once you have configured a hidden service, you can look at the
## contents of the file ".../hidden_service/hostname" for the address
## to tell people.
##
## HiddenServicePort x y:z says to redirect requests on port x to the
## address y:z.

#HiddenServiceDir @LOCALSTATEDIR@/lib/tor/hidden_service/
#HiddenServicePort 80 127.0.0.1:80

#HiddenServiceDir @LOCALSTATEDIR@/lib/tor/other_hidden_service/
#HiddenServicePort 80 127.0.0.1:80
#HiddenServicePort 22 127.0.0.1:22

################ This section is just for relays #####################
#
## See https://www.torproject.org/docs/tor-doc-relay for details.

## Required: what port to advertise for incoming Tor connections.
ORPort $orport
## If you want to listen on a port other than the one advertised in
## ORPort (e.g. to advertise 443 but bind to 9090), you can do it as
## follows.  You'll need to do ipchains or other port forwarding
## yourself to make this work.
#ORPort 443 NoListen
#ORPort 127.0.0.1:9090 NoAdvertise
## If you want to listen on IPv6 your numeric address must be explictly
## between square brackets as follows. You must also listen on IPv4.
#ORPort [2001:DB8::1]:9050

## The IP address or full DNS name for incoming connections to your
## relay. Leave commented out and Tor will guess.
#Address noname.example.com

## If you have multiple network interfaces, you can specify one for
## outgoing traffic to use.
## OutboundBindAddressExit will be used for all exit traffic, while
## OutboundBindAddressOR will be used for all OR and Dir connections
## (DNS connections ignore OutboundBindAddress).
## If you do not wish to differentiate, use OutboundBindAddress to
## specify the same address for both in a single line.
#OutboundBindAddressExit 10.0.0.4
#OutboundBindAddressOR 10.0.0.5

## A handle for your relay, so people don't have to refer to it by key.
## Nicknames must be between 1 and 19 characters inclusive, and must
## contain only the characters [a-zA-Z0-9].
## If not set, "Unnamed" will be used.
Nickname $tor_node_name

## Define these to limit how much relayed traffic you will allow. Your
## own traffic is still unthrottled. Note that RelayBandwidthRate must
## be at least 75 kilobytes per second.
## Note that units for these config options are bytes (per second), not
## bits (per second), and that prefixes are binary prefixes, i.e. 2^10,
## 2^20, etc.
RelayBandwidthRate $upload_speed MBytes
RelayBandwidthBurst $download_speed MBytes
## Use these to restrict the maximum traffic per day, week, or month.
## Note that this threshold applies separately to sent and received bytes,
## not to their sum: setting "40 GB" may allow up to 80 GB total before
## hibernating.
##
## Set a maximum of 40 gigabytes each way per period.
#AccountingMax 40 GBytes
## Each period starts daily at midnight (AccountingMax is per day)
#AccountingStart day 00:00
## Each period starts on the 3rd of the month at 15:00 (AccountingMax
## is per month)
#AccountingStart month 3 15:00

## Administrative contact information for this relay or bridge. This line
## can be used to contact you if your relay or bridge is misconfigured or
## something else goes wrong. Note that we archive and publish all
## descriptors containing these lines and that Google indexes them, so
## spammers might also collect them. You may want to obscure the fact that
## it's an email address and/or generate a new address for this purpose.
##
## If you are running multiple relays, you MUST set this option.
##
#ContactInfo Random Person <nobody AT example dot com>
## You might also include your PGP or GPG fingerprint if you have one:
#ContactInfo 0xFFFFFFFF Random Person <nobody AT example dot com>

## Uncomment this to mirror directory information for others. Please do
## if you have enough bandwidth.
DirPort $dirport # what port to advertise for directory connections
## If you want to listen on a port other than the one advertised in
## DirPort (e.g. to advertise 80 but bind to 9091), you can do it as
## follows.  below too. You'll need to do ipchains or other port
## forwarding yourself to make this work.
#DirPort 80 NoListen
#DirPort 127.0.0.1:9091 NoAdvertise
## Uncomment to return an arbitrary blob of html on your DirPort. Now you
## can explain what Tor is if anybody wonders why your IP address is
## contacting them. See contrib/tor-exit-notice.html in Tor's source
## distribution for a sample.
#DirPortFrontPage @CONFDIR@/tor-exit-notice.html

## Uncomment this if you run more than one Tor relay, and add the identity
## key fingerprint of each Tor relay you control, even if they're on
## different networks. You declare it here so Tor clients can avoid
## using more than one of your relays in a single circuit. See
## https://www.torproject.org/docs/faq#MultipleRelays
## However, you should never include a bridge's fingerprint here, as it would
## break its concealability and potentially reveal its IP/TCP address.
##
## If you are running multiple relays, you MUST set this option.
##
## Note: do not use MyFamily on bridge relays.
#MyFamily $keyid,$keyid,...

## Uncomment this if you want your relay to be an exit, with the default
## exit policy (or whatever exit policy you set below).
## (If ReducedExitPolicy, ExitPolicy, or IPv6Exit are set, relays are exits.
## If none of these options are set, relays are non-exits.)
#ExitRelay 1

## Uncomment this if you want your relay to allow IPv6 exit traffic.
## (Relays do not allow any exit traffic by default.)
#IPv6Exit 1

## Uncomment this if you want your relay to be an exit, with a reduced set
## of exit ports.
#ReducedExitPolicy 1

## Uncomment these lines if you want your relay to be an exit, with the
## specified set of exit IPs and ports.
##
## A comma-separated list of exit policies. They're considered first
## to last, and the first match wins.
##
## If you want to allow the same ports on IPv4 and IPv6, write your rules
## using accept/reject *. If you want to allow different ports on IPv4 and
## IPv6, write your IPv6 rules using accept6/reject6 *6, and your IPv4 rules
## using accept/reject *4.
##
## If you want to _replace_ the default exit policy, end this with either a
## reject *:* or an accept *:*. Otherwise, you're _augmenting_ (prepending to)
## the default exit policy. Leave commented to just use the default, which is
## described in the man page or at
## https://www.torproject.org/documentation.html
##
## Look at https://www.torproject.org/faq-abuse.html#TypicalAbuses
## for issues you might encounter if you use the default exit policy.
##
## If certain IPs and ports are blocked externally, e.g. by your firewall,
## you should update your exit policy to reflect this -- otherwise Tor
## users will be told that those destinations are down.
##
## For security, by default Tor rejects connections to private (local)
## networks, including to the configured primary public IPv4 and IPv6 addresses,
## and any public IPv4 and IPv6 addresses on any interface on the relay.
## See the man page entry for ExitPolicyRejectPrivate if you want to allow
## "exit enclaving".
##
#ExitPolicy accept *:6660-6667,reject *:* # allow irc ports on IPv4 and IPv6 but no more
#ExitPolicy accept *:119 # accept nntp ports on IPv4 and IPv6 as well as default exit policy
#ExitPolicy accept *4:119 # accept nntp ports on IPv4 only as well as default exit policy
#ExitPolicy accept6 *6:119 # accept nntp ports on IPv6 only as well as default exit policy
ExitPolicy reject *:* # no exits allowed

## Bridge relays (or "bridges") are Tor relays that aren't listed in the
## main directory. Since there is no complete public list of them, even an
## ISP that filters connections to all the known Tor relays probably
## won't be able to block all the bridges. Also, websites won't treat you
## differently because they won't know you're running Tor. If you can
## be a real relay, please do; but if not, be a bridge!
##
## Warning: when running your Tor as a bridge, make sure than MyFamily is
## NOT configured.
#BridgeRelay 1
## By default, Tor will advertise your bridge to users through various
## mechanisms like https://bridges.torproject.org/. If you want to run
## a private bridge, for example because you'll give out your bridge
## address manually to your friends, uncomment this line:
#PublishServerDescriptor 0

## Configuration options can be imported from files or folders using the %include
## option with the value being a path. This path can have wildcards. Wildcards are
## expanded first, using lexical order. Then, for each matching file or folder, the following
## rules are followed: if the path is a file, the options from the file will be parsed as if
## they were written where the %include option is. If the path is a folder, all files on that
## folder will be parsed following lexical order. Files starting with a dot are ignored. Files
## on subfolders are ignored.
## The %include option can be used recursively.
#%include /etc/torrc.d/*.conf
EOF
############################################################################################################

# configure automatic updates
echo "===== Configuring unattended upgrades"
apt install -y unattended-upgrades apt-listchanges
# cp $PWD/etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades

# attempt to forward tor ports on user's router
# decent explanation of upnpc: https://po-ru.com/2013/02/17/using-upnp-igd-for-simpler-port-forwarding
echo "===== Configuring port forwarding"
apt install -y miniupnpc
cat <<EOF >/usr/local/bin/update-upnp-forwards
#!/bin/bash
root_description_url=$(upnpc -l | grep desc: | cut -c8-)
upnpc -u $root_description_url -e 'Forward OrPort'  -r $orport TCP >/dev/null
upnpc -u $root_description_url -e 'Forward DirPort' -r $dirport TCP >/dev/null
EOF
chmod a+x /usr/local/bin/update-upnp-forwards

local_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')

echo "========================================="
echo "===== You should make ensure the following ports are forwarded from your router:"
echo "===== Control Port: " $control_port
echo "===== ORPort: " $orport
echo "===== DirPort: " $dirport
echo "===== IP address to forward to: " $local_ip

cat <<EOF >/etc/systemd/system/upnp-forward-ports.service
[Unit]
Description=Update UPnP forward leases

[Service]
Type=simple
ExecStart=/usr/local/bin/update-upnp-forwards

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/upnp-forward-ports.timer
[Unit]
Description=Update UPnP forward leases every 30 minutes

[Timer]
Unit=upnp-forward-ports.service
OnBootSec=0min
OnUnitActiveSec=30min

[Install]
WantedBy=timers.target
EOF

shopt -s expand_aliases
#check what shell environment they are using
if [ ! -z ${ZSH_VERSION+x} ]; then
  echo "alias status='sudo -u debian-tor nyx'" > ~/.zshrc
  source ~/.zshrc
elif [ ! -z ${BASH_VERSION+x} ]; then
  echo "alias status='sudo -u debian-tor nyx'" > ~/.bashrc
  source ~/.bashrc
else
  echo "===== Could not detect shell..."
fi


systemctl daemon-reload
systemctl enable upnp-forward-ports.timer
systemctl start tor

# final instructions
echo "========================================="
echo "===== Run 'status' to get tor node stats"
echo "========================================="
echo "========== REBOOT THIS SERVER============"
echo "========================================="
