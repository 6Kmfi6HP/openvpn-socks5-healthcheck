#!/bin/bash

# Lock file path
LOCK_FILE="/tmp/vpn_update.lock"
# Completion marker file
COMPLETION_MARKER="/tmp/vpn_configs_ready"

# Remove completion marker at start
rm -f "$COMPLETION_MARKER"

# Exit if another instance is running
if [ -f "$LOCK_FILE" ]; then
    # Check if process is actually running
    if ps -p $(cat "$LOCK_FILE") > /dev/null 2>&1; then
        echo "Another instance is already running"
        exit 1
    else
        # Lock file exists but process is not running, remove stale lock
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Ensure lock file is removed on script exit
trap 'rm -f "$LOCK_FILE"' EXIT

# Load configuration
if [ -f "/config.env" ]; then
    source /config.env
else
    echo "Error: config.env not found"
    exit 1
fi

# Verify VPN_CONFIGS_DIR is set
if [ -z "$VPN_CONFIGS_DIR" ]; then
    VPN_CONFIGS_DIR="/vpn"
fi

# Set default country if not specified
if [ -z "$VPN_COUNTRY" ]; then
    VPN_COUNTRY="JP"
fi

echo "Downloading VPN configs for country: $VPN_COUNTRY"

# Create vpn directory if it doesn't exist
mkdir -p "$VPN_CONFIGS_DIR"

# Function to verify OpenVPN config file
verify_config() {
    local config_file="$1"
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    if [ ! -s "$config_file" ]; then
        return 1
    fi
    # Basic OpenVPN config validation
    if ! grep -q "^remote " "$config_file"; then
        return 1
    fi
    return 0
}

# GitHub repository information
REPO_OWNER="fdciabdul"
REPO_NAME="Vpngate-Scraper-API"
BRANCH="main"
CONFIGS_PATH="configs"
API_BASE="https://api.github.com"
RAW_BASE="https://raw.githubusercontent.com"

# Function to download a single config file
download_config() {
    local file_path="$1"
    local output_file="$2"
    echo "Downloading $file_path to $output_file"
    curl -s -L -o "$output_file" "$RAW_BASE/$REPO_OWNER/$REPO_NAME/$BRANCH/$file_path"
    if [ $? -eq 0 ] && [ -s "$output_file" ]; then
        echo "Successfully downloaded $output_file"
        return 0
    else
        echo "Failed to download $output_file"
        rm -f "$output_file"
        return 1
    fi
}

# Function to get list of config files from GitHub API for specific country
get_config_files() {
    curl -s "$API_BASE/repos/$REPO_OWNER/$REPO_NAME/contents/$CONFIGS_PATH?ref=$BRANCH" | \
    grep "\"path\"" | \
    grep "\.ovpn\"" | \
    grep "_${VPN_COUNTRY}\.ovpn\"" | \
    sed -E 's/.*"path": "([^"]+)".*/\1/'
}

# Get current timestamp for backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Backup existing configs if any exist
if [ "$(ls -A $VPN_CONFIGS_DIR/*.ovpn 2>/dev/null)" ]; then
    echo "Backing up existing configurations..."
    BACKUP_DIR="${VPN_CONFIGS_DIR}_backup_${TIMESTAMP}"
    mkdir -p "$BACKUP_DIR"
    cp "$VPN_CONFIGS_DIR"/*.ovpn "$BACKUP_DIR"/ 2>/dev/null
    echo "Backed up to $BACKUP_DIR"
fi

# Clean existing configs
rm -f "$VPN_CONFIGS_DIR"/*.ovpn

# Download new configs
echo "Fetching VPN configurations for $VPN_COUNTRY from VPNGate repository..."
CONFIGS=$(get_config_files)
DOWNLOAD_COUNT=0
TOTAL_CONFIGS=$(echo "$CONFIGS" | wc -l)

if [ "$TOTAL_CONFIGS" -eq 0 ]; then
    echo "No configurations found for country $VPN_COUNTRY"
    echo "Please check if the country code is correct. Example country codes: JP, US, KR, etc."
    exit 1
fi

echo "Found $TOTAL_CONFIGS configuration files for $VPN_COUNTRY"

while IFS= read -r config_path; do
    if [ -n "$config_path" ]; then
        filename=$(basename "$config_path")
        output_path="$VPN_CONFIGS_DIR/$filename"
        if download_config "$config_path" "$output_path"; then
            ((DOWNLOAD_COUNT++))
        fi
    fi
done <<< "$CONFIGS"

echo "Successfully downloaded $DOWNLOAD_COUNT out of $TOTAL_CONFIGS configurations for $VPN_COUNTRY"

# After download, verify configs
echo "Verifying downloaded configurations..."
VALID_CONFIGS=0
for config in "$VPN_CONFIGS_DIR"/*.ovpn; do
    if verify_config "$config"; then
        VALID_CONFIGS=$((VALID_CONFIGS + 1))
    else
        echo "Removing invalid config: $config"
        rm -f "$config"
    fi
done

if [ $VALID_CONFIGS -gt 0 ]; then
    echo "Successfully verified $VALID_CONFIGS configurations for $VPN_COUNTRY"
    touch "$COMPLETION_MARKER"
    echo "VPN configurations are ready for use"
else
    echo "Error: No valid VPN configurations found for $VPN_COUNTRY"
    rm -f "$COMPLETION_MARKER"
    exit 1
fi

# Clean up lock file
rm -f "$LOCK_FILE" 