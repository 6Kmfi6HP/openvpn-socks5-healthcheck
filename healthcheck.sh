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

# Function to check VPN connection
check_vpn() {
    # Get container health status
    health_status=$(docker inspect --format='{{.State.Health.Status}}' "${NAME}")
    if [ "$health_status" = "healthy" ]; then
        return 0
    else
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

# Main loop
echo "Starting VPN health check monitoring..."
echo "Initial configuration: $CURRENT_CONFIG"

while true; do
    if check_vpn; then
        echo "[$(date)] VPN connection is healthy"
        FAILURE_COUNT=0
    else
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo "[$(date)] VPN check failed (Failure count: $FAILURE_COUNT/$MAX_FAILURES)"
        
        if [ $FAILURE_COUNT -ge $MAX_FAILURES ]; then
            echo "[$(date)] Maximum failures reached, switching VPN configuration"
            switch_vpn
        fi
    fi
    
    sleep "$CHECK_INTERVAL"
done 