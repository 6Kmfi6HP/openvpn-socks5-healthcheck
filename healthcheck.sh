#!/bin/bash

# Load configuration
source ./config.env

# Initialize variables
FAILURE_COUNT=0
CURRENT_CONFIG="$ACTIVE_CONFIG"

# Create vpn directory if it doesn't exist
mkdir -p "$VPN_CONFIGS_DIR"

# Function to get next VPN config
get_next_config() {
    local current="$1"
    local configs=($(find "$VPN_CONFIGS_DIR" -name "*.ovpn" -type f))
    local next_config=""
    
    if [ ${#configs[@]} -eq 0 ]; then
        echo "No VPN configurations found in $VPN_CONFIGS_DIR" >&2
        exit 1
    fi
    
    # If no current config, return first one
    if [ -z "$current" ]; then
        next_config=$(basename "${configs[0]}")
    else
        # Find current config and get next one
        for i in "${!configs[@]}"; do
            if [ "$(basename "${configs[$i]}")" = "$current" ]; then
                next_index=$(( (i + 1) % ${#configs[@]} ))
                next_config=$(basename "${configs[$next_index]}")
                break
            fi
        done
        
        # If current config not found, return first one
        if [ -z "$next_config" ]; then
            next_config=$(basename "${configs[0]}")
        fi
    fi
    
    echo "$next_config"
}

# Function to check if VPN is working and get current IP
check_vpn() {
    # Try to curl an external IP check service through the VPN
    # timeout after 10 seconds to avoid hanging
    local ip_address=$(timeout 10 curl -s --socks5 localhost:${SOCKS5_PORT:-1080} https://api.ipify.org)
    if [ $? -eq 0 ] && [ ! -z "$ip_address" ]; then
        echo "Current VPN IP: $ip_address"
        return 0
    else
        echo "Failed to get IP address through VPN"
        return 1
    fi
}

# Function to switch VPN configuration
switch_vpn() {
    local next_config=$(get_next_config "$CURRENT_CONFIG")
    echo "Switching from $CURRENT_CONFIG to $next_config"
    
    # Update the active configuration
    sed -i.bak "s/^ACTIVE_CONFIG=.*$/ACTIVE_CONFIG=$next_config/" config.env
    CURRENT_CONFIG="$next_config"
    
    # Update container environment and restart
    docker compose up -d --force-recreate vpn-socks5
    
    # Wait for container to initialize
    sleep 15
    FAILURE_COUNT=0
}

# Main health check loop
echo "Starting VPN health check monitoring..."
echo "Initial configuration: $CURRENT_CONFIG"

while true; do
    if ! check_vpn; then
        echo "Health check failed - VPN connection appears to be down"
        # Signal the main process to switch to next config
        pkill -USR1 openvpn
        sleep 5
    else
        echo "Health check passed - VPN connection is working"
    fi
    sleep ${HEALTH_CHECK_INTERVAL:-30}
done 