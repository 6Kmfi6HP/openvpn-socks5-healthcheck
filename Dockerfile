FROM curve25519xsalsa20poly1305/openvpn-socks5

# Install curl for health checks
# RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy our custom scripts
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/healthcheck.sh

# Set environment variables
ENV HEALTH_CHECK_INTERVAL=30

# Set the new entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"] 