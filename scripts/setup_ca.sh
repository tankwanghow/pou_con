#!/bin/bash
#
# PouCon Certificate Authority Setup
# Run this ONCE on your development machine to create a CA for all houses.
# The ca.crt must be installed on all user devices (mobile/iPad).
#
# Usage: ./scripts/setup_ca.sh
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory (works even when called from different locations)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CA_DIR="$PROJECT_DIR/priv/ssl/ca"

echo ""
echo "═══════════════════════════════════════════"
echo "  PouCon Certificate Authority Setup"
echo "═══════════════════════════════════════════"
echo ""

# Check if CA already exists
if [ -f "$CA_DIR/ca.crt" ]; then
    echo -e "${YELLOW}CA certificate already exists at:${NC}"
    echo "  $CA_DIR/ca.crt"
    echo ""
    read -p "Regenerate CA? This will invalidate ALL existing certificates! (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Keeping existing CA."
        exit 0
    fi
    rm -rf "$CA_DIR"
fi

mkdir -p "$CA_DIR"

# Prompt for organization details
echo "Enter CA details (press Enter for defaults):"
echo ""

read -p "Organization name [PouCon Farm]: " ORG_NAME
ORG_NAME=${ORG_NAME:-"PouCon Farm"}

read -p "Country code (2 letters) [MY]: " COUNTRY
COUNTRY=${COUNTRY:-"MY"}

read -p "State/Province [Selangor]: " STATE
STATE=${STATE:-"Selangor"}

read -p "City [Kuala Lumpur]: " CITY
CITY=${CITY:-"Kuala Lumpur"}

echo ""
echo "Generating CA..."

# Generate CA private key (4096 bits for long-term security)
openssl genrsa -out "$CA_DIR/ca.key" 4096 2>/dev/null

# Generate CA certificate (valid 10 years)
openssl req -x509 -new -nodes \
    -key "$CA_DIR/ca.key" \
    -sha256 \
    -days 3650 \
    -out "$CA_DIR/ca.crt" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG_NAME/CN=$ORG_NAME Local CA"

# Set permissions
chmod 600 "$CA_DIR/ca.key"
chmod 644 "$CA_DIR/ca.crt"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  CA Setup Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "Files created:"
echo -e "  ${CYAN}CA Certificate:${NC} $CA_DIR/ca.crt"
echo -e "  ${CYAN}CA Private Key:${NC} $CA_DIR/ca.key (KEEP SECRET!)"
echo ""
echo "═══════════════════════════════════════════"
echo "  Install CA on User Devices (ONE TIME)"
echo "═══════════════════════════════════════════"
echo ""
echo -e "${CYAN}iOS/iPadOS:${NC}"
echo "  1. Transfer ca.crt to device (AirDrop, email, or USB)"
echo "  2. Open the file → 'Profile Downloaded' notification"
echo "  3. Settings → General → VPN & Device Management"
echo "  4. Tap the profile and Install"
echo "  5. Settings → General → About → Certificate Trust Settings"
echo "  6. Enable full trust for '$ORG_NAME Local CA'"
echo ""
echo -e "${CYAN}Android:${NC}"
echo "  1. Copy ca.crt to device"
echo "  2. Settings → Security → Install from storage"
echo "  3. Select ca.crt, name it '$ORG_NAME'"
echo "  4. Install as 'CA certificate'"
echo ""
echo -e "${CYAN}Windows:${NC}"
echo "  1. Double-click ca.crt"
echo "  2. Install Certificate → Local Machine → Trusted Root CA"
echo ""
echo -e "${CYAN}macOS:${NC}"
echo "  1. Double-click ca.crt to add to Keychain"
echo "  2. Keychain Access → Find certificate → Get Info"
echo "  3. Trust → Always Trust"
echo ""
echo "═══════════════════════════════════════════"
echo ""
echo "Next: Run ./scripts/setup_house.sh on each Raspberry Pi"
echo "      to generate house-specific SSL certificates."
echo ""
