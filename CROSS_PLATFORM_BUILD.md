# Cross-Platform Build Guide for PouCon

## The Problem

Your development machine is **x86_64** (AMD64), but Raspberry Pi uses **ARM** architecture (ARM64 or ARM32). While Elixir's BEAM bytecode is platform-independent, some dependencies use **NIFs** (Native Implemented Functions) - compiled C code that's architecture-specific.

**PouCon dependencies with NIFs:**
- `bcrypt_elixir` - Password hashing (native C)
- `ecto_sqlite3` - SQLite database bindings (native C)
- `circuits_uart` - Serial port communication (native C)

**This means you CANNOT directly copy a release built on x86_64 to ARM Raspberry Pi.**

## Solutions Overview

| Solution | Build Time | Setup Complexity | Reliability | Recommended |
|----------|------------|------------------|-------------|-------------|
| **1. Build on Pi** | Slow (30-60 min) | Simple | High | Good for 1-2 deployments |
| **2. Docker ARM Emulation** | Medium (10-20 min) | Medium | High | **Best for multiple sites** |
| **3. Pi Build Server** | Fast (5-10 min) | Simple | Highest | **Best overall** |
| **4. Cross-compile** | Fast (5 min) | Complex | Low | Not recommended |

## Solution 1: Build on Raspberry Pi (Simple)

### Pros
- No architecture issues
- Simple setup
- No special tools needed

### Cons
- Very slow (30-60 minutes per build)
- Need Elixir/Erlang installed on Pi
- Consumes Pi resources

### Setup Process

**1. Install Elixir/Erlang on Raspberry Pi:**

```bash
# SSH to Raspberry Pi
ssh pi@<pi-ip-address>

# Install dependencies
sudo apt update
sudo apt install -y git curl build-essential autoconf m4 libncurses5-dev \
  libwxgtk3.0-gtk3-dev libwxgtk-webview3.0-gtk3-dev libgl1-mesa-dev \
  libglu1-mesa-dev libpng-dev libssh-dev unixodbc-dev xsltproc fop \
  libxml2-utils libncurses-dev openjdk-11-jdk

# Install asdf (Erlang/Elixir version manager)
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
source ~/.bashrc

# Install Erlang plugin
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git

# Install Elixir plugin
asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git

# Install Erlang (this takes 30-60 minutes on Pi!)
asdf install erlang 26.2.1

# Install Elixir (5-10 minutes)
asdf install elixir 1.16.0-otp-26

# Set global versions
asdf global erlang 26.2.1
asdf global elixir 1.16.0-otp-26

# Verify installation
elixir --version
```

**2. Build Release on Pi:**

```bash
# Clone repository
cd ~
git clone <repository-url> pou_con
cd pou_con

# Install dependencies (this takes time)
mix local.hex --force
mix local.rebar --force
mix deps.get

# Build production release
MIX_ENV=prod mix deps.compile
MIX_ENV=prod mix compile
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release

# Release is now in _build/prod/rel/pou_con/
```

**3. Create Deployment Package:**

```bash
# Package for deployment
cd /tmp
cp -r ~/pou_con/_build/prod/rel/pou_con ./
tar -czf pou_con_release_$(date +%Y%m%d).tar.gz pou_con/

# Copy to USB or transfer to other Pis
# This release can now be deployed to any Pi with same ARM architecture
```

## Solution 2: Docker with ARM Emulation (Recommended for Multiple Sites)

### Pros
- Build on your fast development machine
- Consistent build environment
- Can build for multiple architectures
- Reproducible builds

### Cons
- Initial Docker setup required
- Slightly slower than native builds (but faster than Pi)
- Uses emulation (QEMU)

### Setup Process

**1. Install Docker and Setup Buildx:**

```bash
# On your x86_64 development machine

# Install Docker (if not already installed)
# For Ubuntu/Debian:
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
# Log out and back in

# Install QEMU for ARM emulation
sudo apt update
sudo apt install -y qemu-user-static

# Enable Docker BuildKit
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap
```

**2. Create Dockerfile for ARM Build:**

```bash
cd /home/tankwanghow/Projects/elixir/pou_con

cat > Dockerfile.arm << 'EOF'
# Multi-stage Dockerfile for ARM builds
FROM hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y \
    build-essential \
    git \
    curl \
    sqlite3 \
    libsqlite3-dev \
    ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config

# Copy compile-time config files before we compile dependencies
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# Copy application code
COPY priv priv
COPY lib lib
COPY assets assets

# Compile assets and application
RUN mix assets.deploy
RUN mix compile

# Build release
COPY config/runtime.exs config/
RUN mix release

# Extract release for easier copying
RUN cd /app/_build/prod/rel/pou_con && \
    tar -czf /app/pou_con_release_arm.tar.gz .

# Final stage - just the tarball
FROM scratch AS export
COPY --from=builder /app/pou_con_release_arm.tar.gz /
EOF
```

**3. Build for ARM Architecture:**

```bash
# Build release for ARM64 (Raspberry Pi 3B+/4)
docker buildx build \
  --platform linux/arm64 \
  --output type=local,dest=./output \
  -f Dockerfile.arm \
  .

# The release tarball is now in ./output/pou_con_release_arm.tar.gz
# This was built FOR ARM but ON your x86_64 machine!

# Check the file
ls -lh output/pou_con_release_arm.tar.gz

# Build time: ~10-20 minutes (much faster than building on Pi)
```

**4. Create Deployment Package:**

```bash
# Create deployment package with scripts
mkdir -p deployment_package
cd deployment_package

# Extract release
tar -xzf ../output/pou_con_release_arm.tar.gz -C ./pou_con/

# Copy deployment scripts from DEPLOYMENT_GUIDE.md
# (deploy.sh, backup.sh, uninstall.sh, README.txt)

# Package everything
cd ..
tar -czf pou_con_deployment_arm_$(date +%Y%m%d).tar.gz deployment_package/

# Copy to USB drive for field deployment
cp pou_con_deployment_arm_*.tar.gz /media/usb_drive/
```

**5. Verify ARM Build (Optional):**

```bash
# Run ARM release on your x86_64 machine using QEMU to test it
docker run --rm -it --platform linux/arm64 \
  -v $(pwd)/output:/release \
  debian:bookworm-slim \
  /bin/bash

# Inside container:
cd /release
tar -xzf pou_con_release_arm.tar.gz
file bin/pou_con  # Should show "ARM aarch64"
```

## Solution 3: Raspberry Pi Build Server (Best Overall)

### Pros
- Fast builds (Pi stays on, deps cached)
- No emulation overhead
- Simple workflow
- Highest reliability

### Cons
- Need spare Raspberry Pi
- Need network access to build Pi

### Setup Process

**1. Setup One Pi as Build Server:**

```bash
# Use any spare Raspberry Pi at your office
# Follow "Solution 1" setup to install Elixir/Erlang

# Keep it powered on and connected to network
# Give it static IP or hostname: build-pi.local

# Install SSH keys for passwordless access
ssh-copy-id pi@build-pi.local
```

**2. Create Build Script on Development Machine:**

```bash
# On your development machine
cd /home/tankwanghow/Projects/elixir/pou_con

cat > build_on_pi.sh << 'EOF'
#!/bin/bash
set -e

BUILD_PI="pi@build-pi.local"
PROJECT_NAME="pou_con"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Building PouCon on Raspberry Pi Build Server ==="

# 1. Sync code to build Pi
echo "1. Syncing code to build Pi..."
rsync -av --delete \
  --exclude '_build' \
  --exclude 'deps' \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude '*.db' \
  ./ "$BUILD_PI:~/$PROJECT_NAME/"

# 2. Build release on Pi
echo "2. Building release on Pi..."
ssh "$BUILD_PI" << 'REMOTE_SCRIPT'
cd ~/pou_con
export MIX_ENV=prod

# Get/update dependencies
mix deps.get --only prod

# Build release
mix deps.compile
mix compile
mix assets.deploy
mix release

# Package release
cd _build/prod/rel/pou_con
tar -czf ~/pou_con_release_$(date +%Y%m%d_%H%M%S).tar.gz .
REMOTE_SCRIPT

# 3. Download release to local machine
echo "3. Downloading release..."
LATEST_RELEASE=$(ssh "$BUILD_PI" "ls -t ~/pou_con_release_*.tar.gz | head -1")
scp "$BUILD_PI:$LATEST_RELEASE" ./

echo ""
echo "=== Build Complete! ==="
echo "Release: $(basename $LATEST_RELEASE)"
echo "Size: $(du -h $(basename $LATEST_RELEASE) | cut -f1)"
echo ""
echo "Next: Create deployment package and copy to USB drive"
EOF

chmod +x build_on_pi.sh
```

**3. Build Workflow:**

```bash
# On your development machine
cd /home/tankwanghow/Projects/elixir/pou_con

# Make code changes...
git commit -am "Add new feature"

# Build on Pi
./build_on_pi.sh

# Release will be downloaded: pou_con_release_YYYYMMDD_HHMMSS.tar.gz

# Create deployment package
./create_deployment_package.sh pou_con_release_*.tar.gz

# Copy to USB
cp pou_con_deployment_*.tar.gz /media/usb_drive/

# Deploy to field sites (no internet needed)
```

**Build time: 5-10 minutes** (after initial setup, deps are cached)

## Solution 4: True Cross-Compilation (Not Recommended)

Cross-compiling Erlang/Elixir for ARM is complex and error-prone due to:
- Need to cross-compile Erlang VM
- Need to cross-compile all NIFs
- Need ARM toolchain
- Need to match exact ARM architecture (armv7l vs aarch64)
- Hard to debug issues

**Not recommended unless you have specific expertise.**

## Recommended Workflow for Your Use Case

Based on "multiple poultry houses" deployment:

### **Recommended: Docker ARM Build (Solution 2)**

**Why:**
1. Build on your fast development machine (10-20 min vs 30-60 min on Pi)
2. No need for dedicated build Pi
3. Reproducible builds (same environment every time)
4. Can build multiple architectures if needed (ARM32 + ARM64)

**One-time setup (30 minutes):**
```bash
# Install Docker + buildx
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Setup ARM emulation
sudo apt install -y qemu-user-static
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap
```

**Every build (10-20 minutes):**
```bash
cd /home/tankwanghow/Projects/elixir/pou_con

# Build for ARM
docker buildx build \
  --platform linux/arm64 \
  --output type=local,dest=./output \
  -f Dockerfile.arm \
  .

# Package for deployment
./create_deployment_package.sh output/pou_con_release_arm.tar.gz

# Copy to USB drive
cp pou_con_deployment_*.tar.gz /media/usb_drive/

# Deploy at poultry houses (no internet needed)
```

### **Alternative: Pi Build Server (Solution 3)**

If Docker feels too complex, use a spare Pi as build server:
- Keep it at office with power + network
- One-time Elixir setup (1 hour)
- Then builds take 5-10 minutes via SSH
- Most reliable method

## Deployment Package Creation Script

This works with ANY of the above solutions:

```bash
cat > create_deployment_package.sh << 'EOF'
#!/bin/bash
set -e

if [ $# -eq 0 ]; then
    echo "Usage: ./create_deployment_package.sh <release_tarball.tar.gz>"
    exit 1
fi

RELEASE_TAR="$1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_DIR="deployment_package_$TIMESTAMP"

echo "Creating deployment package from $RELEASE_TAR..."

mkdir -p "$PACKAGE_DIR/pou_con"
tar -xzf "$RELEASE_TAR" -C "$PACKAGE_DIR/pou_con/"

# Copy deployment scripts (from DEPLOYMENT_GUIDE.md)
cp scripts/deploy.sh "$PACKAGE_DIR/"
cp scripts/backup.sh "$PACKAGE_DIR/"
cp scripts/uninstall.sh "$PACKAGE_DIR/"
cp scripts/README.txt "$PACKAGE_DIR/"

# Make scripts executable
chmod +x "$PACKAGE_DIR"/*.sh

# Package everything
tar -czf "pou_con_deployment_$TIMESTAMP.tar.gz" "$PACKAGE_DIR/"

echo ""
echo "Deployment package created: pou_con_deployment_$TIMESTAMP.tar.gz"
echo "Size: $(du -h pou_con_deployment_$TIMESTAMP.tar.gz | cut -f1)"
echo ""
echo "Copy this to USB drive and deploy at poultry houses"

# Cleanup
rm -rf "$PACKAGE_DIR"
EOF

chmod +x create_deployment_package.sh
```

## Verification Before Deployment

Test the ARM release works before deploying to field:

```bash
# Option 1: Test on real Pi at office
scp pou_con_deployment_*.tar.gz pi@test-pi.local:~/
ssh pi@test-pi.local
cd ~
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh
sudo systemctl start pou_con
curl http://localhost:4000  # Should work!

# Option 2: Test in Docker ARM emulation
docker run --rm -it --platform linux/arm64 \
  -p 4000:4000 \
  -v $(pwd)/pou_con:/app \
  debian:bookworm-slim \
  /bin/bash

# Inside container:
cd /app
./bin/pou_con start
# Access http://localhost:4000 from host browser
```

## Summary

**For your use case (multiple poultry houses, offline deployment):**

1. **Use Docker ARM builds** (Solution 2) - Best balance of speed and simplicity
2. Create deployment package once on your dev machine
3. Copy to USB drives
4. Deploy at each site (5-10 minutes, no internet)

**Initial setup time:** 30 minutes (Docker + buildx)
**Per-build time:** 10-20 minutes
**Per-deployment time:** 5-10 minutes

This gives you the fastest workflow while maintaining offline deployment capability!
