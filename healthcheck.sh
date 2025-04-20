#!/bin/bash

# Default values
CHECK_URL=${HEALTH_CHECK_URL:-"https://www.google.com"}
CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-10}
MAX_RETRIES=${HEALTH_CHECK_RETRIES:-3}
RETRY_INTERVAL=${HEALTH_CHECK_RETRY_INTERVAL:-2}

for i in $(seq 1 $MAX_RETRIES); do
    # Try to curl through the SOCKS5 proxy
    curl --connect-timeout $CHECK_TIMEOUT \
         --socks5-hostname localhost:${SOCKS5_PORT:-1080} \
         -s -f -o /dev/null \
         $CHECK_URL
    
    if [ $? -eq 0 ]; then
        # Connection successful
        exit 0
    fi
    
    # Wait before retrying
    if [ $i -lt $MAX_RETRIES ]; then
        sleep $RETRY_INTERVAL
    fi
done

# All retries failed
exit 1 