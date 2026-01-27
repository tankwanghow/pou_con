#!/bin/bash
#
# PouCon House Setup Script
# Run this on each Raspberry Pi during deployment to:
#   1. Set the house_id
#   2. Generate SSL certificate signed by the CA
#   3. Configure the system hostname
#
# Prerequisites:
#   - CA files (ca.crt, ca.key) must be available
#   - Run as user with sudo access
#
# Usage: ./setup_house.sh
#        ./setup_house.sh --house-id h1  (non-interactive)
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
POUCON_DIR="/etc/pou_con"
SSL_DIR="$POUCON_DIR/ssl"
HOUSE_ID_FILE="$POUCON_DIR/house_id"

# Parse arguments
HOUSE_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --house-id)
            HOUSE_ID="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo "═══════════════════════════════════════════"
echo "  PouCon House Setup"
echo "═══════════════════════════════════════════"
echo ""

# Check for CA files
CA_CRT=""
CA_KEY=""

# Look for CA files in common locations
for dir in "/tmp" "$HOME" "." "./priv/ssl/ca" "/opt/pou_con/ssl/ca"; do
    if [ -f "$dir/ca.crt" ] && [ -f "$dir/ca.key" ]; then
        CA_CRT="$dir/ca.crt"
        CA_KEY="$dir/ca.key"
        break
    fi
done

if [ -z "$CA_CRT" ]; then
    echo -e "${RED}ERROR: CA files not found!${NC}"
    echo ""
    echo "Please copy ca.crt and ca.key to this machine first:"
    echo "  scp priv/ssl/ca/ca.crt priv/ssl/ca/ca.key pi@<this-ip>:/tmp/"
    echo ""
    echo "Then run this script again."
    exit 1
fi

echo -e "Found CA files at: ${CYAN}$(dirname "$CA_CRT")${NC}"
echo ""

# Prompt for house_id if not provided
if [ -z "$HOUSE_ID" ]; then
    # Show current house_id if exists
    if [ -f "$HOUSE_ID_FILE" ]; then
        CURRENT_ID=$(cat "$HOUSE_ID_FILE")
        echo -e "Current house_id: ${CYAN}$CURRENT_ID${NC}"
        echo ""
    fi

    echo "Enter the house identifier for this installation."
    echo "Examples: h1, h2, house1, farm_a, building_north"
    echo ""
    read -p "House ID: " HOUSE_ID
fi

# Validate house_id
if [ -z "$HOUSE_ID" ]; then
    echo -e "${RED}ERROR: House ID cannot be empty${NC}"
    exit 1
fi

# Normalize house_id (lowercase, trim whitespace)
HOUSE_ID=$(echo "$HOUSE_ID" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

# Construct hostname
HOSTNAME="poucon.$HOUSE_ID"

echo ""
echo "Configuration:"
echo -e "  House ID:  ${CYAN}$HOUSE_ID${NC}"
echo -e "  Hostname:  ${CYAN}$HOSTNAME${NC}"
echo -e "  URL:       ${CYAN}https://$HOSTNAME${NC}"
echo ""

read -p "Proceed with this configuration? (Y/n): " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Create directories
echo ""
echo "Creating directories..."
sudo mkdir -p "$POUCON_DIR"
sudo mkdir -p "$SSL_DIR"

# Write house_id file
echo "Writing house_id..."
echo "$HOUSE_ID" | sudo tee "$HOUSE_ID_FILE" > /dev/null
sudo chmod 644 "$HOUSE_ID_FILE"

# Get the Pi's IP address
PI_IP=$(hostname -I | awk '{print $1}')
echo -e "Detected IP address: ${CYAN}$PI_IP${NC}"

# Generate SSL certificate
echo ""
echo "Generating SSL certificate..."

# Create temporary directory for cert generation
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Generate server private key
openssl genrsa -out server.key 2048 2>/dev/null

# Create CSR
openssl req -new -key server.key \
    -out server.csr \
    -subj "/CN=$HOSTNAME/O=PouCon/C=MY"

# Create extension file with SAN (Subject Alternative Names)
cat > server.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $HOSTNAME
DNS.2 = poucon.$HOUSE_ID.local
DNS.3 = localhost
IP.1 = $PI_IP
IP.2 = 127.0.0.1
EOF

# Sign with CA (valid 2 years)
openssl x509 -req -in server.csr \
    -CA "$CA_CRT" -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out server.crt \
    -days 730 \
    -sha256 \
    -extfile server.ext 2>/dev/null

# Copy certificates to proper location
sudo cp server.key "$SSL_DIR/server.key"
sudo cp server.crt "$SSL_DIR/server.crt"
sudo cp "$CA_CRT" "$SSL_DIR/ca.crt"

# Set permissions (pou_con user needs to read the key for HTTPS)
sudo chmod 600 "$SSL_DIR/server.key"
sudo chmod 644 "$SSL_DIR/server.crt"
sudo chmod 644 "$SSL_DIR/ca.crt"

# Service user for pou_con (same as in deploy script)
SERVICE_USER="pou_con"

# Check if service user exists (created by deploy script)
if id "$SERVICE_USER" &>/dev/null; then
    # Key must be readable by pou_con service
    sudo chown "$SERVICE_USER:$SERVICE_USER" "$SSL_DIR/server.key"
    sudo chown root:root "$SSL_DIR/server.crt"
    sudo chown root:root "$SSL_DIR/ca.crt"
    echo "SSL key ownership set to $SERVICE_USER user"
else
    # pou_con user doesn't exist yet, will be created by deploy
    sudo chown -R root:root "$SSL_DIR"
    echo -e "${YELLOW}Note: $SERVICE_USER user not found. Run deploy script first, then re-run this script.${NC}"
    echo -e "${YELLOW}Or manually fix permissions after deploy:${NC}"
    echo "  sudo chown $SERVICE_USER:$SERVICE_USER $SSL_DIR/server.key"
fi

# Cleanup
cd /
rm -rf "$TEMP_DIR"

# Set system hostname (optional but helpful)
echo ""
read -p "Set system hostname to '$HOSTNAME'? (Y/n): " set_hostname
if [[ ! "$set_hostname" =~ ^[Nn]$ ]]; then
    sudo hostnamectl set-hostname "$HOSTNAME"
    echo "System hostname set."
fi

# Update /etc/hosts
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "Adding $HOSTNAME to /etc/hosts..."
    echo "127.0.0.1 $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  House Setup Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "Files created:"
echo "  $HOUSE_ID_FILE"
echo "  $SSL_DIR/server.key"
echo "  $SSL_DIR/server.crt"
echo "  $SSL_DIR/ca.crt"
echo ""
echo "═══════════════════════════════════════════"
echo "  Client Device Setup"
echo "═══════════════════════════════════════════"
echo ""
echo "On each mobile/iPad/laptop that will access this house:"
echo ""
echo -e "${CYAN}1. Install CA certificate (one-time, covers all houses):${NC}"
echo "   Already installed if you set up other houses."
echo ""
echo -e "${CYAN}2. Add hostname to device's /etc/hosts or router DNS:${NC}"
echo "   $PI_IP    $HOSTNAME"
echo ""
echo -e "${CYAN}3. Access the app:${NC}"
echo "   https://$HOSTNAME"
echo ""
echo "═══════════════════════════════════════════"
echo ""
echo "If PouCon is already running, restart it:"
echo "  sudo systemctl restart pou_con"
echo ""
