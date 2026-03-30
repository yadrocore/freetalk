# Intro
My personal project to  attemp to create a secure chat platform with encription, server blindness and fully open source toolchain.  

# Features
 - No Logins, security is based on private public key pairing
 - Based on wireguard (open source VPN)
 - Runs on barebones linux
 - Compatible with RISCV arch

# Server
 - This is the riscv server hardware that I used [RV Nano](https://wiki.sipeed.com/hardware/en/lichee/RV_Nano/1_intro.html)
 
## Building the Linux Kernel for The RV Nano
 - Based on sipeed documentation to build the linux kernel (This was done on Ubunutu):
 
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
- Login into your router via your ubuntu internet browser (every router is different) 

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



