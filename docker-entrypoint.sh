#!/usr/bin/env bash

# Load environment variables from config.env if it exists
if [ -f "/config.env" ]; then
    echo "Loading configuration from config.env..."
    set -a
    source /config.env
    set +a
fi

# Completion marker file
COMPLETION_MARKER="/tmp/vpn_configs_ready"

# Clean up old files on startup
rm -f /openvpn-fifo
rm -f "$COMPLETION_MARKER"
rm -f /tmp/vpn_update.lock

# Function to spawn background processes
function spawn {
    if [[ -z ${PIDS+x} ]]; then PIDS=(); fi
    "$@" &
    PIDS+=($!)
}

# Function to wait for spawned processes
function join {
    if [[ ! -z ${PIDS+x} ]]; then
        for pid in "${PIDS[@]}"; do
            wait "${pid}"
        done
    fi
}

# Function to handle process cleanup
function on_kill {
    if [[ ! -z ${PIDS+x} ]]; then
        for pid in "${PIDS[@]}"; do
            kill "${pid}" 2> /dev/null
        done
    fi
    kill "${ENTRYPOINT_PID}" 2> /dev/null
}

# Function to update VPN configs periodically
function update_vpn_configs_loop {
    local last_success_time=0
    local min_interval=600  # Minimum 10 minutes between updates

    while true; do
        current_time=$(date +%s)
        
        # Only attempt update if enough time has passed since last success
        if [ $((current_time - last_success_time)) -ge $min_interval ]; then
            echo "Attempting VPN configurations update..."
            if /usr/local/bin/update_vpn_configs.sh; then
                echo "VPN configurations update completed successfully"
                last_success_time=$current_time
            else
                echo "VPN configurations update failed, will retry in 1 minute"
                sleep 60  # Wait 1 minute before retrying on failure
                continue
            fi
        fi
        
        # Calculate time to sleep until next update
        # This ensures we maintain the minimum interval between successful updates
        sleep_time=$((min_interval - ($(date +%s) - last_success_time)))
        if [ $sleep_time -gt 0 ]; then
            sleep $sleep_time
        else
            sleep $min_interval
        fi
    done
}

# Global array to store tried configs
declare -a TRIED_CONFIGS=()

# Function to get random config file
function get_config() {
    local config_dir="/vpn"
    local config_file=""
    local country_pattern=""
    
    # If VPN_COUNTRY is set, create pattern for filtering
    if [ ! -z "${VPN_COUNTRY}" ]; then
        echo "Filtering configs for country: ${VPN_COUNTRY}" >&2
        country_pattern="_${VPN_COUNTRY}.ovpn$"
    fi
    
    # List all .ovpn files, filtered by country if specified
    if [ ! -z "${country_pattern}" ]; then
        local configs=($(find "${config_dir}" -name "*.ovpn" -type f | grep "${country_pattern}" || true))
        if [ ${#configs[@]} -eq 0 ]; then
            echo "Warning: No configs found for country ${VPN_COUNTRY}, falling back to all configs" >&2
            local configs=($(find "${config_dir}" -name "*.ovpn" -type f))
        else
            echo "Found ${#configs[@]} configs for country ${VPN_COUNTRY}" >&2
        fi
    else
        local configs=($(find "${config_dir}" -name "*.ovpn" -type f))
    fi
    
    # If no configs found, exit with error
    if [ ${#configs[@]} -eq 0 ]; then
        echo "Error: No OpenVPN config files found in ${config_dir}" >&2
        exit 1
    fi
    
    # If ACTIVE_CONFIG is set and exists and hasn't been tried, use it
    if [ -n "${ACTIVE_CONFIG}" ] && [ -f "${config_dir}/${ACTIVE_CONFIG}" ] && [[ ! " ${TRIED_CONFIGS[@]} " =~ " ${config_dir}/${ACTIVE_CONFIG} " ]]; then
        # If country is specified, check if ACTIVE_CONFIG matches country
        if [ ! -z "${country_pattern}" ]; then
            if echo "${ACTIVE_CONFIG}" | grep -q "${country_pattern}"; then
                config_file="${config_dir}/${ACTIVE_CONFIG}"
            fi
        else
            config_file="${config_dir}/${ACTIVE_CONFIG}"
        fi
    fi
    
    # If no config file selected yet, choose random one
    if [ -z "${config_file}" ]; then
        # Filter out already tried configs
        local available_configs=()
        for config in "${configs[@]}"; do
            if [[ ! " ${TRIED_CONFIGS[@]} " =~ " ${config} " ]]; then
                available_configs+=("$config")
            fi
        done
        
        # If all configs have been tried, reset the tried list
        if [ ${#available_configs[@]} -eq 0 ]; then
            TRIED_CONFIGS=()
            available_configs=("${configs[@]}")
        fi
        
        # Get random config from available ones
        local random_index=$((RANDOM % ${#available_configs[@]}))
        config_file="${available_configs[$random_index]}"
    fi
    
    # Add selected config to tried list
    TRIED_CONFIGS+=("$config_file")
    
    # Verify the selected config exists and is readable
    if [ ! -f "${config_file}" ] || [ ! -r "${config_file}" ]; then
        echo "Error: Selected config ${config_file} is not accessible" >&2
        return 1
    fi
    
    echo "${config_file}"
}

# Function to switch VPN config
function switch_vpn() {
    echo "Switching VPN configuration..."
    kill $(pidof openvpn) 2>/dev/null
    
    # Get new config
    OPENVPN_CONFIG=$(get_config)
    echo "Switching to OpenVPN config: ${OPENVPN_CONFIG}"
    
    # Start OpenVPN with new config
    cd $(dirname "${OPENVPN_CONFIG}")
    spawn openvpn \
        --script-security 2 \
        --config "${OPENVPN_CONFIG}" \
        --up /usr/local/bin/openvpn-up.sh
    cd "${SAVED_DIR}"
}

# Handle SIGUSR1 signal for VPN switching
trap "switch_vpn" SIGUSR1

# Print current configuration
echo "Current configuration:"
echo "SOCKS5_USER: ${SOCKS5_USER:-user}"
echo "SOCKS5_PORT: ${SOCKS5_PORT:-1080}"
echo "VPN_CONFIGS_DIR: ${VPN_CONFIGS_DIR:-/vpn}"

export ENTRYPOINT_PID="${BASHPID}"

# Set up signal handlers
trap "on_kill" EXIT
trap "on_kill" SIGINT

# Start VPN config update loop in background first
spawn update_vpn_configs_loop

# Wait for initial VPN configs to be ready
echo "Waiting for VPN configurations to be downloaded..."
WAIT_COUNT=0
MAX_WAIT=60  # Maximum 5 minutes (60 * 5 seconds)
while [ ! -f "$COMPLETION_MARKER" ]; do
    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
        echo "Error: Timeout waiting for VPN configurations"
        exit 1
    fi
    echo "Still waiting for VPN configurations... ($(($WAIT_COUNT * 5)) seconds)"
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 1))
done
echo "VPN configurations are ready"

# Reset TRIED_CONFIGS array since we have fresh configs
TRIED_CONFIGS=()

# Get and validate initial OpenVPN config
OPENVPN_CONFIG=$(get_config)
if [ $? -ne 0 ] || [ -z "${OPENVPN_CONFIG}" ]; then
    echo "Error: Failed to get a valid OpenVPN config"
    exit 1
fi

echo "Using OpenVPN config: ${OPENVPN_CONFIG}"

if [ ! -f "${OPENVPN_CONFIG}" ]; then
    echo "Error: ${OPENVPN_CONFIG} is not a valid file!"
    exit 1
fi

# Double check file exists and is readable
if [ ! -r "${OPENVPN_CONFIG}" ]; then
    echo "Error: Cannot read ${OPENVPN_CONFIG}"
    exit 1
fi

export OPENVPN_CONFIG=$(readlink -f "${OPENVPN_CONFIG}")

# Create FIFO for OpenVPN communication
mkfifo /openvpn-fifo

# Set up routing
SUBNET=$(ip -o -f inet addr show dev eth0 | awk '{print $4}')
IPADDR=$(echo "${SUBNET}" | cut -f1 -d'/')
GATEWAY=$(route -n | grep 'UG[ \t]' | awk '{print $2}')
eval $(ipcalc -np "${SUBNET}")

ip rule add from "${IPADDR}" table 128
ip route add table 128 to "${NETWORK}/${PREFIX}" dev eth0
ip route add table 128 default via "${GATEWAY}"

# Start OpenVPN
SAVED_DIR="${PWD}"
cd $(dirname "${OPENVPN_CONFIG}")
spawn openvpn \
    --script-security 2 \
    --config "${OPENVPN_CONFIG}" \
    --up /usr/local/bin/openvpn-up.sh
cd "${SAVED_DIR}"

# Start health check script
spawn /usr/local/bin/healthcheck.sh

cat /openvpn-fifo > /dev/null
rm -f /openvpn-fifo

# Handle additional commands
if [[ -n "${OPENVPN_UP}" ]]; then
    spawn "${OPENVPN_UP}" "$@"
elif [[ $# -gt 0 ]]; then
    "$@"
fi

# Keep container running if no additional commands or DAEMON_MODE is true
if [[ $# -eq 0 || "${DAEMON_MODE}" == true ]]; then
    join
fi 