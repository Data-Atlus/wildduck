#! /bin/bash

OURNAME=05_install_packages.sh

echo -e "\n-- Executing ${ORANGE}${OURNAME}${NC} subscript --"

# install nginx
apt-get update
apt-get -q -y install pwgen git ufw build-essential libssl-dev dnsutils python software-properties-common nginx wget nodejs redis-server clamav clamav-daemon

apt-get clean
