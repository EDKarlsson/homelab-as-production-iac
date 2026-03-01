#!/bin/bash

apt update && apt install nut nut-client
systemctl enable --now nut-client

sed 's/mode=(none|standalone)/mode=netclient/' -i /etc/nut/nut.conf
echo 'MONITOR ups@leviathan "NAS CyberPower CP1350PFCLCD UPS"' >> /etc/nut/hosts.conf

systemctl restart nut-client