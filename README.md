# Intro
My personal project to create a secure chat platform with encription, server blindness and fully open source toolchain.  

# Features
 - No Logins, security is based on private public key pairing
 - Based on wireguard (open source VPN)
 - Runs on barebones linux
 - Compatible with RISCV arch
   
# Pre-requisites
 - Ubuntu computer with docker and wireguard installed
 - Something that can run linux and have internet support to be the server
   
# Server
 - Riscv server hardware that I used [RV Nano](https://wiki.sipeed.com/hardware/en/lichee/RV_Nano/1_intro.html).
## Building the Linux Kernel for The RV Nano
 - Using sipeed documentation, I built my own linux kernel (This was done on a Ubunutu machine):
 
```
git clone https://github.com/sipeed/LicheeRV-Nano-Build --depth=1
cd LicheeRV-Nano-Build
git clone https://github.com/sophgo/host-tools --depth=1

sudo docker build -t licheervnano-build-ubuntu .

cd ~/LicheeRV-Nano-Build
~/LicheeRV-Nano-Build$ sudo docker run -it --rm -v $PWD:/licheervnano licheervnano-build-ubuntu bash
```
 - Inside Docker container (root@3edf6927d036:/#):
 
```
cd /licheervnano
source build/cvisetup.sh
```

Now edit this file:

```
vim /licheervnano/build/boards/sg200x/sg2002_licheervnano_sd/sg2002_licheervnano_sd_defconfig
```
Add these Flags to end of file:
```
CONFIG_INET=y
CONFIG_IPV6=y
CONFIG_IP6_NF_IPTABLES=y
CONFIG_IPV6_ROUTER_PREF=y
CONFIG_IPV6_OPTIMISTIC_DAD=y
CONFIG_WIREGUARD=y
CONFIG_WIREGUARD_DEBUG=y
```

Also edit this file:
```
vim /licheervnano/build/.defconfig
```

Add these Flags to end of file:
```
CONFIG_INET=y
CONFIG_IPV6=y
CONFIG_IP6_NF_IPTABLES=y
CONFIG_IPV6_ROUTER_PREF=y
CONFIG_IPV6_OPTIMISTIC_DAD=y
CONFIG_WIREGUARD=y
CONFIG_WIREGUARD_DEBUG=y
```


Change rootfs partition size to be able to build:

```
vim build/boards/sg200x/sg2002_licheervnano_sd/partition/partition_sd.xml
```

Add 10M to rootfs or something, it should be enough

Trust the git file (to avoid failing build script):

```
git config --global --add safe.directory /licheervnano
```

Build now:

```
build_all
```

Export from Docker:

```
sudo docker cp 6e947b1fa42a:/licheervnano/install/soc_sg2002_licheervnano_sd/images/2026-02-23-20-05-d4003f.img ~/
```

Connect an sd card to your computer. Find where it is mounted on your machine (mine is mounted on /dev/sdc)

Sending linux image to sd card:

```
sudo dd if=2026-02-23-20-05-d4003f.img of=/dev/sdc bs=4M conv=fsync status=progress

sync
```


Edit the wifi configuration file on your mounted sd card folder to inlcude your home network (will be used for ssh to server):

```
vim /mnt/rootfs/etc/wpa_supplicant.conf
```

Should look something like this:

```
# cat /etc/wpa_supplicant.conf 
ctrl_interface=/var/run/wpa_supplicant
ap_scan=1

network={
  ssid="MY_VERY_COOL_SSID"
  psk="MY_VERY_COOL_WIFI_PASSWORD"
  key_mgmt=WPA-PSK
}
```

Run sync:

```
sync
```

Now unmount and eject the sd card.

Connect the sd card back into Lichee

Turn Lichee on

On your ubuntu computer run the default SSH for LICHEE RV (PASSWORD IS ROOT):

```
ssh root@192.168.15.19
root
```

It should connect to board, now we can prepare the DNS (needed for static IP).

## DNS Config

- For my project, I used [https://www.noip.com/](https://www.noip.com/) to create my DNS domain (its free and can be created with fake personal data). Only issue with this service is that you need to login into the noip website to confirm that your domain is still active every 30 days.
- Now that you have the DNS we need to change some files in the server to ensure automatic DNS update and static lichee ip.
- First we need to ensure that your router is ready to recieve an send udp data aswell as respect the lichee ip.
- Login into your router via your ubuntu internet browser (every router is different) and do these steps:
    - Reduce DHCP ip range to be ouside of the intended static ip (I am using 192.168.15.19 as the static ip for the board so I reduced my DHCP range to from 192.168.15.30 to  192.168.15.200)
	- Create a port fowarding rule for your wireguard (which is udp based):
        - Protocol: UDP; External Ports: 51820 (could be any port compatible with wireguard, I just chose this one); Internal Ports: 51820; External IP: leave empty; Internal IP: 192.168.15.19 (lichee static ip I used)
    - Create a firewall rule to allow traffic trought this port:
        - Protocol: UDP; Local Ports: 51820; Remote Ports: 51820; Remote IP: *; Local IP: 192.168.15.19
    - (optional): Enable a DMZ zone on the lichee static ip (192.168.15.19) if your router has that




- Now we need to setup board real time clock, static ip and automatically update the dns IP.
- While ssh to the server, edit this boot file:
```
vim /etc/init.d/S99local
```
- To force the fixed IP, and setup the real time clock during boot replace the file contents with:
```
#!/bin/sh

if [ "${1}" = "start" ]
then
	if [ ! -e /boot/rclocal.disable ]
	then
		sh /etc/rc.local &
	fi
fi

[ ! -s /tmp/resolv.conf ] && echo nameserver 8.8.8.8 > /tmp/resolv.conf

# --- force static IP (added manually) ---
IFACE=wlan0
IP=192.168.15.19
NETMASK=255.255.255.0
GW=192.168.15.1

# stop DHCP if running
killall udhcpc 2>/dev/null

# bring interface up with fixed IP
ifconfig $IFACE $IP netmask $NETMASK up

# ensure correct default route
route del default 2>/dev/null
route add default gw $GW

killall ntpd 2>/dev/null
sleep 1

for i in $(seq 1 30); do
	ping -c1 -W1 8.8.8.8 >/dev/null 2>&1 && break
	sleep 1
done

ntpd -gq -p pool.ntp.org

ntpd -p pool.ntp.org &

```
Make the file executable
```
chmod +x /etc/init.d/S99local
```



- Create a new file to update the DNS:

```
cd /usr/bin/
touch  noip-dual-update.sh
vim /usr/bin/noip-dual-update.sh
```
- Copy this to the noip-dual-update.sh file:

```
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
```
- Edit these variables according to your account and log storage preference:
  
```
USERNAME="<MY_VERY_COOL_NOIP_USERNAME>"
PASSWORD="<MY_VERY_COOL_NOIP_PASSWORD>"
HOSTNAME="<MY_VERY_COOL_HOSTNAME>"
IFACE="wlan0"     # Interface for IPv6 (usually your main network interface, if using cable ethernet this would probably eth0, check with ip a command)
LOGFILE="<MY_VERY_COOL_LOGFILE_LOCATION>.log"
```

Make the file executable
```
chmod +x noip-dual-update.sh
```
- Now to create the boot script for the DNS:

```
vim /etc/init.d/S99local
```
Replace the file contents with:
```
#!/bin/sh

PATH=/sbin:/bin:/usr/sbin:/usr/bin
PIDFILE=/var/run/noip-dual-update.pid
INTERVAL=600   # seconds (600 = 10 minutes)

start() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "noip-dual-update already running"
        return
    fi

    (
        echo $$ > "$PIDFILE"

        # wait a bit after boot
        sleep 30

        while true; do
            /usr/bin/noip-dual-update.sh >/dev/null 2>&1
            sleep "$INTERVAL"
        done
    ) &
}

stop() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
    fi
}

case "$1" in
    start)
        start
        ;;#!/bin/sh

PATH=/sbin:/bin:/usr/sbin:/usr/bin
PIDFILE=/var/run/noip-dual-update.pid
INTERVAL=600   # seconds (600 = 10 minutes)

start() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "noip-dual-update already running"
        return
    fi

    (
        echo $$ > "$PIDFILE"

        # wait a bit after boot
        sleep 30

        while true; do
            /usr/bin/noip-dual-update.sh >/dev/null 2>&1
            sleep "$INTERVAL"
        done
    ) &
}

stop() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 2
        start
        ;;
esac

exit 0

    stop)
        stop
        ;;
    restart)
        stop
        sleep 2
        start
        ;;
esac

exit 0
```
Make the file executable
```
chmod +x /etc/init.d/S99local
```
Reboot the board and check the logs from noip-dual-update.sh to see if everithing is working (<MY_VERY_COOL_LOGFILE_LOCATION>.log that was defined set in previous steps).

## Wireguard Server Setup

