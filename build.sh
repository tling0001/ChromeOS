#!/usr/bin/env bash

# Check if sudo is available and set with_sudo accordingly
if command -v sudo &>/dev/null; then
    with_sudo="sudo "
else
    with_sudo=""
fi

# ✅ Hardcoded ChromeOS recovery image
RECOVERY_URL="${RECOVERY_URL:-https://dl.google.com/dl/edgedl/chromeos/recovery/chromeos_16640.61.0_volteer_recovery_stable-channel_VolteerMPKeys-v14.bin.zip}"

# Function to install required dependencies
install_dependencies() {
    ${with_sudo}apt-get update && ${with_sudo}apt-get -y install pv cgpt tar unzip aria2 curl
}

# clean folder brunch and chromeos if they exist
clean_previous_run() {
    [ -d brunch ] && rm -rf brunch
    [ -d chromeos ] && rm -rf chromeos
    echo "Cleaned previous run"
}

# ✅ UPDATED: download ChromeOS (no scraping, uses fixed URL)
download_chromeos() {
    echo "Using fixed recovery image:"
    echo "$RECOVERY_URL"

    echo "Downloading ChromeOS..."
    aria2c --console-log-level=warn --summary-interval=1 -x 16 -o chromeos.zip "$RECOVERY_URL"

    if [ ! -f chromeos.zip ]; then
        echo "::error::Download failed"
        exit 1
    fi

    echo "Extracting ChromeOS..."
    unzip -o chromeos.zip -d chromeos
    rm -f chromeos.zip

    # Ensure a .bin exists
    BIN_FILE=$(find chromeos -name "*.bin" | head -n 1)

    if [ -z "$BIN_FILE" ]; then
        echo "::error::No .bin file found after extraction"
        exit 1
    fi

    echo "✅ ChromeOS downloaded successfully"
}

# Function to download the latest Brunch release
download_brunch() {
    local url="https://api.github.com/repos/sebanc/brunch/releases/latest"
    local response=$(curl -s "$url")
    local link=$(echo "$response" | grep browser_download_url | grep ".tar.gz" | cut -d '"' -f 4 | head -n 1)

    if [ -z "$link" ]; then
        if [ "$D_BRUNCH_COUNT" -ge 2 ]; then
            echo "Failed to download Brunch"
            exit 1
        else
            local random_sec=$((1 + RANDOM % 5))
            echo "Failed to download Brunch. Retrying in $random_sec seconds"
            sleep $random_sec
            D_BRUNCH_COUNT=$((D_BRUNCH_COUNT + 1))
            download_brunch
            return
        fi
    fi

    echo "Downloading Brunch"
    aria2c --console-log-level=warn --summary-interval=1 -x 16 -o brunch.tar.gz "$link"

    mkdir -p brunch
    tar -xzf brunch.tar.gz -C brunch
    rm -f brunch.tar.gz
}

# Function for post-download setup
post_download_setup() {
    # Check if brunch and chromeos directories exist
    [ ! -d brunch ] && {
        echo "brunch directory not found"
        exit 1
    }
    [ ! -d chromeos ] && {
        echo "chromeos directory not found"
        exit 1
    }

    # Copy all files from brunch to chromeos
    echo "Copying Brunch files to Chrome OS..."
    cp -r brunch/* chromeos/

    # Normalize bin filename
    BIN_FILE=$(find chromeos -name "*.bin" | head -n 1)

    if [ -z "$BIN_FILE" ]; then
        echo "chromeos .bin not found"
        exit 1
    fi

    mv "$BIN_FILE" chromeos/chromeos.bin
}

# Function to build the final Chrome OS image
build_chromos_img() {
    cd chromeos || {
        echo "Failed to change directory to chromeos"
        exit 1
    }

    [ ! -f chromeos.bin ] && {
        echo "chromeos.bin not found"
        exit 1
    }

    [ ! -f chromeos-install.sh ] && {
        echo "chromeos-install.sh not found"
        exit 1
    }

    [ -f chromeos.img ] && rm -f chromeos.img

    CHROMEOS_IMG_FILENAME=${CHROMEOS_IMG_FILENAME:-"chromeos.img"}

    [[ "$CHROMEOS_IMG_FILENAME" != *.img ]] && {
        echo "CHROMEOS_IMG_FILENAME must end with .img"
        exit 1
    }

    ${with_sudo}bash chromeos-install.sh -src chromeos.bin -dst "$CHROMEOS_IMG_FILENAME"

    if [ -f "$CHROMEOS_IMG_FILENAME" ]; then
        echo "✅ $CHROMEOS_IMG_FILENAME created successfully"
    else
        echo "❌ Failed to create $CHROMEOS_IMG_FILENAME"
        exit 1
    fi
}

# Main execution
install_dependencies || {
    echo "Failed to install dependencies"
    exit 1
}

if [ -z "$1" ]; then
    echo "No codename provided (still required for compatibility)"
fi

clean_previous_run \
&& download_chromeos \
&& download_brunch \
&& post_download_setup \
&& build_chromos_img
``
