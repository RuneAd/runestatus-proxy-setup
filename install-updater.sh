#!/bin/bash
#
# Install auto-updater for RuneStatus proxy
# This creates a systemd timer that checks GitHub for updates hourly

set -e

RAILWAY_IP="${1}"
REPO_URL="https://raw.githubusercontent.com/RuneAd/runestatus-proxy-setup/main"

if [ -z "$RAILWAY_IP" ]; then
    echo "❌ Error: Railway IP required"
    exit 1
fi

echo "📦 Installing auto-updater..."

# Create update check script
cat > /usr/local/bin/runestatus-update-check << 'SCRIPT_EOF'
#!/bin/bash
#
# Auto-update checker for RuneStatus proxy
# Runs every hour via systemd timer

set -e

REPO_URL="https://raw.githubusercontent.com/RuneAd/runestatus-proxy-setup/main"
RAILWAY_IP_FILE="/root/runestatus-setup.json"
LOG_FILE="/var/log/runestatus-updater.log"

# Function to log messages
log() {
    echo "[$(date -Iseconds)] $1" | tee -a "$LOG_FILE"
}

log "🔍 Checking for RuneStatus proxy updates..."

# Read Railway IP from metadata
if [ -f "$RAILWAY_IP_FILE" ]; then
    RAILWAY_IP=$(grep -oP '"railway_ip":\s*"\K[^"]+' "$RAILWAY_IP_FILE")
else
    log "⚠️  Railway IP metadata not found, skipping update"
    exit 0
fi

# Download latest setup script to temp location
TEMP_SCRIPT="/tmp/runestatus-setup-new.sh"
curl -sSL ${REPO_URL}/setup.sh -o "$TEMP_SCRIPT" || {
    log "❌ Failed to download update"
    exit 1
}

# Check if script changed (basic hash comparison)
CURRENT_HASH=$(md5sum /usr/local/bin/runestatus-setup.sh 2>/dev/null | awk '{print $1}' || echo "none")
NEW_HASH=$(md5sum "$TEMP_SCRIPT" | awk '{print $1}')

if [ "$CURRENT_HASH" != "$NEW_HASH" ]; then
    log "📥 New version detected, applying update..."
    
    # Save new version
    cp "$TEMP_SCRIPT" /usr/local/bin/runestatus-setup.sh
    chmod +x /usr/local/bin/runestatus-setup.sh
    
    # Run the updated setup
    bash /usr/local/bin/runestatus-setup.sh "$RAILWAY_IP" >> "$LOG_FILE" 2>&1
    
    log "✅ Update applied successfully!"
else
    log "✓ Already up to date"
fi

# Cleanup
rm -f "$TEMP_SCRIPT"
SCRIPT_EOF

chmod +x /usr/local/bin/runestatus-update-check

# Save initial setup script
curl -sSL ${REPO_URL}/setup.sh -o /usr/local/bin/runestatus-setup.sh
chmod +x /usr/local/bin/runestatus-setup.sh

# Create systemd service
cat > /etc/systemd/system/runestatus-updater.service << 'EOF'
[Unit]
Description=RuneStatus Proxy Update Check
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/runestatus-update-check
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create systemd timer (runs every hour)
cat > /etc/systemd/system/runestatus-updater.timer << 'EOF'
[Unit]
Description=RuneStatus Proxy Update Check Timer
Requires=runestatus-updater.service

[Timer]
# Run 5 minutes after boot
OnBootSec=5min
# Then every hour
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer
systemctl daemon-reload
systemctl enable runestatus-updater.timer
systemctl start runestatus-updater.timer

echo "✅ Auto-updater installed!"
echo "   - Checks GitHub every hour for updates"
echo "   - Logs: /var/log/runestatus-updater.log"
echo "   - Status: systemctl status runestatus-updater.timer"
