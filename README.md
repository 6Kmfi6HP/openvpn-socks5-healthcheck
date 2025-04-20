# OpenVPN SOCKS5 with Auto Health Check

This project provides an automated solution for running an OpenVPN client with SOCKS5 proxy support and automatic failover between multiple VPN configurations.

## Features

- Runs OpenVPN client in a Docker container
- Exposes a SOCKS5 proxy with authentication
- Automatic health checking of VPN connection
- Automatic failover to next VPN configuration when connection fails
- Easy configuration through environment variables

## Prerequisites

- Docker
- Docker Compose
- curl (for health checking)
- Bash shell

## Setup

1. Create a `vpn` directory and place your OpenVPN configuration files (*.ovpn) in it:
   ```bash
   mkdir -p vpn
   cp your-vpn-configs/*.ovpn vpn/
   ```

2. Configure the environment variables in `config.env`:
   ```bash
   # Adjust values as needed
   NAME=vpn-socks5
   SOCKS5_PORT=7777
   SOCKS5_USER=myuser
   SOCKS5_PASS=mypass
   ```

3. Make sure the health check script is executable:
   ```bash
   chmod +x healthcheck.sh
   ```

## Usage

1. Start the VPN service:
   ```bash
   docker compose up -d
   ```

2. Start the health check monitor in a separate terminal:
   ```bash
   ./healthcheck.sh
   ```

3. Use the SOCKS5 proxy:
   ```
   Host: localhost
   Port: 7777 (or your configured port)
   Username: myuser (or your configured username)
   Password: mypass (or your configured password)
   ```

The health check script will automatically monitor the VPN connection and switch to the next configuration if the current one fails.

## Configuration

### Environment Variables

- `NAME`: Container name
- `SOCKS5_PORT`: Port for the SOCKS5 proxy
- `SOCKS5_USER`: Username for SOCKS5 authentication
- `SOCKS5_PASS`: Password for SOCKS5 authentication
- `CHECK_INTERVAL`: Time between health checks in seconds
- `MAX_FAILURES`: Number of consecutive failures before switching VPN
- `CURL_TIMEOUT`: Timeout for health check requests
- `VPN_CONFIGS_DIR`: Directory containing OpenVPN configurations
- `ACTIVE_CONFIG`: Currently active VPN configuration file

## Health Check Logic

The health check script:
1. Attempts to connect to https://www.google.com through the SOCKS5 proxy
2. If the connection fails, increments a failure counter
3. After `MAX_FAILURES` consecutive failures, switches to the next VPN configuration
4. Continues monitoring in an infinite loop

## Troubleshooting

1. Check container logs:
   ```bash
   docker compose logs
   ```

2. Check health check script logs (printed to stdout)

3. Verify VPN configurations are correctly placed in the `vpn` directory

4. Ensure proper permissions on the `healthcheck.sh` script 