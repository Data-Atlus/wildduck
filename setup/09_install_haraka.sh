#! /bin/bash

OURNAME=08_install_haraka.sh

echo -e "\n-- Executing ${ORANGE}${OURNAME}${NC} subscript --"



####### HARAKA #######

# clear previous install
if [ -f "/etc/systemd/system/haraka.service" ]
then
    $SYSTEMCTL_PATH stop haraka || true
    $SYSTEMCTL_PATH disable haraka || true
    rm -rf /etc/systemd/system/haraka.service
fi
rm -rf /var/opt/haraka-plugin-wildduck.git
rm -rf /opt/haraka

# fresh install
cd /var/opt
git clone --bare git://github.com/nodemailer/haraka-plugin-wildduck.git
echo "#!/bin/bash
git --git-dir=/var/opt/haraka-plugin-wildduck.git --work-tree=/opt/haraka/plugins/wildduck checkout "\$3" -f
cd /opt/haraka/plugins/wildduck
rm -rf package-lock.json
npm install --production --no-optional --no-package-lock --no-audit --ignore-scripts --no-shrinkwrap --progress=false
sudo $SYSTEMCTL_PATH restart haraka || echo \"Failed restarting service\"" > "/var/opt/haraka-plugin-wildduck.git/hooks/update"
chmod +x "/var/opt/haraka-plugin-wildduck.git/hooks/update"

# allow deploy user to restart wildduck service
echo "deploy ALL = (root) NOPASSWD: $SYSTEMCTL_PATH restart haraka" >> /etc/sudoers.d/wildduck

cd
npm install --production --no-optional --no-package-lock --no-audit --ignore-scripts --no-shrinkwrap --unsafe-perm -g Haraka@$HARAKA_VERSION
haraka -i /opt/haraka
cd /opt/haraka
npm install --production --no-optional --no-package-lock --no-audit --ignore-scripts --no-shrinkwrap --unsafe-perm --save haraka-plugin-redis haraka-plugin-watch haraka-plugin-limit Haraka@$HARAKA_VERSION

# Haraka WildDuck plugin. Install as separate repo as it can be edited more easily later
mkdir -p plugins/wildduck
git --git-dir=/var/opt/haraka-plugin-wildduck.git --work-tree=/opt/haraka/plugins/wildduck checkout "$WILDDUCK_HARAKA_COMMIT"

cd plugins/wildduck
npm install --production --no-optional --no-package-lock --no-audit --ignore-scripts --no-shrinkwrap --unsafe-perm --progress=false

cd /opt/haraka
mv config/plugins config/plugins.bak

echo "26214400" > config/databytes
echo "$HOSTNAME" > config/me
echo "WildDuck MX" > config/smtpgreeting

# Setup plugins file
echo "# SPF setup
spf

# DKIM setup for verification and signing
dkim_sign
dkim_verify

# Only accept mail where the MAIL FROM domain is resolvable to an MX record
mail_from.is_resolvable

## ClamAV is disabled by default. Make sure freshclam has updated all
## virus definitions and clamav-daemon has successfully started before
## enabling it.
#clamd

# TLS Setup
tls

# WildDuck plugin handles recipient checking and queueing
wildduck

# Limit plugin
limit

# Watch live SMTP traffic in a web interface
watch
" > config/plugins

echo "key=/etc/wildduck/certs/privkey.pem
cert=/etc/wildduck/certs/fullchain.pem" > config/tls.ini

echo 'clamd_socket = /var/run/clamav/clamd.ctl
[reject]
virus=true
error=false' > config/clamd.ini

# DKIM Setup
DKIM_FILE_LOCATION="/opt/zone-mta/keys/$MAILDOMAIN-dkim.pem"
echo "disabled=false
selector=$DKIM_SELECTOR
domain=$MAILDOMAIN
dkim.private.key=$DKIM_FILE_LOCATION
headers_to_sign = From,Sender,Reply-To,Subject,Date,Message-ID,To,Cc,MIME-Version" > config/dkim_sign.ini

# Setup wildduck config file
cp plugins/wildduck/config/wildduck.yaml config/wildduck.yaml
sed -i -e "s/secret value/$SRS_SECRET/g;s/#loopSecret/loopSecret/g" config/wildduck.yaml

# Ensure required files and permissions
echo "d /opt/haraka 0755 deploy deploy" > /etc/tmpfiles.d/haraka.conf
log_script "haraka"

echo '[Unit]
Description=Haraka MX Server
After=redis.service

[Service]
Environment="NODE_ENV=production"
WorkingDirectory=/opt/haraka
ExecStart=/usr/bin/node ./node_modules/.bin/haraka -c .
Type=simple
Restart=always
SyslogIdentifier=haraka

[Install]
WantedBy=multi-user.target' > /etc/systemd/system/haraka.service

echo 'user=wildduck
group=wildduck' >> config/smtp.ini

chown -R deploy:deploy /opt/haraka
chown -R deploy:deploy /var/opt/haraka-plugin-wildduck.git

# ensure queue folder for Haraka
mkdir -p /opt/haraka/queue
chown -R wildduck:wildduck /opt/haraka/queue

$SYSTEMCTL_PATH enable haraka.service
