#!/bin/bash

# Set the country code you want to use
COUNTRY_CODE_PARAM="US"

# Check if you're running in sudo
if [[ $EUID -ne 0 ]]; then
	echo "Please run the script with sudo"
	exit 1
fi

# Check for an internet connection
if ! : >/dev/tcp/8.8.8.8/53; then
	echo 'Please connect to the internet.'
	exit
fi

sudo apt-get install crda hostapd dnsmasq

SCRIPT_LOCATION="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
JETSON_L4T_STRING=$(head -n 1 /etc/nv_tegra_release)
JETSON_L4T_RELEASE=$(echo $JETSON_L4T_STRING | cut -f 2 -d ' ' | grep -Po '(?<=R)[^;]+')
# Extract revision + trim trailing zeros to convert 32.5.0 => 32.5 to match git tags
JETSON_L4T_REVISION=$(echo $JETSON_L4T_STRING | cut -f 2 -d ',' | grep -Po '(?<=REVISION: )[^;]+' | sed 's/.0$//g')
JETSON_L4T_VERSION=$JETSON_L4T_RELEASE.$JETSON_L4T_REVISION
KERNEL_VER=`uname -r`
KERNEL_VER_SHORT=`uname -r | cut -d '.' -f 1,2`

WIFI_PATCH_FILE="0001-Wifi-Patch.patch"
SOURCE_SYNC_FILE="source_sync.sh"

# Download source_sync from nvidia to pull appropriate kernel
if [ ! -f "$SOURCE_SYNC_FILE" ]; then
	echo "Could not find $SOURCE_SYNC_FILE"
else
	echo "Found $SOURCE_SYNC_FILE"
fi

# Download Wifi 5GHZ git Patch
if [ ! -f "$WIFI_PATCH_FILE" ]; then
	echo "Could not find $WIFI_PATCH_FILE"
else
	echo "Found $WIFI_PATCH_FILE"
fi

# Get tegra tag
LINUX_SOURCE_TREE="linux-$KERNEL_VER_SHORT-source-tree"
if [ ! -d "$LINUX_SOURCE_TREE" ]; then
	mkdir $LINUX_SOURCE_TREE
	cd $LINUX_SOURCE_TREE
	git init
	git remote add origin git://nv-tegra.nvidia.com/linux-${KERNEL_VER_SHORT}
else
	echo "Found $LINUX_SOURCE_TREE"
	cd $LINUX_SOURCE_TREE
fi

echo "Extracting tegra tag from git kernel" 
TEGRA_TAG=$(git ls-remote --tags origin | grep ${JETSON_L4T_VERSION} | grep '[^^{}]$' | tail -n 1 | awk -F/ '{print $NF}')
cd ../

# Download the kernel
./source_sync.sh -k ${TEGRA_TAG} 
cd sources/kernel/kernel-$KERNEL_VER_SHORT/
ATH_PATCH_APPLIED=`git apply --check $SCRIPT_LOCATION/$WIFI_PATCH_FILE 2>&1`
if [ -z "$ATH_PATCH_APPLIED" ]; then
	echo "Applying patch $WIFI_PATCH_FILE to kernel"
	git apply $SCRIPT_LOCATION/$WIFI_PATCH_FILE
else
	echo "Patch $WIFI_PATCH_FILE is already applied to kernel"
fi

# Setup the kernel
echo "Building kernel-$KERNEL_VER_SHORT with ATH patch"
sudo make ARCH=arm64 mrproper -j$(($(nproc)-1)) && sudo make ARCH=arm64 tegra_defconfig -j$(($(nproc)-1))
sudo cp /usr/src/linux-headers-${KERNEL_VER}-ubuntu18.04_aarch64/kernel-${KERNEL_VER_SHORT}/Module.symvers .
sudo make ARCH=arm64 prepare modules_prepare  -j$(($(nproc)-1))
sudo -s make -j$(($(nproc)-1)) ARCH=arm64 M=drivers/net/wireless/ath/ modules

# Copy built kernel files to proper location
ATH_KERNEL_OUTPUT_LOCATION="/lib/modules/${KERNEL_VER}/kernel/drivers/net/wireless/ath"
echo "Copying built kernel modules to $ATH_KERNEL_OUTPUT_LOCATION"
sudo cp drivers/net/wireless/ath/ath.ko $ATH_KERNEL_OUTPUT_LOCATION
sudo cp drivers/net/wireless/ath/ath10k/ath10k*.ko $ATH_KERNEL_OUTPUT_LOCATION/ath10k/
# Reload kernel modules
echo "Reloading kernel modules"
sudo depmod
# Set regulatory country to remove NO-IR
echo "Setting regulatory country code in /etc/default/crda"
sudo sed -i "s/\(REGDOMAIN=\).*/\1$COUNTRY_CODE_PARAM/" /etc/default/crda

if ! grep -q "DAEMON_OPTS=\"/etc/hostapd/hostapd.conf\"" /etc/default/hostapd; then
sudo tee -a /etc/default/hostapd >/dev/null << 'EOF'

DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF
fi

echo -e "\033[32mFinished building and patching ATH drivers! Please reboot machine!"
cd $SCRIPT_LOCATION

# Just incase
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl start hostapd
