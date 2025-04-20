#!/usr/bin/env bash

# Load environment variables from config.env if it exists
if [ -f "/config.env" ]; then
    echo "Loading configuration from config.env..."
    set -a
    source /config.env
    set +a
fi

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

# Function to get random config file
function get_random_config() {
    local config_dir="/vpn"
    local configs=($(find "${config_dir}" -name "*.ovpn" -type f))
    
    if [ ${#configs[@]} -eq 0 ]; then
        echo "Error: No OpenVPN config files found in ${config_dir}" >&2
        exit 1
    fi
    
    # Get random index
    local random_index=$((RANDOM % ${#configs[@]}))
    echo "${configs[$random_index]}"
}

# Print current configuration
echo "Current configuration:"
echo "SOCKS5_USER: ${SOCKS5_USER:-user}"
echo "SOCKS5_PORT: ${SOCKS5_PORT:-1080}"
echo "VPN_CONFIGS_DIR: ${VPN_CONFIGS_DIR:-/vpn}"
echo "VPN_SWITCH_MODE: ${VPN_SWITCH_MODE:-health}"
echo "VPN_SWITCH_INTERVAL: ${VPN_SWITCH_INTERVAL:-3600}"
echo "HEALTH_CHECK_INTERVAL: ${HEALTH_CHECK_INTERVAL:-60}"

export ENTRYPOINT_PID="${BASHPID}"

# Set up signal handlers
trap "on_kill" EXIT
trap "on_kill" SIGINT

# Get initial OpenVPN config
if [ -n "${ACTIVE_CONFIG}" ] && [ -f "/vpn/${ACTIVE_CONFIG}" ]; then
    OPENVPN_CONFIG="/vpn/${ACTIVE_CONFIG}"
else
    OPENVPN_CONFIG=$(get_random_config)
fi

echo "Using initial OpenVPN config: ${OPENVPN_CONFIG}"

# Copy health check script to root
cp /healthcheck.sh /healthcheck.sh
chmod +x /healthcheck.sh

# Copy VPN switcher script to root
cp /vpn_switcher.sh /vpn_switcher.sh
chmod +x /vpn_switcher.sh

# Set up routing
SUBNET=$(ip -o -f inet addr show dev eth0 | awk '{print $4}')
IPADDR=$(echo "${SUBNET}" | cut -f1 -d'/')
GATEWAY=$(route -n | grep 'UG[ \t]' | awk '{print $2}')
eval $(ipcalc -np "${SUBNET}")

ip rule add from "${IPADDR}" table 128
ip route add table 128 to "${NETWORK}/${PREFIX}" dev eth0
ip route add table 128 default via "${GATEWAY}"

# Start VPN switcher in background
spawn /vpn_switcher.sh

# Start OpenVPN
SAVED_DIR="${PWD}"
cd $(dirname "${OPENVPN_CONFIG}")
spawn openvpn \
    --script-security 2 \
    --config "${OPENVPN_CONFIG}" \
    --up /usr/local/bin/openvpn-up.sh
export OPENVPN_PID=$!
cd "${SAVED_DIR}"

# Handle additional commands
if [[ -n "${OPENVPN_UP}" ]]; then
    spawn "${OPENVPN_UP}" "$@"
elif [[ $# -gt 0 ]]; then
    "$@"
fi

# Keep container running
join 