#!/bin/bash
# Quick build and package — app-only changes, no dependency downloads
#
# Use this when ONLY PouCon application code has changed (lib/, priv/, assets/).
# Skips downloading runtime debs and preserves Docker build cache for fast rebuilds.
#
# First build still downloads Elixir deps (mix deps.get), but subsequent builds
# with unchanged mix.exs/mix.lock will use Docker layer cache.
#
# For full builds including debs, use: ./scripts/build_and_package.sh
#
# Usage:
#   ./scripts/build_and_package_quick.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "=== PouCon Quick Build (App-Only) ==="
echo ""
echo "This builds ONLY the PouCon application."
echo "Skips: runtime deb downloads (chromium, swayidle, etc.)"
echo "Skips: buildx builder recreation (preserves Docker cache)"
echo ""
echo "If mix.exs/mix.lock are unchanged, deps are cached too."
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed"
    exit 1
fi

if ! docker buildx version &> /dev/null; then
    echo "ERROR: Docker buildx is not available"
    exit 1
fi

if [ ! -f "mix.exs" ]; then
    echo "ERROR: Must run from project root (where mix.exs is located)"
    exit 1
fi

if [ ! -f "Dockerfile.arm.quick" ]; then
    echo "ERROR: Dockerfile.arm.quick not found"
    exit 1
fi

# Step 1: Build ARM release (quick mode)
echo ""
echo "=== Step 1: Building ARM Release (Quick Mode) ==="

rm -rf output
mkdir -p output

# Recreate buildx builder fresh to prevent export-phase hangs
echo "Recreating buildx builder..."
docker buildx stop multiarch 2>/dev/null || true
docker buildx rm multiarch 2>/dev/null || true
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap

echo "Starting ARM64 quick build (timeout: 30 minutes)..."
timeout 1800 docker buildx build \
  --platform linux/arm64 \
  --output type=local,dest=./output \
  --provenance=false \
  -f Dockerfile.arm.quick \
  --progress=plain \
  .

BUILD_STATUS=$?
if [ $BUILD_STATUS -eq 124 ]; then
    echo ""
    echo "ERROR: Build timed out after 30 minutes"
    exit 1
elif [ $BUILD_STATUS -ne 0 ]; then
    echo ""
    echo "ERROR: Build failed with exit code $BUILD_STATUS"
    exit $BUILD_STATUS
fi

if [ ! -f "output/pou_con_release_arm.tar.gz" ]; then
    echo "ERROR: Build failed - release tarball not found"
    exit 1
fi

echo ""
echo "Release: output/pou_con_release_arm.tar.gz"
echo "Size: $(du -h output/pou_con_release_arm.tar.gz | cut -f1)"

# Step 2: Create deployment package (without debs)
echo ""
echo "=== Step 2: Creating Deployment Package (No Debs) ==="

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_DIR="deployment_package_$TIMESTAMP"

mkdir -p "$PACKAGE_DIR/pou_con"

# Extract release
echo "Extracting release..."
tar -xzf output/pou_con_release_arm.tar.gz -C "$PACKAGE_DIR/pou_con/"

# Copy update script (primary use case for quick builds)
if [ -f "scripts/update.sh" ]; then
    cp scripts/update.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/update.sh"
    echo "  ✓ Update script included"
fi

# Copy screen timeout scripts
if [ -f "scripts/set_screen_timeout.sh" ]; then
    mkdir -p "$PACKAGE_DIR/pou_con/scripts"
    cp scripts/set_screen_timeout.sh "$PACKAGE_DIR/pou_con/scripts/"
    cp scripts/on_screen.sh "$PACKAGE_DIR/pou_con/scripts/"
    cp scripts/off_screen.sh "$PACKAGE_DIR/pou_con/scripts/"
    chmod +x "$PACKAGE_DIR/pou_con/scripts/"*.sh
    echo "  ✓ Screen timeout scripts included"
fi

# Copy setup_sudo.sh for system time management
if [ -f "setup_sudo.sh" ]; then
    cp setup_sudo.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/setup_sudo.sh"
fi

# Create README for quick package
cat > "$PACKAGE_DIR/README.txt" << 'EOF'
PouCon Quick Update Package
============================

This is an app-only update package (no runtime debs included).
Use this to update an EXISTING PouCon installation.

For fresh installations, use a full deployment package built with:
  ./scripts/build_and_package.sh

Usage:
  1. Copy to USB drive
  2. At Raspberry Pi:
     cd /media/pi/*/deployment_package_*/
     sudo ./update.sh
  3. Done!
EOF

# Package everything
echo "Creating deployment archive..."
tar -czf "pou_con_deployment_quick_$TIMESTAMP.tar.gz" "$PACKAGE_DIR/"

# Cleanup temp directory
rm -rf "$PACKAGE_DIR"

echo ""
echo "=== Quick Build Complete! ==="
echo ""
echo "Package: pou_con_deployment_quick_$TIMESTAMP.tar.gz"
echo "Size: $(du -h pou_con_deployment_quick_$TIMESTAMP.tar.gz | cut -f1)"
echo ""
echo "⚠ This package is for UPDATING existing installations only."
echo "  It does NOT include runtime debs (chromium, swayidle, etc.)"
echo "  For fresh installs, use: ./scripts/build_and_package.sh"
echo ""
echo "Next step: Copy to USB drive and run update.sh on the Pi"
echo "  cp pou_con_deployment_quick_$TIMESTAMP.tar.gz /media/<usb-drive>/"
