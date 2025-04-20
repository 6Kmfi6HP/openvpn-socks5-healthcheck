#!/bin/bash

# Load configuration
source ./config.env

# Default update interval (in hours)
UPDATE_INTERVAL=${UPDATE_INTERVAL:-24}

echo "Starting VPN auto-update and health check system..."
echo "Will check for new VPN configs every $UPDATE_INTERVAL hours"

# Start health check in background
./healthcheck.sh &
HEALTH_CHECK_PID=$!

# Trap to handle script termination
cleanup() {
    echo "Stopping health check system..."
    kill $HEALTH_CHECK_PID 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

# Main update loop
while true; do
    echo "[$(date)] Updating VPN configurations..."
    ./update_vpn_configs.sh
    
    # Sleep for specified interval
    echo "Next update in $UPDATE_INTERVAL hours"
    sleep ${UPDATE_INTERVAL}h
done 