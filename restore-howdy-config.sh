#!/bin/bash
#
# Restore Howdy config from backup
#

set -e

echo "Restoring Howdy config from backup..."

if [[ -f /etc/howdy/config.ini.backup ]]; then
    sudo cp /etc/howdy/config.ini.backup /etc/howdy/config.ini
    echo "✓ Config restored from /etc/howdy/config.ini.backup"
elif [[ -f /usr/lib/security/howdy/config.ini.backup ]]; then
    sudo cp /usr/lib/security/howdy/config.ini.backup /etc/howdy/config.ini
    echo "✓ Config restored from /usr/lib/security/howdy/config.ini.backup"
else
    echo "✗ No backup found. Reinstalling howdy-bin to get fresh config..."
    paru -S --noconfirm howdy-bin --rebuild
    echo "✓ Fresh config installed"
fi

echo ""
echo "Config has been restored. You can now run ./setup-howdy-kde.sh again"
