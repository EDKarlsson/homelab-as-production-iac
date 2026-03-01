#!/usr/bin/env bash

sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  vim git zsh tree tmux \
  avahi-daemon avahi-discover avahi-utils libnss-mdns mdns-scan

# restart mdns service
sudo systemctl restart avahi-daemon
