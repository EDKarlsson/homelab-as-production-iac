#!/bin/bash
export os=debian
export dist=trixie
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash

apt update && apt install -q -y speedtest

speedtest --accept-license --accept-gdpr