#!/bin/bash
# Reset Docker buildx builder to fix hanging builds
#
# Use this when build_arm.sh hangs at "exporting to client directory"
#
# Usage:
#   ./scripts/reset_docker_buildx.sh

set -e

echo "=== Resetting Docker Buildx Builder ==="
echo ""

# Stop and remove existing builder
echo "Stopping existing builder..."
docker buildx stop 2>/dev/null || true

echo "Removing existing builder..."
docker buildx rm multiarch 2>/dev/null || true

# Clean up Docker resources
echo "Pruning Docker build cache..."
docker builder prune -af 2>/dev/null || true

echo "Pruning unused Docker resources..."
docker system prune -f 2>/dev/null || true

# Recreate the builder
echo ""
echo "Creating fresh buildx builder..."
docker buildx create --name multiarch --driver docker-container --use

echo "Bootstrapping builder (this downloads QEMU)..."
docker buildx inspect --bootstrap

echo ""
echo "=== Buildx Reset Complete ==="
echo ""
echo "You can now run: ./scripts/build_arm.sh"
