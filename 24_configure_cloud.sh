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

################################################################################

#### CLOUD

# Test if Nextcloud database password is set
if [ ! -f /tmp/lxc_nextcloud_password ] ; then
    echo "$($_RED_)You need to create « /tmp/lxc_nextcloud_password » with nextcloud user passord$($_WHITE_)"
    exit 1
fi
MDP_nextcoud="$(cat /tmp/lxc_nextcloud_password)"

echo "$($_GREEN_)BEGIN cloud$($_WHITE_)"
echo "$($_ORANGE_)Update, upgrade and packages$($_WHITE_)"
lxc exec cloud -- apt-get update > /dev/null
lxc exec cloud -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null"
lxc exec cloud -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install vim apt-utils > /dev/null"
 
echo "$($_ORANGE_)Create « occ » alias command$($_WHITE_)"
lxc exec cloud -- bash -c 'echo "sudo -u www-data php /var/www/nextcloud/occ $@" > /usr/local/bin/occ'

echo -n "$($_GREEN_)Please enter a password for nextcloud admin « admincloud » : $($_WHITE_)"
read -rs MDP_admincloud

echo "$($_ORANGE_)Install packages for nextcloud...$($_WHITE_)"
lxc exec cloud -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install \
    wget            \
    curl            \
    sudo            \
    apache2         \
    mariadb-client  \
    redis-server    \
    php7.0 php7.0-fpm php7.0-simplexml php-mysql php-gd php-zip php-mbstring php-curl php-redis php7.0-bz2 php7.0-intl php7.0-mcrypt php7.0-gmp \
    > /dev/null"

echo "$($_ORANGE_)Enable php7-fpm in apache2$($_WHITE_)"
lxc exec cloud -- bash -c "a2enmod proxy_fcgi setenvif > /dev/null"
lxc exec cloud -- bash -c "a2enconf php7.0-fpm > /dev/null"

echo "$($_ORANGE_)Enable apache2 mods$($_WHITE_)"
lxc exec cloud -- bash -c "a2enmod rewrite > /dev/null"
lxc exec cloud -- bash -c "a2enmod headers env dir mime > /dev/null"

echo "$($_ORANGE_)Tuning opcache (php7) conf$($_WHITE_)"
lxc exec cloud -- bash -c "sed -i                                                                              \
    -e 's/;opcache.enable=0/opcache.enable=1/'                                      \
    -e 's/;opcache.enable_cli=0/opcache.enable_cli=1/'                              \
    -e 's/;opcache.interned_strings_buffer=4/opcache.interned_strings_buffer=8/'    \
    -e 's/;opcache.max_accelerated_files=2000/opcache.max_accelerated_files=10000/' \
    -e 's/;opcache.memory_consumption=64/opcache.memory_consumption=128/'           \
    -e 's/;opcache.save_comments=1/opcache.save_comments=1/'                        \
    -e 's/;opcache.revalidate_freq=2/opcache.revalidate_freq=1/'                    \
    /etc/php/7.0/fpm/php.ini"

echo "$($_ORANGE_)Restart FPM$($_WHITE_)"
lxc exec cloud -- bash -c "systemctl restart php7.0-fpm.service"

echo "$($_ORANGE_)Restart apache2$($_WHITE_)"
lxc exec cloud -- bash -c "systemctl restart apache2.service"

echo "$($_ORANGE_)Test Apache + PHP with FPM$($_WHITE_)"
lxc exec cloud -- bash -c "cat << EOF > /var/www/html/phpinfo.php
<?php
phpinfo();
EOF"

lxc exec cloud -- bash -c 'if curl -s 127.0.0.1/phpinfo.php|grep -q php-fpm; then
    echo -e "\n\033[33m ** FPM OK **\033[00m\n"
else
    >&2 echo -e "\033[31m==================== ERROR  ====================\033[00m"
    >&2 echo -e "\033[31m==================== FPM HS ====================\033[00m"
    exit 1
fi'

lxc exec cloud -- bash -c "rm -f /var/www/html/phpinfo.php"

echo "$($_ORANGE_)Download and uncompress Nextcloud$($_WHITE_)"
lxc exec cloud -- bash -c "wget -q https://download.nextcloud.com/server/releases/nextcloud-13.0.1.tar.bz2 -O /tmp/nextcloud.tar.bz2"
lxc exec cloud -- bash -c "tar xaf /tmp/nextcloud.tar.bz2 -C /var/www/"
lxc exec cloud -- bash -c "rm -f /tmp/nextcloud.tar.bz2"

echo "$($_ORANGE_)Update directory privileges$($_WHITE_)"
lxc exec cloud -- bash -c "
    chown -R www-data:www-data /var/www/nextcloud/
    mkdir -p /srv/data
    chown -R www-data:www-data /srv/data
    mkdir -p /var/log/nextcloud
    chown -R www-data:www-data /var/log/nextcloud
    "

echo "$($_ORANGE_)Create Vhost apache for Nextcloud$($_WHITE_)"
lxc exec cloud -- bash -c 'cat << "EOF" > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    ServerName __FQDN__

    ServerAdmin webmaster@zordhak.fr
    DocumentRoot /var/www/nextcloud

    # Autorisation des réécritures
    RewriteEngine  on

    # Tunning des logs de sortie
    LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\" \"%{Host}i\"" MyFormat
    CustomLog ${APACHE_LOG_DIR}/cloud_access.log MyFormat

</VirtualHost>

<Directory /var/www/nextcloud>

    Options +FollowSymLinks
    AllowOverride All
    Require all granted

    <IfModule mod_dav.c>
        Dav off
    </IfModule>

    SetEnv HOME /var/www/nextcloud
    SetEnv HTTP_HOME /var/www/nextcloud

</Directory>
EOF'

echo "$($_ORANGE_)Update FQDN$($_WHITE_)"
lxc exec cloud -- bash -c "sed -i 's/__FQDN__/$FQDN/' /etc/apache2/sites-available/nextcloud.conf"

echo "$($_ORANGE_)Enable Vhost « nextcloud »$($_WHITE_)"
lxc exec cloud -- bash -c "a2ensite nextcloud.conf > /dev/null"

echo "$($_ORANGE_)apache2 configtest$($_WHITE_)"
lxc exec cloud -- bash -c "apache2ctl configtest"

echo "$($_ORANGE_)Reload apache2$($_WHITE_)"
lxc exec cloud -- bash -c "systemctl reload apache2"

echo "$($_ORANGE_)Nextcloud installation$($_WHITE_)"
lxc exec cloud -- bash -c "occ maintenance:install --database 'mysql' --database-name 'nextcloud'  --database-user 'nextcloud' --database-pass '$MDP_nextcoud' --admin-user 'admincloud' --admin-pass '$MDP_admincloud' --data-dir='/srv/data'"

echo "$($_ORANGE_)Tune Nextcloud conf$($_WHITE_)"
lxc exec cloud -- bash -c "occ config:system:set trusted_domains 0 --value='$FQDN'
                           occ config:system:set overwrite.cli.url --value='$FQDN'
                           # French conf
                           occ config:system:set default_language --value='fr'
                           occ config:system:set force_language   --value='fr'
                           occ config:system:set htaccess.RewriteBase --value='/'
                           occ config:system:set logtimezone --value='Europe/Paris'
                           # Redis
                           occ config:system:set memcache.local --value='\\OC\\Memcache\\Redis'
                           occ config:system:set memcache.locking --value='\\OC\\Memcache\\Redis'
                           occ config:system:set redis host --value='localhost'
                           occ config:system:set redis port --value='6379'
                           # Log
                           occ config:system:set loglevel --value='2'
                           occ config:system:set logfile --value='/var/log/nextcloud/nextcloud.log'
                           # 100Mo ( 100 * 1024 * 1024 ) = 104857600 byte
                           occ config:system:set log_rotate_size --value=$(( 100 * 1024 * 1024 ))
                           "

echo "$($_ORANGE_)Update .htaccess$($_WHITE_)"
lxc exec cloud -- bash -c "occ maintenance:update:htaccess > /dev/null"

echo "$($_ORANGE_)Install app in Nextcloud$($_WHITE_)"
lxc exec cloud -- bash -c "occ app:install calendar
                           occ app:enable calendar
                           occ app:enable  admin_audit
                           occ app:install contacts
                           occ app:enable  contacts
                           occ app:install announcementcenter
                           occ app:enable  announcementcenter
                           "

