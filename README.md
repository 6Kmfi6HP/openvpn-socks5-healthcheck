# OpenVPN SOCKS5 Proxy with Auto-Healing

This project provides a Docker container that automatically manages OpenVPN connections and exposes them as a SOCKS5 proxy. It includes features like automatic VPN server rotation, health monitoring, and automatic recovery.

## Features

- **Automatic VPN Configuration Management**
  - Auto-downloads VPN configurations from VPNGate
  - Periodically updates configurations (every 10 minutes)
  - Validates configurations before use
  - Backs up existing configurations before updates

- **Smart VPN Connection Management**
  - Country-based VPN server selection
  - Automatic server rotation on connection failures
  - Health monitoring with automatic recovery
  - Connection verification through SOCKS5 proxy

- **SOCKS5 Proxy Interface**
  - Easy to use SOCKS5 proxy interface
  - Configurable authentication
  - Local network binding for security

- **Auto-Healing**
  - Automatic health checks
  - Detects and recovers from connection failures
  - Intelligent server selection on failures
  - Integration with Docker's health check system

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/openvpn-socks5-healthcheck.git
   cd openvpn-socks5-healthcheck
   ```

2. Create a config.env file:
   ```bash
   # Basic configuration
   SOCKS5_USER=myuser
   SOCKS5_PASS=mypass
   
   # Optional: Specify preferred VPN country (e.g., JP, KR, US)
   VPN_COUNTRY=JP
   ```

3. Start the service:
   ```bash
   docker compose up -d
   ```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| SOCKS5_USER | SOCKS5 proxy username | user |
| SOCKS5_PASS | SOCKS5 proxy password | pass |
| VPN_COUNTRY | Preferred VPN server country (e.g., JP, KR) | - |
| ACTIVE_CONFIG | Specific VPN config to use | - |
| HEALTH_CHECK_INTERVAL | Interval between health checks (seconds) | 30 |

### Docker Compose Configuration

```yaml
version: '3.8'

services:
  vpn-socks5:
    build: .
    container_name: ${NAME:-vpn-socks5}
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    volumes:
      - ./vpn:/vpn
      - ./config.env:/config.env:ro
    env_file:
      - config.env
    environment:
      - ACTIVE_CONFIG=${ACTIVE_CONFIG:-}
      - VPN_COUNTRY=${VPN_COUNTRY:-JP}
      - SOCKS5_USER=${SOCKS5_USER:-user}
      - SOCKS5_PASS=${SOCKS5_PASS:-pass}
    ports:
      - "127.0.0.1:7777:7777"
    healthcheck:
      test: ["CMD", "curl", "-x", "socks5h://127.0.0.1:7777", "-U", "${SOCKS5_USER}:${SOCKS5_PASS}", "https://www.google.com", "-f", "-s", "-o", "/dev/null"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
```

## Usage

### Basic Usage

1. Start the service:
   ```bash
   docker compose up -d
   ```

2. Use the SOCKS5 proxy:
   ```
   Host: 127.0.0.1
   Port: 7777
   Username: [SOCKS5_USER from config]
   Password: [SOCKS5_PASS from config]
   ```

### Country-Specific VPN

To use VPN servers from a specific country:

1. Set VPN_COUNTRY in config.env:
   ```bash
   VPN_COUNTRY=JP  # For Japan
   ```

2. Or specify when starting:
   ```bash
   VPN_COUNTRY=KR docker compose up -d  # For Korea
   ```

Available country codes: JP (Japan), KR (Korea), US (United States), etc.

### Health Monitoring

The container automatically:
- Checks connection health every 30 seconds
- Rotates to a different VPN server if health check fails
- Maintains connection stability through auto-healing
- Updates VPN configurations every 10 minutes

### Logs and Monitoring

View container logs:
```bash
docker compose logs -f
```

Check container health:
```bash
docker ps  # Check STATUS column
```

## Security Considerations

- The SOCKS5 proxy is bound to localhost (127.0.0.1) by default
- Authentication is required for proxy access
- VPN configurations are automatically validated before use
- Container runs with minimal required privileges

## Troubleshooting

1. If the container fails to start:
   - Check if the tun device is available
   - Verify config.env permissions
   - Check container logs for errors

2. If the proxy is not accessible:
   - Verify the port mapping
   - Check SOCKS5 credentials
   - Ensure the container is healthy

3. If VPN connection is unstable:
   - Try specifying a different country
   - Check your internet connection
   - Review container logs for errors

## Contributing

Contributions are welcome! Please feel free to submit pull requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 