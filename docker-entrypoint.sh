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

# Function to get first available config file
function get_config() {
    local config_dir="/vpn"
    local config_file=""
    
    # List all .ovpn files
    local configs=($(find "${config_dir}" -name "*.ovpn" -type f))
    
    # If no configs found, exit with error
    if [ ${#configs[@]} -eq 0 ]; then
        echo "Error: No OpenVPN config files found in ${config_dir}" >&2
        exit 1
    fi
    
    # If ACTIVE_CONFIG is set and exists, use it
    if [ -n "${ACTIVE_CONFIG}" ] && [ -f "${config_dir}/${ACTIVE_CONFIG}" ]; then
        config_file="${config_dir}/${ACTIVE_CONFIG}"
    else
        # Otherwise, use the first available config
        config_file="${configs[0]}"
    fi
    
    echo "${config_file}"
}

# Print current configuration
echo "Current configuration:"
echo "SOCKS5_USER: ${SOCKS5_USER:-user}"
echo "SOCKS5_PORT: ${SOCKS5_PORT:-1080}"
echo "VPN_CONFIGS_DIR: ${VPN_CONFIGS_DIR:-/vpn}"

export ENTRYPOINT_PID="${BASHPID}"

# Set up signal handlers
trap "on_kill" EXIT
trap "on_kill" SIGINT

# Get and validate OpenVPN config
OPENVPN_CONFIG=$(get_config)
echo "Using OpenVPN config: ${OPENVPN_CONFIG}"

if [ ! -f "${OPENVPN_CONFIG}" ]; then
    echo "Error: ${OPENVPN_CONFIG} is not a valid file!"
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