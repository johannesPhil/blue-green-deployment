#!/bin/sh
set -e

# Determine backup pool based on active pool
if [ "$ACTIVE_POOL" = "blue" ]; then
    export BACKUP_POOL="green"
else
    export BACKUP_POOL="blue"
fi

echo "Active Pool: $ACTIVE_POOL"
echo "Backup Pool: $BACKUP_POOL"
echo "App Port: $APP_PORT"

# Substitute environment variables in nginx config
envsubst '${ACTIVE_POOL} ${BACKUP_POOL} ${APP_PORT}' \
    < /etc/nginx/nginx.conf.template \
    > /etc/nginx/nginx.conf

# Test the configuration
nginx -t

# Start nginx in foreground
exec nginx -g 'daemon off;'