#!/bin/bash


# CONFIG STUFF
VMUser="a1g"  # Username of vriosk user
FIXSUDO="true"  # Install and give the user sudo
VISEversion="0.2"

# Root check
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Update package lists silently
echo "Updating package lists, please stand by..."
apt update >/dev/null 2>&1

# Enable 32-bit architecture for Steam
dpkg --add-architecture i386

# figlet go brrrr
if ! whereis figlet | grep -q '/'; then
    echo "Installing figlet, please stand by..."
    apt install -y figlet >/dev/null 2>&1
fi

# Check and install jq if not already installed
if ! whereis jq | grep -q '/'; then
    echo "Installing jq, please stand by..."
    apt install -y jq >/dev/null 2>&1
fi

# Check and install dialog if not already installed
if ! whereis dialog | grep -q '/'; then
    echo "Installing dialog, please stand by..."
    apt install -y dialog >/dev/null 2>&1
fi

figlet "VISE"

echo "Welcome to VISE (Vrman Installation SystEm) version $VISEversion!"
echo "Copyleft 2024 Caleb Varnadore. No rights reserved."
echo ""
echo WARNING: You are running a development branch of VISE.
echo This is STRONGLY advised against, proceed only if you know what you are doing.
echo Press enter to confirm you know what you are doing:
read


# Remove CD from sources
filename="/etc/apt/sources.list"

if [[ ! -f "$filename" ]]; then
    echo "CRITICAL ERROR: Sources not found."
    exit 1
fi

first_line=$(head -n 1 "$filename")
if [[ $first_line == "deb cdrom"* ]]; then
    sed -i '1s/^/# /' "$filename"
    echo "Disabled apt sourcing from cdrom."
else
    echo "No apt cdrom source found, ignoring."
fi

# Handle sudo setup
if [ "$FIXSUDO" = "true" ]; then
    apt install -y sudo >/dev/null 2>&1
    sudo usermod -aG sudo "$VMUser"
fi

# Install Steam
FILENAME="steam.deb"
URL="https://cdn.akamai.steamstatic.com/client/installer/steam.deb"

if ! whereis steam | grep -q '/'; then
    echo "Installing Steam..."
    wget "$URL" -O steam.deb >/dev/null 2>&1

    echo steam steam/question select "I AGREE" | sudo debconf-set-selections
    echo steam steam/license note '' | sudo debconf-set-selections

    sudo apt install -y ./steam.deb >/dev/null 2>&1
    rm steam.deb  # Remove the .deb file after installation

    # Update steam dependency installer to avoid confirmation prompts
    steamdepper="/usr/bin/steamdeps"
    sed -i 's/def update_packages(packages, install_confirmation=True):/def update_packages(packages, install_confirmation=False):/g' "$steamdepper"
else
    echo "Steam is already installed, not installing..."
fi

# First run Steam check
if [ -d "/home/$VMUser/.steam/steam/steamapps" ]; then
    echo "Steam library found."
else
    echo "Steam library does not exist, starting Steam."
    sudo -u "$VMUser" /home/$VMUser/.steam/steam/steam.sh -silent -login "vriosk_steamvrloader" "vrioskpassword" -shutdown >/dev/null 2>&1
fi

# Save starting directory
curdir=$(pwd)

# Define the filename for HMD type
hmdfilename="HMDtype"

# Function to display the dialog menu for HMD selection
function select_hmd() {
    hmd_choice=$(dialog --title "Welcome to Vrisok!" \
                        --menu "Please select your headset from the list below:" \
                        15 50 2 \
                        1 "Valve Index" \
                        2 "Meta Quest 2" \
                        3>&1 1>&2 2>&3)

    case $hmd_choice in
        1)
            echo "index" > "$hmdfilename"
            echo "HMD set to Valve Index"
            ;;
        2)
            echo "quest" > "$hmdfilename"
            echo "HMD set to Meta Quest 2"
            ;;
        *)
            dialog --msgbox "Invalid selection. Please try again." 5 40
            select_hmd  # Call the function again
            ;;
    esac
}

# Check if the file exists
if [[ -e "$hmdfilename" ]]; then
    hmd=$(< "$hmdfilename")
    echo "HMD set to $hmd"
else
    select_hmd  # Loop until a valid selection is made
fi

# Install steamcmd
echo steam steam/question select "I AGREE" | sudo debconf-set-selections
echo steam steam/license note '' | sudo debconf-set-selections
apt install -y steamcmd >/dev/null 2>&1

# Install curl for the ALVR updater if Quest is selected, then update ALVR
if [ "$hmd" = "quest" ]; then
    apt install -y curl >/dev/null 2>&1
    # Variables
    REPO="alvr-org/ALVR"
    TARBALL_FILENAME="alvr_streamer_linux_latest.tar.gz"
    VERSION_FILE="alvr_latest_version"

    # Fetch the latest release information from GitHub API
    echo "Fetching the latest ALVR release information..."
    LATEST_RELEASE_INFO=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")

    if [ $? -ne 0 ]; then
        echo "Failed to fetch release information."
        exit 1
    fi

    # Extract the download URL for the tarball
    TARBALL_URL=$(echo "$LATEST_RELEASE_INFO" | jq -r '.assets[] | select(.name | contains("alvr_streamer_linux.tar.gz")) | .browser_download_url')

    # Extract the version number from the release information
    LATEST_VERSION_NAME=$(echo "$LATEST_RELEASE_INFO" | jq -r '.tag_name')

    if [ -z "$TARBALL_URL" ]; then
        echo "No tarball found in the latest release."
        exit 1
    fi

    if [ -z "$LATEST_VERSION_NAME" ]; then
        echo "No version name found in the latest release."
        exit 1
    fi

    # Compare the current saved version with the latest version
    if [ -f "$VERSION_FILE" ]; then
        SAVED_VERSION_NAME=$(cat "$VERSION_FILE" | awk '{print $2}')
    else
        SAVED_VERSION_NAME=""
    fi

    if [ "$LATEST_VERSION_NAME" == "$SAVED_VERSION_NAME" ]; then
        echo "The saved version of ALVR Streamer is up-to-date."
    else
	    # Download the tarball if the version is newer
	    echo "Downloading the ALVR Sreamer tarball from $TARBALL_URL..."
	    curl -L -o "$TARBALL_FILENAME" "$TARBALL_URL"

	    if [ $? -eq 0 ]; then
	        echo "Download completed successfully: $TARBALL_FILENAME"
    
    	    # Save the new version name to a text file
    	    echo "Version: $LATEST_VERSION_NAME" > "$VERSION_FILE"
    	    echo "Version information saved to $VERSION_FILE"
    	    echo "Extracting new ALVR streamer..."
    	    tar -xzf "$TARBALL_FILENAME"
    	else
    	    echo "Download failed. Network issue?"
    	    exit 1
    	fi
    fi



    if [ -f "/home/$VMUser/.config/alvr/session.json" ]; then
    	echo "Found ALVR config"
    else
    	echo "No ALVR config found, loading ALVR..."
    	$PWD/alvr_streamer_linux/bin/alvr_dashboard > /dev/null 2>&1 &
    	pid=$!

    	sleep 3

    	kill $pid
    fi
	

    set +x
    driverDir="$PWD/alvr_streamer_linux/lib64/alvr"
    cd ..
    regeditor="/home/$VMUser/.steam/steam/steamapps/common/SteamVR/bin/vrpathreg.sh"
    configfile="/home/$VMUser/.config/alvr/session.json"

    # update config
    sed -i 's/"open_setup_wizard": true/"open_setup_wizard": false/g' $configfile
    sed -i 's/"auto_trust_clients": false/"auto_trust_clients": true/g' $configfile
    # Remove -x from the shebang line
    sed -i '1s|^#!/bin/bash -x|#!/bin/bash|' "$regeditor"
    # register driver
    if $regeditor show 2>/dev/null | grep -q "alvr_server :" >/dev/null; then
       echo "ALVR Driver already installed."
    else
        echo "Installing ALVR Driver..."
        $regeditor adddriver $driverDir
    fi
    apt install -y adb >/dev/null 2>&1
fi

# Update SteamVR
./updateSteamVR.sh

# From this point onward, headset is required
check_device() {
    # Get the list of connected devices
    device_list=$(adb devices | grep -w "device")

    # Check if there is at least one connected device
    [[ -n "$device_list" ]]
}

if [ "$hmd" = "quest" ]; then
    while true; do
        read -p "Please connect your Quest 2 Headset and press Enter when ready... " 

        if check_device; then
            echo "Awesome work, headset connected successfully!"
            break
        else
            echo "No headset detected. Please try again."
        fi
    done

    # Update ALVR Android app
    # Find Oculus device
    DEVICE_INFO=$(lsusb | grep -i "Oculus")

    if [ -z "$DEVICE_INFO" ]; then
        echo "No Oculus device found."
        exit 1
    fi

    # Extract vendor and product IDs
    VENDOR_ID=$(echo $DEVICE_INFO | awk '{print $6}' | cut -d':' -f1)
    PRODUCT_ID=$(echo $DEVICE_INFO | awk '{print $6}' | cut -d':' -f2)

    # Create udev rules file
    UDEV_RULES_FILE="/etc/udev/rules.d/51-oculus.rules"

    echo "Creating udev rules for Oculus device: Vendor ID: $VENDOR_ID, Product ID: $PRODUCT_ID"

    # Write udev rule
    echo "SUBSYSTEM==\"usb\", ATTR{idVendor}==\"$VENDOR_ID\", ATTR{idProduct}==\"$PRODUCT_ID\", MODE=\"0666\", GROUP=\"plugdev\"" | sudo tee $UDEV_RULES_FILE > /dev/null

    # Reload udev rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger

    echo "Udev rules have been set up successfully."


    # Variables
    REPO="alvr-org/ALVR"
    APK_FILENAME="alvr_client_android.apk"
    VERSION_FILE="alvr_client_version"
    PACKAGE_NAME="alvr.client.stable"  # Replace with the actual package name of the app

    # Fetch the latest release information from GitHub API
    echo "Fetching the latest ALVR Client release information..."
    LATEST_RELEASE_INFO=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")

    if [ $? -ne 0 ]; then
        echo "Failed to fetch release information."
        exit 1
    fi

    # Extract the download URL for the APK
    APK_URL=$(echo "$LATEST_RELEASE_INFO" | jq -r '.assets[] | select(.name | contains("alvr_client_android.apk")) | .browser_download_url')

    # Extract the version number from the release information
    LATEST_VERSION_NAME=$(echo "$LATEST_RELEASE_INFO" | jq -r '.tag_name')

    if [ -z "$APK_URL" ]; then
        echo "No APK found in the latest release."
        exit 1
    fi

    if [ -z "$LATEST_VERSION_NAME" ]; then
        echo "No version name found in the latest release."
        exit 1
    fi

    # Check the installed version on the Quest 2
    echo "Checking installed version on the Quest 2..."
    INSTALLED_VERSION=$(adb shell dumpsys package "$PACKAGE_NAME" | grep versionName | awk -F= '{print $2}')

    if [ $? -ne 0 ]; then
        echo "Failed to retrieve installed version. Ensure that the device is connected and the package name is correct."
        exit 1
    fi

    # normalize versions
    LATEST_VERSION_NAME=$(echo "$LATEST_VERSION_NAME" | sed "s/v//g")
    INSTALLED_VERSION=$(echo "$INSTALLED_VERSION" | sed "s/v//g")

    # Check if an update is necessary
    if [ "$LATEST_VERSION_NAME" != "$INSTALLED_VERSION" ]; then
        echo "A new version is available. Downloading the APK from $APK_URL..."
        
        # Download the APK if the version is newer
        curl -L -o "$APK_FILENAME" "$APK_URL"

        if [ $? -eq 0 ]; then
            echo "Download completed successfully: $APK_FILENAME"
            
            # Install the APK on the Quest 2 using adb
            echo "Installing the APK on the Quest 2..."
            adb install -r "$APK_FILENAME"

            if [ $? -eq 0 ]; then
                echo "APK installed successfully on the Quest 2."
            else
                echo "Failed to install APK on the Quest 2."
                exit 1
            fi

        else
            echo "Download failed. Network issue?"
            exit 1
        fi
    else
        echo "The installed version is up-to-date. No new download needed."
    fi

    # Update the version file with the latest version information
    echo "Version: $LATEST_VERSION_NAME" > "$VERSION_FILE"
    echo "ALVR Client version information saved to $VERSION_FILE"

    read -p "Vrman is now going to attempt to load into the headset environment. Please put on the headset." 
    adb shell am start -n alvr.client.stable/android.app.NativeActivity
    adb forward tcp:9943 tcp:9943
    adb forward tcp:9944 tcp:9944
    ./startSVR.sh
fi
