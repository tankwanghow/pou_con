#!/bin/bash
# Build PouCon release for ARM (Raspberry Pi) on x86_64 development machine
# Uses Docker with ARM emulation (QEMU)

set -e

echo "=== PouCon ARM Build Script ==="
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

echo "Building PouCon for ARM64 (Raspberry Pi 3B+/4)..."
echo "This will take 10-20 minutes..."
echo ""

# Clean previous output
rm -rf output
mkdir -p output

# Build for ARM64
docker buildx build \
  --platform linux/arm64 \
  --output type=local,dest=./output \
  -f Dockerfile.arm \
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
echo "Release: output/pou_con_release_arm.tar.gz"
echo "Size: $(du -h output/pou_con_release_arm.tar.gz | cut -f1)"
echo ""
echo "Next step: Create deployment package"
echo "  ./scripts/create_deployment_package.sh"
