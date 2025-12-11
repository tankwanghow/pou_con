#!/bin/bash
# Deploy PouCon to Raspberry Pi CM4 (Bookworm)
# Usage: ./scripts/deploy_to_cm4.sh <cm4-ip-address> [--build-only]

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
RELEASE_TAR="pou_con_release.tar.gz"
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
        exit 1
    fi

    if [ -z "$CM4_IP" ] && [ "$BUILD_ONLY" != "--build-only" ]; then
        print_error "Usage: $0 <cm4-ip-address> [--build-only]"
        echo "Example: $0 192.168.1.100"
        echo "Build only: $0 - --build-only"
        exit 1
    fi

    echo "✓ Docker found"
}

build_release() {
    print_step "Building release with Bookworm Docker container..."

    # Clean previous builds
    rm -f "$RELEASE_TAR"

    # Build using Bookworm container to match CM4
    docker run -it --rm \
        -v "$PROJECT_DIR:/app" \
        -w /app \
        hexpm/elixir:1.15.7-erlang-26.1.2-debian-bookworm-20231009-slim \
        bash -c "
            set -e
            echo 'Installing Hex and Rebar...'
            mix local.hex --force
            mix local.rebar --force

            echo 'Fetching dependencies...'
            mix deps.get --only prod

            echo 'Building assets...'
            MIX_ENV=prod mix assets.deploy

            echo 'Creating release...'
            MIX_ENV=prod mix release

            echo 'Release build complete!'
        "

    # Package release
    print_step "Packaging release..."
    tar -czf "$RELEASE_TAR" -C _build/prod/rel/pou_con .

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

        echo "Stopping service if running..."
        sudo systemctl stop pou_con 2>/dev/null || true

        echo "Backing up current installation..."
        if [ -d /opt/pou_con ]; then
            sudo cp -r /opt/pou_con/data /tmp/pou_con_data_backup 2>/dev/null || true
            sudo cp /opt/pou_con/.env /tmp/pou_con_env_backup 2>/dev/null || true
        fi

        echo "Extracting release..."
        sudo mkdir -p /opt/pou_con
        sudo tar -xzf /tmp/pou_con_release.tar.gz -C /opt/pou_con
        sudo chown -R pi:pi /opt/pou_con

        echo "Restoring data and config..."
        if [ -d /tmp/pou_con_data_backup ]; then
            sudo cp -r /tmp/pou_con_data_backup /opt/pou_con/data
            sudo chown -R pi:pi /opt/pou_con/data
        else
            mkdir -p /opt/pou_con/data
        fi

        if [ -f /tmp/pou_con_env_backup ]; then
            sudo cp /tmp/pou_con_env_backup /opt/pou_con/.env
            sudo chown pi:pi /opt/pou_con/.env
        fi

        echo "Running migrations..."
        cd /opt/pou_con
        if [ -f .env ]; then
            export $(cat .env | xargs)
            ./bin/pou_con eval "PouCon.Release.migrate()" || echo "Migration failed or no new migrations"
        else
            echo "WARNING: No .env file found. Skipping migrations."
        fi

        echo "Starting service..."
        sudo systemctl start pou_con 2>/dev/null || echo "Service not configured. Run setup manually."

        echo "Deployment complete!"

        # Cleanup
        rm -f /tmp/pou_con_release.tar.gz
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
