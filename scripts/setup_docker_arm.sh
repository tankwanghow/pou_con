#!/bin/bash
# One-time setup for Docker ARM builds
# Run this once on your development machine

set -e

echo "=== Docker ARM Build Setup ==="
echo ""
echo "This script will:"
echo "  1. Check Docker installation"
echo "  2. Install QEMU for ARM emulation"
echo "  3. Setup Docker buildx for multi-arch builds"
echo ""

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "WARNING: This script is designed for Linux"
    echo "For macOS, Docker Desktop already includes ARM support"
    exit 0
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing Docker..."
    echo "You may need to enter your password for sudo commands"
    echo ""

    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh

    echo ""
    echo "Adding current user to docker group..."
    sudo usermod -aG docker $USER

    echo ""
    echo "IMPORTANT: You need to log out and back in for docker group to take effect"
    echo "After logging back in, run this script again"
    exit 0
fi

# Check if user is in docker group
if ! groups | grep -q docker; then
    echo "Adding current user to docker group..."
    sudo usermod -aG docker $USER

    echo ""
    echo "IMPORTANT: You need to log out and back in for docker group to take effect"
    echo "After logging back in, run this script again"
    exit 0
fi

# Install QEMU for ARM emulation
echo "Installing QEMU for ARM emulation..."
if command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y qemu-user-static
elif command -v dnf &> /dev/null; then
    sudo dnf install -y qemu-user-static
elif command -v yum &> /dev/null; then
    sudo yum install -y qemu-user-static
else
    echo "WARNING: Could not detect package manager"
    echo "Please install qemu-user-static manually"
fi

# Setup Docker buildx
echo ""
echo "Setting up Docker buildx for multi-architecture builds..."

# Check if multiarch builder already exists
if docker buildx ls | grep -q multiarch; then
    echo "Builder 'multiarch' already exists, removing..."
    docker buildx rm multiarch || true
fi

# Create new builder
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "You can now build ARM releases on this x86_64 machine:"
echo "  ./scripts/build_arm.sh"
echo ""
echo "To verify setup:"
echo "  docker buildx ls"
echo ""
echo "Expected output should show 'multiarch' builder with linux/arm64 platform"
