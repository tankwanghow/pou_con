#!/bin/bash
# One-command build and package for ARM deployment
# This builds the release AND creates the deployment package

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "=== PouCon Complete Build Process ==="
echo ""
echo "This will:"
echo "  1. Build ARM release using Docker (~10-20 minutes)"
echo "  2. Create deployment package"
echo "  3. Ready for USB transfer"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Step 1: Build ARM release
echo ""
echo "=== Step 1: Building ARM Release ==="
./scripts/build_arm.sh

# Step 2: Create deployment package
echo ""
echo "=== Step 2: Creating Deployment Package ==="
./scripts/create_deployment_package.sh

echo ""
echo "=== Complete Build Process Finished! ==="
echo ""
echo "Deployment package is ready:"
ls -lh pou_con_deployment_*.tar.gz | tail -1
echo ""
echo "Next step: Copy to USB drive"
echo "  cp pou_con_deployment_*.tar.gz /media/<usb-drive>/"
