#!/usr/bin/env bash

#########################################################
## Needs to be fixed -- See working script init-k3s.sh ##
#########################################################

export $( grep 'K3S_' .env | grep -v "^#" | xargs )

K3S_CONFIG_DIR=$(find . -name 'k3s.config.d')
K3S_CONFIG_FILES=($(find ${K3S_CONFIG_DIR} -name '*-config.yaml' -exec basename {} \;))
K3S_ENV_VARS=$(env | sort | grep K3S)

agents=($(printenv K3S_AGENTS | sed 's/:/ /g'))
servers=($(printenv K3S_SERVERS) $(printenv K3S_AGENTS | sed 's/:/ /g'))

print_confs () {
    echo "Config dir: ${K3S_CONFIG_DIR}"
    echo "Config files:"
    for conf in ${K3S_CONFIG_FILES[@]}; do
        echo $conf
    done
}

print_k3s_var () {
    echo "K3s env vars:"
    for var in ${K3S_ENV_VARS[@]}; do
        echo $var
    done
    echo "Agents: " $(printenv K3S_AGENTS | sed 's/:/, /g')
    echo "Servers:" $(printenv K3S_SERVER)", " $(printenv K3S_OTHER_SERVERS | sed 's/:/, /g')
}

copy_config () {
    scp "${K3S_CONFIG_DIR}/$1-config.yaml" "$1:~/config.yaml"
    ssh -t "$1" "sudo mkdir -p /etc/rancher/k3s/config.yaml.d && sudo mv ~/config.yaml /etc/rancher/k3s/config.yaml.d && sudo chown -R root:root /etc/rancher"
}

install_k3s () {
    case $1 in
        kcs-*)
            echo "Init k3s server..."
            # ssh -t $1 "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server' K3S_DATASTORE_ENDPOINT=${K3S_DATASTORE_ENDPOINT} K3S_TOKEN=${K3S_TOKEN} sh -s - --flannel-backend none"
            ssh -t $1 "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server' sh -s - --flannel-backend none --datastore-endpoint=${K3S_DATASTORE_ENDPOINT} --token=${K3S_TOKEN}"
        ;;
        kca-*)
            echo "Init k3s agent..."
            ssh -t $1 "curl -sfL https://get.k3s.io | K3S_URL=https://${K3S_URL} K3S_TOKEN=${K3S_TOKEN} sh -s -"

        ;;
        *)
        echo "[ERROR] K3s Type: $1"
        exit 1
        ;;
    esac
}

install_k3s kca-fnw4la

get_server_token () {
    # Capture K3s server token
    printf "Getting token from kcs-$1.\nEnter Password:\n"
    K3S_TOKEN=$(ssh -t $1 "sudo cat /var/lib/rancher/k3s/server/token" | grep -v sudo )
    if [ $(uname) == "Darwin" ]; then
        sed -i '' "s/_TOKEN=.*/_TOKEN=${K3S_TOKEN}/g" '.env'
    else
        sed -i "s/_TOKEN=.*/_TOKEN=${K3S_TOKEN}/g" '.env'
    fi
}

# get_server_token kcs-${K3S_SERVER}

# main () {

# }