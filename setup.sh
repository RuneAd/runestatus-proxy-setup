#!/bin/bash
#
# RuneStatus Proxy Droplet Setup Script
# Fetched from GitHub for easy updates
#
# Usage: 
#   curl -sSL https://raw.githubusercontent.com/RuneAd/runestatus-proxy-setup/main/setup.sh | bash -s RAILWAY_IP
#
# Example:
#   curl -sSL https://raw.githubusercontent.com/RuneAd/runestatus-proxy-setup/main/setup.sh | bash -s 162.220.232.99

set -e

# Make everything non-interactive
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Configuration
RAILWAY_IP="${1}"
REPO_URL="https://raw.githubusercontent.com/RuneAd/runestatus-proxy-setup/main"
VERSION="1.0.1"

# Validate Railway IP provided
if [ -z "$RAILWAY_IP" ]; then
    echo "❌ Error: Railway IP not provided"
    echo "Usage: $0 <RAILWAY_IP>"
    echo "Example: $0 162.220.232.99"
    exit 1
fi

echo "🚀 RuneStatus Proxy Setup v${VERSION}"
echo "========================================"
echo "Railway IP: $RAILWAY_IP"
echo "Repository: RuneAd/runestatus-proxy-setup"
echo ""

# Disable interactive prompts for package configuration
echo "📦 Configuring non-interactive mode..."
export DEBIAN_FRONTEND=noninteractive

# Update system (non-interactive, skip problematic upgrades)
echo "📦 Updating package lists..."
apt-get update -qq

# Only upgrade security packages, skip interactive ones
echo "📦 Installing security updates..."
apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    -o DPkg::options::="--force-confmiss" \
    || echo "⚠️  Some packages skipped (non-critical)"

# Install required packages
echo "📦 Installing Squid and UFW..."
apt-get install -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    squid ufw curl

# Backup original Squid config
if [ -f /etc/squid/squid.conf ]; then
    cp /etc/squid/squid.conf /etc/squid/squid.conf.backup.$(date +%s)
fi

# Download and install Squid configuration
echo "⚙️  Configuring Squid from GitHub..."
cat > /etc/squid/squid.conf << EOF
# RuneStatus Proxy - Secure Configuration
# Generated on: $(date)
# Railway IP: $RAILWAY_IP

# ACL for Railway app
acl railway_app src $RAILWAY_IP

# Standard ports
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

# Deny requests to unsafe ports
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# Allow localhost
http_access allow localhost

# ONLY allow Railway app
http_access allow railway_app

# Deny everything else
http_access deny all

# Squid listening port
http_port 3128

# Cache settings
coredump_dir /var/spool/squid

# Refresh patterns
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

# Logging
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
EOF

# Validate Squid configuration
echo "✅ Validating Squid configuration..."
squid -k parse || {
    echo "❌ Squid configuration error!"
    exit 1
}

# Restart Squid
echo "🔄 Restarting Squid..."
systemctl restart squid
systemctl enable squid

# Configure firewall
echo "🔥 Configuring UFW firewall..."
ufw --force reset
ufw allow 22/tcp
ufw allow from $RAILWAY_IP to any port 3128
ufw deny 3128/tcp
ufw --force enable

# Install auto-updater
echo "📥 Installing auto-updater..."
curl -sSL ${REPO_URL}/install-updater.sh | bash -s "$RAILWAY_IP"

# Save setup metadata
cat > /root/runestatus-setup.json << EOF
{
  "version": "${VERSION}",
  "railway_ip": "$RAILWAY_IP",
  "installed_at": "$(date -Iseconds)",
  "repository": "RuneAd/runestatus-proxy-setup"
}
EOF

# Get external IP
EXTERNAL_IP=$(curl -s ifconfig.me || echo "unknown")

# Success message
echo ""
echo "✅ Setup Complete!"
echo "===================="
echo ""
echo "📊 Squid Status:"
systemctl is-active squid && echo "   ✓ Running" || echo "   ✗ Not running"
echo ""
echo "🔒 Firewall Rules:"
ufw status numbered | head -n 10
echo ""
echo "🌐 Proxy Details:"
echo "   External IP: $EXTERNAL_IP"
echo "   Proxy Port: 3128"
echo "   Allowed IP: $RAILWAY_IP"
echo ""
echo "📝 Next Steps:"
echo "   1. Add '$EXTERNAL_IP:3128' to RuneStatus admin panel"
echo "   2. Auto-updater installed - checks GitHub every hour"
echo "   3. View logs: tail -f /var/log/squid/access.log"
echo ""
