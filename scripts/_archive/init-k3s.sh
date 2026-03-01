#!/usr/bin/env bash

node_type=$1

config_server () {
    mkdir -p ~/.kube \
        && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config \
        && sudo chown k3sifnpmq:k3sifnpmq ~/.kube/config
    sudo chmod 644 /etc/rancher/k3s/k3s.yaml
    

    # Installing bash completion on Linux
    ## If bash-completion is not installed on Linux, install the 'bash-completion' package
    ## via your distribution's package manager.
    ## Load the kubectl completion code for bash into the current shell
    source <(kubectl completion bash)
    ## Write bash completion code to a file and source it from .bash_profile
    kubectl completion bash > ~/.kube/completion.bash.inc
    printf "
    # kubectl shell completion
    source '$HOME/.kube/completion.bash.inc'
    " >> $HOME/.bash_profile
    source $HOME/.bash_profile
}

if [ $node_type == "master" ]; then
    curl -fL https://get.k3s.io | K3S_TOKEN=${K3S_TOKEN} \
        K3S_DATASTORE_ENDPOINT=${K3S_DATASTORE_ENDPOINT} \
        sh -s - --disable traefik --disable servicelb server --cluster-init
    config_server
elif [ $node_type == "server" ]; then
    curl -fL https://get.k3s.io | K3S_TOKEN=${K3S_TOKEN} \
        K3S_DATASTORE_ENDPOINT=${K3S_DATASTORE_ENDPOINT} \
        sh -s - server --disable servicelb --server https://${K3S_URL}:6443
    config_server
elif [ $node_type == "agent" ]; then
    curl -sfL https://get.k3s.io | K3S_TOKEN=${K3S_TOKEN} \
        K3S_URL=${K3S_URL}:6443 \
        sh -s -
else
    echo "K3s node type not defined!"
fi
