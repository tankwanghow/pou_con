#!/bin/bash
# Build PouCon release for ARM (Raspberry Pi) on x86_64 development machine
# Uses Docker with ARM emulation (QEMU)
#
# Usage:
#   ./scripts/build_arm.sh              # Build for Debian 12 (Bookworm) - default
#   ./scripts/build_arm.sh --bullseye   # Build for Debian 11 (Bullseye)
#
# Use --bullseye for:
#   - reTerminal DM (ships with Bullseye)
#   - Older Raspberry Pi OS installations
#   - Any device with glibc 2.31

set -e

# Parse arguments
TARGET_OS="bookworm"
DOCKERFILE="Dockerfile.arm"

if [ "$1" = "--bullseye" ]; then
    TARGET_OS="bullseye"
    DOCKERFILE="Dockerfile.arm.bullseye"
elif [ -n "$1" ]; then
    echo "ERROR: Unknown option '$1'"
    echo ""
    echo "Usage: $0 [--bullseye]"
    echo "  --bullseye  Build for Debian 11 (Bullseye) - for reTerminal DM"
    echo "  (default)   Build for Debian 12 (Bookworm)"
    exit 1
fi

echo "=== PouCon ARM Build Script ==="
echo ""
echo "Target OS: Debian $TARGET_OS"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed"
    echo "Install with: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# Check if buildx is available
if ! docker buildx version &> /dev/null; then
    echo "ERROR: Docker buildx is not available"
    echo "Setup with:"
    echo "  docker buildx create --name multiarch --driver docker-container --use"
    echo "  docker buildx inspect --bootstrap"
    exit 1
fi

# Check if running in project root
if [ ! -f "mix.exs" ]; then
    echo "ERROR: Must run from project root (where mix.exs is located)"
    exit 1
fi

# Check if Dockerfile exists
if [ ! -f "$DOCKERFILE" ]; then
    echo "ERROR: $DOCKERFILE not found"
    exit 1
fi

echo "Building PouCon for ARM64 (Raspberry Pi 3B+/4)..."
echo "Using: $DOCKERFILE"
echo "This will take 10-20 minutes..."
echo ""

# Clean previous output
rm -rf output
mkdir -p output

# Build for ARM64
docker buildx build \
  --platform linux/arm64 \
  --output type=local,dest=./output \
  -f "$DOCKERFILE" \
  --progress=plain \
  .

# Check if build succeeded
if [ ! -f "output/pou_con_release_arm.tar.gz" ]; then
    echo "ERROR: Build failed - release tarball not found"
    exit 1
fi

echo ""
echo "=== Build Complete! ==="
echo ""
echo "Target OS: Debian $TARGET_OS"
echo "Release: output/pou_con_release_arm.tar.gz"
echo "Size: $(du -h output/pou_con_release_arm.tar.gz | cut -f1)"

# Check for runtime debs
if [ -f "output/runtime_debs_arm.tar.gz" ]; then
    echo ""
    echo "Runtime dependencies: output/runtime_debs_arm.tar.gz"
    echo "Size: $(du -h output/runtime_debs_arm.tar.gz | cut -f1)"
    echo "  ✓ Offline deployment enabled"
else
    echo ""
    echo "⚠ Runtime dependencies not found - deployment will require internet"
fi

echo ""
echo "Next step: Create deployment package"
echo "  ./scripts/create_deployment_package.sh"
