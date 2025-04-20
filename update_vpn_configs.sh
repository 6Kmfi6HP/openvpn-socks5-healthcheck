#!/bin/bash

# Lock file path
LOCK_FILE="/tmp/vpn_update.lock"

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
source ./config.env

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

# Function to get list of config files from GitHub API
get_config_files() {
    curl -s "$API_BASE/repos/$REPO_OWNER/$REPO_NAME/contents/$CONFIGS_PATH?ref=$BRANCH" | \
    grep "\"path\"" | \
    grep "\.ovpn\"" | \
    sed -E 's/.*"path": "([^"]+)".*/\1/'
}

# Create vpn directory if it doesn't exist
mkdir -p "$VPN_CONFIGS_DIR"

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
echo "Fetching VPN configurations from VPNGate repository..."
CONFIGS=$(get_config_files)
DOWNLOAD_COUNT=0
TOTAL_CONFIGS=$(echo "$CONFIGS" | wc -l)

echo "Found $TOTAL_CONFIGS configuration files"

while IFS= read -r config_path; do
    if [ -n "$config_path" ]; then
        filename=$(basename "$config_path")
        output_path="$VPN_CONFIGS_DIR/$filename"
        if download_config "$config_path" "$output_path"; then
            ((DOWNLOAD_COUNT++))
        fi
    fi
done <<< "$CONFIGS"

echo "Successfully downloaded $DOWNLOAD_COUNT out of $TOTAL_CONFIGS configurations"

# Update ACTIVE_CONFIG if necessary
if [ $DOWNLOAD_COUNT -gt 0 ]; then
    # Get first config file as default
    FIRST_CONFIG=$(ls "$VPN_CONFIGS_DIR"/*.ovpn 2>/dev/null | head -n 1)
    if [ -n "$FIRST_CONFIG" ]; then
        FIRST_CONFIG=$(basename "$FIRST_CONFIG")
        # Update config.env if ACTIVE_CONFIG doesn't exist
        if [ ! -f "$VPN_CONFIGS_DIR/$ACTIVE_CONFIG" ]; then
            sed -i.bak "s/^ACTIVE_CONFIG=.*/ACTIVE_CONFIG=$FIRST_CONFIG/" config.env
            echo "Updated ACTIVE_CONFIG to $FIRST_CONFIG"
        fi
    fi
fi

# Set permissions
chmod 644 "$VPN_CONFIGS_DIR"/*.ovpn 2>/dev/null

echo "VPN configuration update completed"
if [ $DOWNLOAD_COUNT -gt 0 ]; then
    echo "You may need to restart the VPN service to apply new configurations"
fi

# Clean up lock file
rm -f "$LOCK_FILE" 