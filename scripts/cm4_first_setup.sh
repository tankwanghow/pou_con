#!/bin/bash
# First-time setup script for PouCon on Raspberry Pi CM4 (Bookworm)
# Run this script ON the CM4 after transferring the release package

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo ""
echo "═══════════════════════════════════════════"
echo "  PouCon CM4 First-Time Setup"
echo "  For Raspberry Pi OS Bookworm (64-bit)"
echo "═══════════════════════════════════════════"
echo ""

# 1. Install dependencies
# Note: Erlang/OTP is NOT needed - the release includes ERTS (embedded runtime)
# We only need SQLite for database and openssl for key generation
print_step "Installing system dependencies..."
sudo apt update
sudo apt install -y \
    sqlite3 \
    libsqlite3-dev \
    openssl

echo "✓ Dependencies installed"
echo "  (Erlang not required - release includes embedded runtime)"

# 2. Check for release package
if [ ! -f /tmp/pou_con_release_arm.tar.gz ] && [ ! -f ~/pou_con_release_arm.tar.gz ]; then
    echo ""
    echo -e "${YELLOW}Release package not found.${NC}"
    echo "Please transfer pou_con_release_arm.tar.gz to this machine first:"
    echo "  scp pou_con_release_arm.tar.gz pi@<cm4-ip>:/home/pi/"
    echo ""
    echo "Then run this script again."
    exit 1
fi

# Use package from /tmp if exists, otherwise from home
RELEASE_PKG="/tmp/pou_con_release_arm.tar.gz"
if [ ! -f "$RELEASE_PKG" ]; then
    RELEASE_PKG=~/pou_con_release_arm.tar.gz
fi

# 3. Extract release
print_step "Extracting release to /opt/pou_con..."
sudo mkdir -p /opt/pou_con
sudo tar -xzf "$RELEASE_PKG" -C /opt/pou_con
sudo chown -R pi:pi /opt/pou_con
sudo mkdir -p /opt/pou_con/data
sudo mkdir -p /var/log/pou_con
sudo chown -R pi:pi /var/log/pou_con

echo "✓ Release extracted"

# 4. Create .env file
print_step "Creating environment configuration..."

if [ -f /opt/pou_con/.env ]; then
    echo "✓ .env already exists, skipping"
else
    SECRET_KEY=$(openssl rand -base64 48)
    cat > /opt/pou_con/.env << EOF
# Database
DATABASE_PATH=/opt/pou_con/data/pou_con_prod.db

# Phoenix
SECRET_KEY_BASE=${SECRET_KEY}
PHX_HOST=localhost
PORT=4000

# Environment
MIX_ENV=prod

# Hardware (0 = real hardware, 1 = simulation)
SIMULATE_DEVICES=0

# System identification (optional)
FARM_NAME="My Poultry Farm"
HOUSE_NUMBER="House 1"
EOF
    echo "✓ Created .env file"
fi

# 5. Set up serial port permissions
print_step "Configuring serial port access..."
sudo usermod -a -G dialout pi

echo "✓ Added user to dialout group"

# 6. Initialize database
print_step "Initializing database..."
cd /opt/pou_con
export $(cat .env | xargs)
./bin/pou_con eval "PouCon.Release.migrate()"

echo "✓ Database initialized"

# 7. Create systemd service
print_step "Creating systemd service..."

sudo tee /etc/systemd/system/pou_con.service > /dev/null << 'EOF'
[Unit]
Description=PouCon Industrial Control System
After=network.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/opt/pou_con
EnvironmentFile=/opt/pou_con/.env
ExecStart=/opt/pou_con/bin/pou_con start
ExecStop=/opt/pou_con/bin/pou_con stop
Restart=always
RestartSec=5
StandardOutput=append:/var/log/pou_con/stdout.log
StandardError=append:/var/log/pou_con/stderr.log

# Security
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable pou_con

echo "✓ Systemd service created and enabled"

# 8. Set up sudo permissions for time setting (optional)
print_step "Setting up sudo permissions for web-based time management..."

if [ -f /opt/pou_con/scripts/setup_sudo.sh ]; then
    sudo bash /opt/pou_con/scripts/setup_sudo.sh
    echo "✓ Sudo permissions configured"
else
    echo "⚠ setup_sudo.sh not found, skipping (you can run it later)"
fi

# 9. Configure logrotate
print_step "Setting up log rotation..."

sudo tee /etc/logrotate.d/pou_con > /dev/null << 'EOF'
/var/log/pou_con/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 pi pi
    sharedscripts
    postrotate
        systemctl reload pou_con > /dev/null 2>&1 || true
    endscript
}
EOF

echo "✓ Log rotation configured"

# 10. Display system info
echo ""
print_step "System Information:"
echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "  Arch: $(uname -m)"
echo "  Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "  Disk Free: $(df -h /opt/pou_con | awk 'NR==2 {print $4}')"
echo ""

# 11. Check serial ports
print_step "Detected serial ports:"
ls -la /dev/ttyUSB* /dev/ttyAMA* /dev/serial* 2>/dev/null || echo "  No USB serial devices found (check after vendor hardware is connected)"
echo ""

# 12. Start service
print_step "Starting PouCon service..."
sudo systemctl start pou_con
sleep 3

# Check status
if sudo systemctl is-active --quiet pou_con; then
    echo -e "${GREEN}✓ Service started successfully!${NC}"
else
    echo -e "${YELLOW}⚠ Service may not have started. Check logs:${NC}"
    echo "  sudo journalctl -u pou_con -n 50"
fi

echo ""
echo "═══════════════════════════════════════════"
echo -e "${GREEN}  Setup Complete!${NC}"
echo "═══════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Get CM4 IP address: hostname -I"
echo "  2. Access web interface: http://$(hostname -I | awk '{print $1}'):4000"
echo "  3. Default login: admin / admin123 (change immediately!)"
echo ""
echo "Configuration workflow:"
echo "  Admin → Ports → Add RS485/Modbus ports"
echo "  Admin → Devices → Add Modbus devices"
echo "  Admin → Equipment → Create equipment and link to devices"
echo "  Admin → Interlocks → Define safety rules"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status pou_con     # Check service status"
echo "  sudo journalctl -u pou_con -f     # View logs"
echo "  sudo systemctl restart pou_con    # Restart service"
echo ""
echo "⚠ IMPORTANT: You need to log out and log back in for serial port"
echo "   permissions to take effect (dialout group membership)."
echo ""
echo "Optional: Run 'sudo raspi-config' to:"
echo "  - Disable GUI (saves RAM): System → Boot to Console"
echo "  - Enable VNC for remote access"
echo "  - Set timezone and locale"
echo ""
