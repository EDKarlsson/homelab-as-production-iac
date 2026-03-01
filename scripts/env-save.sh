#!/usr/bin/env bash
mapfile -t env_vars < <(sed 's/export //g;s/#.*$//g;s/=.*$//g;/^$/d' .env | sort -u)
save_vars=()

mapfile -t shell_var < <(env)

for var in "${env_vars[@]}"; do
    for shell_entry in "${shell_var[@]}"; do
        IFS='=' read -r key value <<< "$shell_entry"
        # Avoid saving SSH private keys
        if [[ "$key" == "$var" && ! "$key" =~ "SSH_PRIVATE_KEY" ]]; then
            save_vars+=("export $key=\"$value\"")
        fi
    done
done

rm .env.saved 2>/dev/null || true
echo "saving variables:"
for entry in "${save_vars[@]}"; do
    # shellcheck disable=SC2001  # sed pattern replaces quoted value; no clean param-expansion equivalent
    echo "$entry" | sed 's/=".*"/="***"/'
    echo "$entry" >> .env.saved
done
chmod 600 .env.saved
echo "Environment variables saved to .env.saved"
