#!/bin/sh

# noip-dual-update.sh
# Updates both IPv4 (A) and IPv6 (AAAA) for a No-IP hostname

# ----------------------------
# Configuration
# ----------------------------
#
PATH=/sbin:/bin:/usr/sbin:/usr/bin

USERNAME="<MY_VERY_COOL_NOIP_USERNAME>"
PASSWORD="<MY_VERY_COOL_NOIP_PASSWORD>"
HOSTNAME="<MY_VERY_COOL_HOSTNAME>"
IFACE="wlan0"     # Interface for IPv6 (usually your main network interface, if using cable ethernet this would probably eth0, check with ip a command)
LOGFILE="<MY_VERY_COOL_LOGFILE_LOCATION>.log"

# ----------------------------
# Detect current public IPv4
# ----------------------------
# Uses a simple external service to get the IPv4
IPV4=$(curl -s https://api.ipify.org)

# ----------------------------
# Detect current global IPv6
# ----------------------------
IPV6=$(ip -6 addr show $IFACE | grep 'scope global' | awk '{print $2}' | cut -d/ -f1)

# ----------------------------
# Update IPv4 (A record)
# ----------------------------
if [ -n "$IPV4" ]; then
    RESPONSE_V4=$(curl -s -u "$USERNAME:$PASSWORD" \
        "https://dynupdate.no-ip.com/nic/update?hostname=$HOSTNAME&myip=$IPV4")
else
    RESPONSE_V4="No IPv4 detected"
fi

# ----------------------------
# Update IPv6 (AAAA record)
# ----------------------------
if [ -n "$IPV6" ]; then
    RESPONSE_V6=$(curl -s -u "$USERNAME:$PASSWORD" \
        "https://dynupdate.no-ip.com/nic/update?hostname=$HOSTNAME&myipv6=$IPV6")
else
    RESPONSE_V6="No IPv6 detected"
fi

# ----------------------------
# Log results
# ----------------------------
echo "[$(date +'%Y-%m-%d %H:%M:%S')] IPv4=$IPV4, IPv6=$IPV6" >> $LOGFILE
echo "[$(date +'%Y-%m-%d %H:%M:%S')] IPv4 update response: $RESPONSE_V4" >> $LOGFILE
echo "[$(date +'%Y-%m-%d %H:%M:%S')] IPv6 update response: $RESPONSE_V6" >> $LOGFILE
echo "--------------------------------------------------" >> $LOGFILE

