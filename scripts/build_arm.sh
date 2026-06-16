#!/bin/bash
# Build PouCon release for ARM (Raspberry Pi) on x86_64 development machine
# Uses Docker with ARM emulation (QEMU)
#
# Target: Raspberry Pi OS Bookworm (64-bit) with Wayland/labwc
#
# Usage:
#   ./scripts/build_arm.sh

set -e

script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../shared_config/docker_deploy.sh
source "$(cd "$script_path/../.." && pwd)/shared_config/docker_deploy.sh"
docker_deploy_init "$script_path"

echo "=== PouCon ARM Build Script ==="
echo ""
echo "Target: Raspberry Pi OS Bookworm (64-bit)"
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

if [ ! -f "$PROJECT_ROOT/mix.exs" ]; then
    echo "ERROR: mix.exs not found at $PROJECT_ROOT"
    exit 1
fi

if [ ! -f "$PROJECT_ROOT/Dockerfile.arm" ]; then
    echo "ERROR: Dockerfile.arm not found at $PROJECT_ROOT"
    exit 1
fi

ensure_global_assets
stage_dockerignore

echo "Building PouCon for ARM64 (Raspberry Pi 3B+/4/CM4)..."
echo "Using: Dockerfile.arm"
echo "This will take 10-20 minutes..."
echo ""

rm -rf "$PROJECT_ROOT/output"
mkdir -p "$PROJECT_ROOT/output"

# Recreate buildx builder fresh to prevent export-phase hangs
# The docker-container driver accumulates state that causes hangs
echo "Recreating buildx builder..."
docker buildx stop multiarch 2>/dev/null || true
docker buildx rm multiarch 2>/dev/null || true
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap

# Build for ARM64 with timeout to prevent indefinite hangs
# --provenance=false prevents BuildKit attestation hangs during local export
echo "Starting ARM64 build (timeout: 30 minutes)..."
timeout 1800 docker buildx build \
  --platform linux/arm64 \
  --output type=local,dest="$PROJECT_ROOT/output" \
  --provenance=false \
  -f "$PROJECT_ROOT/Dockerfile.arm" \
  --progress=plain \
  "$MONOREPO_ROOT"

BUILD_STATUS=$?
if [ $BUILD_STATUS -eq 124 ]; then
    echo ""
    echo "ERROR: Build timed out after 30 minutes"
    echo "Try resetting the buildx builder:"
    echo "  docker buildx stop"
    echo "  docker buildx rm multiarch"
    echo "  docker buildx create --name multiarch --driver docker-container --use"
    echo "  docker buildx inspect --bootstrap"
    exit 1
elif [ $BUILD_STATUS -ne 0 ]; then
    echo ""
    echo "ERROR: Build failed with exit code $BUILD_STATUS"
    exit $BUILD_STATUS
fi

# Check if build succeeded
if [ ! -f "$PROJECT_ROOT/output/pou_con_release_arm.tar.gz" ]; then
    echo "ERROR: Build failed - release tarball not found"
    exit 1
fi

echo ""
echo "=== Build Complete! ==="
echo ""
echo "Target: Raspberry Pi OS Bookworm (64-bit)"
echo "Release: $PROJECT_ROOT/output/pou_con_release_arm.tar.gz"
echo "Size: $(du -h "$PROJECT_ROOT/output/pou_con_release_arm.tar.gz" | cut -f1)"

# Check for runtime debs
if [ -f "$PROJECT_ROOT/output/runtime_debs_arm.tar.gz" ]; then
    echo ""
    echo "Runtime dependencies: $PROJECT_ROOT/output/runtime_debs_arm.tar.gz"
    echo "Size: $(du -h "$PROJECT_ROOT/output/runtime_debs_arm.tar.gz" | cut -f1)"
    echo "  ✓ Offline deployment enabled"
else
    echo ""
    echo "⚠ Runtime dependencies not found - deployment will require internet"
fi

echo ""
echo "Next step: Create deployment package"
echo "  ./scripts/create_deployment_package.sh"
