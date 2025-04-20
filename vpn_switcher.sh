#!/bin/bash

# Function to get a random config file
get_random_config() {
    local config_dir="/vpn"
    local configs=($(find "${config_dir}" -name "*.ovpn" -type f))
    
    if [ ${#configs[@]} -eq 0 ]; then
        echo "Error: No OpenVPN config files found in ${config_dir}" >&2
        exit 1
    fi
    
    # Get random index
    local random_index=$((RANDOM % ${#configs[@]}))
    echo "$(basename "${configs[$random_index]}")"
}

# Function to get next config file (cycling through them)
get_next_config() {
    local current="$1"
    local config_dir="/vpn"
    local configs=($(find "${config_dir}" -name "*.ovpn" -type f))
    
    if [ ${#configs[@]} -eq 0 ]; then
        echo "Error: No OpenVPN config files found in ${config_dir}" >&2
        exit 1
    fi
    
    # If no current config, return random one
    if [ -z "$current" ]; then
        get_random_config
        return
    fi
    
    # Find current config and get next one
    for i in "${!configs[@]}"; do
        if [ "$(basename "${configs[$i]}")" = "$current" ]; then
            local next_index=$(( (i + 1) % ${#configs[@]} ))
            echo "$(basename "${configs[$next_index]}")"
            return
        fi
    done
    
    # If current config not found, return random one
    get_random_config
}

# Function to switch VPN config
switch_vpn() {
    local next_config=$(get_next_config "${ACTIVE_CONFIG}")
    echo "Switching from ${ACTIVE_CONFIG} to ${next_config}"
    export ACTIVE_CONFIG="${next_config}"
    
    # Kill existing OpenVPN process
    if [ ! -z "${OPENVPN_PID}" ]; then
        kill "${OPENVPN_PID}" 2>/dev/null
    fi
    
    # Create new FIFO
    rm -f /openvpn-fifo
    mkfifo /openvpn-fifo
    
    # Start new OpenVPN process
    SAVED_DIR="${PWD}"
    cd $(dirname "/vpn/${next_config}")
    openvpn \
        --script-security 2 \
        --config "/vpn/${next_config}" \
        --up /usr/local/bin/openvpn-up.sh &
    export OPENVPN_PID=$!
    cd "${SAVED_DIR}"
    
    # Wait for VPN to initialize
    sleep 10
}

# Main loop
if [ "${VPN_SWITCH_MODE}" = "time" ]; then
    # Time-based switching
    while true; do
        switch_vpn
        sleep "${VPN_SWITCH_INTERVAL:-3600}"  # Default to 1 hour if not set
    done
else
    # Health check-based switching
    while true; do
        if ! /healthcheck.sh; then
            echo "Health check failed, switching VPN configuration..."
            switch_vpn
        fi
        sleep "${HEALTH_CHECK_INTERVAL:-60}"  # Default to 1 minute if not set
    done
fi 