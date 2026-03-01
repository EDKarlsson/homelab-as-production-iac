#!/usr/bin/env bash

KEY_NAME=$1

ssh-keygen -C "${KEY_NAME}" -f "/Users/dank/.ssh/config.d/${KEY_NAME}_ed25519"