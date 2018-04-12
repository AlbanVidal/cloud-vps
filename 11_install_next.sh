#!/bin/bash

#
# BSD 3-Clause License
# 
# Copyright (c) 2018, Alban Vidal <alban.vidal@zordhak.fr>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

################################################################################
##########                    Define color to output:                 ########## 
################################################################################
_WHITE_="tput sgr0"
_RED_="tput setaf 1"
_GREEN_="tput setaf 2"
_ORANGE_="tput setaf 3"
################################################################################

# TODO
# - logrotate (all CT)
# - iptables isolateur: Deny !80 !443

# Load Vars
. 00_VARS

# Load Network Vars
. 01_NETWORK_VARS

# Load Resources Vars
. 02_RESOURCES_VARS

# Load Other vars 
# - DEBIAN_RELEASE
. 03_OTHER_VARS

################################################################################

# LXD INIT
echo "$($_ORANGE_)LXD initialization$($_WHITE_)"
cat << EOF | lxd init --preseed
# Daemon settings
config:
  images.auto_update_interval: 15

# Storage pools
storage_pools:
- name: default
  driver: btrfs

# Network devices
networks:
- name: lxdbrEXT
  type: bridge
  config:
    ipv4.address: $IP_LXD/$CIDR
    ipv4.nat: "true"
    ipv4.dhcp: "false"
    ipv6.address: none

- name: lxdbrINT
  type: bridge
  config:
    ipv4.address: none
    ipv4.nat: "false"
    ipv4.dhcp: "false"
    ipv6.address: none

# Profiles
profiles:

- name: default
  description: "Default Net and storage"
  devices:
    ethPublic:
      name: ethPublic
      nictype: bridged
      parent: lxdbrEXT
      type: nic
    root:
      path: /
      pool: default
      type: disk

- name: privNet
  description: "Internal (backend) Network"
  devices:
    ethPrivate:
      name: ethPrivate
      nictype: bridged
      parent: lxdbrINT
      type: nic

- name: cpu-1
  description: "1 CPU"
  config:
    limits.cpu: "1"

- name: cpu-2
  description: "2 CPU"
  config:
    limits.cpu: "2"

- name: cpu-4
  description: "4 CPU"
  config:
    limits.cpu: "4"

- name: ram-256
  description: "256MB RAM"
  config:
    limits.memory: 256MB

- name: ram-512
  description: "512MB RAM"
  config:
    limits.memory: 512MB

- name: ram-1024
  description: "1GB RAM"
  config:
    limits.memory: 1GB

- name: ram-2048
  description: "2GB RAM"
  config:
    limits.memory: 2GB

- name: ram-4096
  description: "4GB RAM"
  config:
    limits.memory: 4GB

EOF

# TEMPLATE interfaces containers
cat << EOF > /tmp/lxd_interfaces_TEMPLATE
auto lo
iface lo inet loopback

auto ethPublic
iface ethPublic inet static
    address _IP_PUB_/_CIDR_
    gateway $IP_LXD

auto ethPrivate
iface ethPrivate inet static
    address _IP_PRIV_/_CIDR_
EOF

# TEMPLATE resolv.conf (OpenDNS)
cat << EOF > /tmp/lxd_resolv.conf
nameserver 208.67.222.222
nameserver 208.67.220.220
EOF

# CT 1 - CLOUD
echo "$($_ORANGE_)LXD create container: cloud$($_WHITE_)"
lxc launch images:debian/$DEBIAN_RELEASE cloud --profile default --profile privNet
sed -e "s/_IP_PUB_/$IP_cloud/" -e "s/_IP_PRIV_/$IP_cloud_PRIV/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_cloud
lxc file push /tmp/lxd_interfaces_cloud cloud/etc/network/interfaces
lxc file push /tmp/lxd_resolv.conf cloud/etc/resolv.conf
lxc restart cloud

# CT 2 - COLLABORA
echo "$($_ORANGE_)LXD create container: collabora$($_WHITE_)"
lxc launch images:debian/$DEBIAN_RELEASE collabora --profile default --profile privNet
sed -e "s/_IP_PUB_/$IP_collabora/" -e "s/_IP_PRIV_/$IP_collabora_PRIV/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_collabora
lxc file push /tmp/lxd_interfaces_collabora collabora/etc/network/interfaces
lxc file push /tmp/lxd_resolv.conf collabora/etc/resolv.conf
lxc restart collabora

# CT 3 - MariaDB
echo "$($_ORANGE_)LXD create container: mariadb$($_WHITE_)"
lxc launch images:debian/$DEBIAN_RELEASE mariadb --profile default --profile privNet
sed -e "s/_IP_PUB_/$IP_mariadb/" -e "s/_IP_PRIV_/$IP_mariadb_PRIV/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_mariadb
lxc file push /tmp/lxd_interfaces_mariadb mariadb/etc/network/interfaces
lxc file push /tmp/lxd_resolv.conf mariadb/etc/resolv.conf
lxc restart mariadb

# CT 4 - RVPRX
echo "$($_ORANGE_)LXD create container: rvprx$($_WHITE_)"
lxc launch images:debian/$DEBIAN_RELEASE rvprx --profile default --profile privNet
sed -e "s/_IP_PUB_/$IP_rvprx/" -e "s/_IP_PRIV_/$IP_rvprx_PRIV/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_rvprx
lxc file push /tmp/lxd_interfaces_rvprx rvprx/etc/network/interfaces
lxc file push /tmp/lxd_resolv.conf rvprx/etc/resolv.conf
lxc restart rvprx

# CT 5 - SMTP
echo "$($_ORANGE_)LXD create container: smtp$($_WHITE_)"
lxc launch images:debian/$DEBIAN_RELEASE smtp --profile default --profile privNet
sed -e "s/_IP_PUB_/$IP_smtp/" -e "s/_IP_PRIV_/$IP_smtp_PRIV/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_smtp
lxc file push /tmp/lxd_interfaces_smtp smtp/etc/network/interfaces
lxc file push /tmp/lxd_resolv.conf smtp/etc/resolv.conf
lxc restart smtp

echo "$($_GREEN_)Waiting all containers correctly started (networking...) 5 seconds$($_WHITE_)"
sleep 5

################################################################################
#### Common containers configuration

echo ""
echo "$($_GREEN_)Common containers configuration$($_WHITE_)"
echo "$($_ORANGE_)Update, upgrade and install common packages$($_WHITE_)"

CT_LIST="smtp rvprx mariadb cloud collabora"

PACKAGES="vim apt-utils bsd-mailx unattended-upgrades apt-listchanges logrotate"

# Configure all container
for CT in $CT_LIST ; do
    echo "$($_ORANGE_)${CT}...$($_WHITE_)"

    if [ "$DEBIAN_RELEASE" == "stretch" ] ; then
        lxc exec $CT -- bash -c "echo 'deb http://ftp.fr.debian.org/debian stretch-backports main' > /etc/apt/sources.list.d/stretch-backports.list"
    fi

    lxc exec $CT -- bash -c "
        apt-get update > /dev/null
        DEBIAN_FRONTEND=noninteractive apt-get -y install $PACKAGES > /dev/null
        DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null
        sed -i \
            -e 's#^//Unattended-Upgrade::Mail .*#Unattended-Upgrade::Mail \"$TECH_ADMIN_EMAIL\";#' \
            -e 's#^//Unattended-Upgrade::MailOnlyOnError .*#Unattended-Upgrade::MailOnlyOnError \"true\";#' \
            /etc/apt/apt.conf.d/50unattended-upgrades
        systemctl stop exim4
        systemctl disable exim4
    "
done

################################################################################
#### CONTAINER CONFIGURATION
echo ""
echo "$($_GREEN_)CONTAINER CONFIGURATION$($_WHITE_)"
echo ""

############################################################
#### SMTP
./21_configure_smtp.sh

############################################################
#### RVPRX
./22_configure_rvprx.sh

############################################################
#### MariaDB

# Generate nextcloud database password
MDP_nextcoud=$(openssl rand -base64 32)
echo "$MDP_nextcoud" > /tmp/lxc_nextcloud_password

./23_configure_mariadb.sh

############################################################
#### CLOUD
./24_configure_cloud.sh

# Delete nextcloud database password
rm -f /tmp/lxc_nextcloud_password

############################################################
#### COLLABORA
./25_configure_collabora.sh

################################################################################
