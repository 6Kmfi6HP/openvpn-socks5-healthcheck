FROM curve25519xsalsa20poly1305/openvpn-socks5

# Copy our custom entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set the new entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"] 