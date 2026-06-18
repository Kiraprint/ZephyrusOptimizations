#!/bin/bash
# Quick command to restore and re-run setup

echo "Restoring config and running setup..."
echo ""

# Restore config
if [[ -f /etc/howdy/config.ini.backup ]]; then
    sudo cp /etc/howdy/config.ini.backup /etc/howdy/config.ini
    echo "✓ Config restored"
else
    echo "✗ No backup found at /etc/howdy/config.ini.backup"
    exit 1
fi

echo ""
echo "Running setup script..."
echo ""

# Run setup
./setup-howdy-kde.sh
