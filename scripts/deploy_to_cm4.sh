#!/bin/bash
# Deploy PouCon to Raspberry Pi CM4 (Bookworm)
# Usage: ./scripts/deploy_to_cm4.sh <cm4-ip-address> [--build-only]
#
# This script uses Docker buildx with QEMU emulation to cross-compile
# for ARM64 (Raspberry Pi 3B+/4/CM4).

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CM4_IP=$1
BUILD_ONLY=$2
PROJECT_DIR=$(pwd)
RELEASE_TAR="pou_con_release_arm.tar.gz"
REMOTE_USER="pi"
REMOTE_DIR="/opt/pou_con"

# Functions
print_step() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

check_requirements() {
    print_step "Checking requirements..."

    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        print_error "Run: ./scripts/setup_docker_arm.sh"
        exit 1
    fi

    if ! docker buildx version &> /dev/null; then
        print_error "Docker buildx is not available."
        print_error "Run: ./scripts/setup_docker_arm.sh"
        exit 1
    fi

    if [ -z "$CM4_IP" ] && [ "$BUILD_ONLY" != "--build-only" ]; then
        print_error "Usage: $0 <cm4-ip-address> [--build-only]"
        echo "Example: $0 192.168.1.100"
        echo "Build only: $0 --build-only"
        exit 1
    fi

    echo "✓ Docker and buildx found"
}

build_release() {
    print_step "Building ARM64 release using Docker buildx..."
    print_step "This uses Dockerfile.arm with cross-compilation (10-20 minutes)..."

    # Clean previous builds
    rm -rf output
    mkdir -p output

    # Build for ARM64 using Dockerfile.arm and buildx
    docker buildx build \
        --platform linux/arm64 \
        --output type=local,dest=./output \
        -f Dockerfile.arm \
        --progress=plain \
        .

    # Check if build succeeded
    if [ ! -f "output/$RELEASE_TAR" ]; then
        print_error "Build failed - release tarball not found"
        exit 1
    fi

    # Move to project root for easier access
    cp "output/$RELEASE_TAR" "./$RELEASE_TAR"

    echo "✓ Release built: $RELEASE_TAR ($(du -h $RELEASE_TAR | cut -f1))"
}

deploy_to_cm4() {
    print_step "Deploying to CM4 at $CM4_IP..."

    # Check if CM4 is reachable
    if ! ping -c 1 -W 2 "$CM4_IP" &> /dev/null; then
        print_warning "Cannot ping $CM4_IP. Continuing anyway..."
    fi

    # Transfer release
    print_step "Transferring release to CM4..."
    scp "$RELEASE_TAR" "${REMOTE_USER}@${CM4_IP}:/tmp/"

    # Deploy on CM4
    print_step "Extracting and configuring on CM4..."
    ssh "${REMOTE_USER}@${CM4_IP}" bash << 'ENDSSH'
        set -e

        # Service user - all pou_con files and processes run as this user
        SERVICE_USER="pou_con"

        echo "Stopping service if running..."
        sudo systemctl stop pou_con 2>/dev/null || true

        echo "Creating service user if needed..."
        if ! id "$SERVICE_USER" &>/dev/null; then
            # Create as regular user with home directory (needed for kiosk/desktop)
            sudo useradd -m -s /bin/bash -d "/home/$SERVICE_USER" "$SERVICE_USER"
            # Set a random password (user won't need to login with password - auto-login)
            echo "$SERVICE_USER:$(openssl rand -base64 32)" | sudo chpasswd
            echo "Created user: $SERVICE_USER with home directory"
        else
            # Ensure home directory exists for existing user
            if [ ! -d "/home/$SERVICE_USER" ]; then
                sudo mkdir -p "/home/$SERVICE_USER"
                sudo chown "$SERVICE_USER:$SERVICE_USER" "/home/$SERVICE_USER"
                echo "Created missing home directory for $SERVICE_USER"
            fi
        fi

        # Add to required groups for hardware and display access
        echo "Configuring user groups..."
        sudo usermod -aG dialout "$SERVICE_USER"  # Serial port access (Modbus RTU)
        sudo usermod -aG video "$SERVICE_USER"    # Backlight control (screen blanking)
        sudo usermod -aG input "$SERVICE_USER"    # Touchscreen input
        sudo usermod -aG render "$SERVICE_USER" 2>/dev/null || true  # GPU access
        sudo usermod -aG audio "$SERVICE_USER" 2>/dev/null || true   # Audio (for alerts)
        echo "Added $SERVICE_USER to required groups"

        echo "Backing up current installation..."
        if [ -d /opt/pou_con ]; then
            sudo cp -r /opt/pou_con/data /tmp/pou_con_data_backup 2>/dev/null || true
            sudo cp /opt/pou_con/.env /tmp/pou_con_env_backup 2>/dev/null || true
        fi

        echo "Extracting release..."
        sudo mkdir -p /opt/pou_con
        sudo tar -xzf /tmp/pou_con_release_arm.tar.gz -C /opt/pou_con
        sudo chown -R "$SERVICE_USER:$SERVICE_USER" /opt/pou_con

        echo "Restoring data and config..."
        if [ -d /tmp/pou_con_data_backup ]; then
            sudo cp -r /tmp/pou_con_data_backup /opt/pou_con/data
            sudo chown -R "$SERVICE_USER:$SERVICE_USER" /opt/pou_con/data
        else
            sudo mkdir -p /opt/pou_con/data
            sudo chown "$SERVICE_USER:$SERVICE_USER" /opt/pou_con/data
        fi

        if [ -f /tmp/pou_con_env_backup ]; then
            sudo cp /tmp/pou_con_env_backup /opt/pou_con/.env
            sudo chown "$SERVICE_USER:$SERVICE_USER" /opt/pou_con/.env
        fi

        echo "Fixing SSL key permissions..."
        if [ -f /etc/pou_con/ssl/server.key ]; then
            sudo chown "$SERVICE_USER:$SERVICE_USER" /etc/pou_con/ssl/server.key
            echo "SSL key ownership set to $SERVICE_USER"
        fi

        echo "Running migrations..."
        cd /opt/pou_con
        if [ -f .env ]; then
            # Run migrations as the service user
            sudo -u "$SERVICE_USER" bash -c 'export $(cat /opt/pou_con/.env | xargs) && /opt/pou_con/bin/pou_con eval "PouCon.Release.migrate()"' || echo "Migration failed or no new migrations"
            echo "Running seeds..."
            sudo -u "$SERVICE_USER" bash -c 'export $(cat /opt/pou_con/.env | xargs) && /opt/pou_con/bin/pou_con eval "PouCon.Release.seed()"' || echo "Seeding failed or already seeded"
        else
            echo "WARNING: No .env file found. Skipping migrations."
        fi

        # Run setup_sudo.sh BEFORE starting service (service needs sudo permissions for screen control)
        echo "Configuring sudo permissions..."
        if [ -f /opt/pou_con/setup_sudo.sh ]; then
            sudo bash /opt/pou_con/setup_sudo.sh
            echo "Sudo permissions configured"
        else
            echo "WARNING: setup_sudo.sh not found. Web-based time/reboot/screen control may not work."
        fi

        echo "Starting service..."
        sudo systemctl start pou_con 2>/dev/null || echo "Service not configured. Run setup manually."

        echo "Configuring screen saver (3 minute idle timeout)..."
        IDLE_SECONDS=180
        DISPLAY_USER="pi"  # User running the Wayland display (labwc)

        # Detect backlight device
        BACKLIGHT_PATH=""
        for bl in lcd_backlight 10-0045 rpi_backlight backlight; do
            if [ -f "/sys/class/backlight/$bl/brightness" ]; then
                BACKLIGHT_PATH="/sys/class/backlight/$bl"
                echo "Found backlight device: $bl"
                break
            fi
        done

        # Configure Wayland (labwc) screen blanking via swayidle
        echo "Configuring screen blanking for Wayland (labwc)..."

        if [ -f /opt/pou_con/scripts/set_screen_timeout.sh ]; then
            sudo /opt/pou_con/scripts/set_screen_timeout.sh $IDLE_SECONDS $DISPLAY_USER
            echo "Screen timeout configured via set_screen_timeout.sh"
        elif [ -n "$BACKLIGHT_PATH" ]; then
            # Manual labwc autostart configuration
            AUTOSTART_FILE="/home/$DISPLAY_USER/.config/labwc/autostart"
            MAX_BRIGHT=$(cat "$BACKLIGHT_PATH/max_brightness" 2>/dev/null || echo "5")

            sudo mkdir -p "$(dirname "$AUTOSTART_FILE")"
            if [ -f "$AUTOSTART_FILE" ]; then
                sudo sed -i '/swayidle/d' "$AUTOSTART_FILE"
            fi
            echo "swayidle -w timeout $IDLE_SECONDS 'echo 0 > $BACKLIGHT_PATH/brightness' resume 'echo $MAX_BRIGHT > $BACKLIGHT_PATH/brightness' &" | sudo tee -a "$AUTOSTART_FILE" > /dev/null
            sudo chown "$DISPLAY_USER:$DISPLAY_USER" "$AUTOSTART_FILE"
            echo "Configured labwc autostart with swayidle"
        else
            echo "WARNING: No backlight device found. Screen blanking may not work."
        fi

        # Ensure backlight is at max
        if [ -n "$BACKLIGHT_PATH" ]; then
            MAX_BRIGHT=$(cat "$BACKLIGHT_PATH/max_brightness")
            echo $MAX_BRIGHT | sudo tee "$BACKLIGHT_PATH/brightness" > /dev/null
            echo "Set backlight to maximum ($MAX_BRIGHT)"
        fi

        echo "Deployment complete!"

        # Cleanup
        rm -f /tmp/pou_con_release_arm.tar.gz
        sudo rm -rf /tmp/pou_con_data_backup /tmp/pou_con_env_backup
ENDSSH

    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo ""
    echo "Access PouCon at: http://${CM4_IP}:4000"
    echo ""
    echo "To check status:"
    echo "  ssh ${REMOTE_USER}@${CM4_IP} 'sudo systemctl status pou_con'"
    echo ""
    echo "To view logs:"
    echo "  ssh ${REMOTE_USER}@${CM4_IP} 'sudo journalctl -u pou_con -f'"
}

# Main execution
main() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  PouCon CM4 Deployment Script"
    echo "  Target: Raspberry Pi OS Bookworm (64-bit)"
    echo "═══════════════════════════════════════════"
    echo ""

    check_requirements
    build_release

    if [ "$BUILD_ONLY" == "--build-only" ]; then
        print_step "Build complete. Skipping deployment (--build-only flag)."
        echo "Release package: $RELEASE_TAR"
        echo "To deploy manually:"
        echo "  scp $RELEASE_TAR ${REMOTE_USER}@<cm4-ip>:/tmp/"
        exit 0
    fi

    deploy_to_cm4

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Deployment Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
}

main
