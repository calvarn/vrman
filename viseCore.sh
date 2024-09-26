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
if [ -d "/home/$VMUser/.steam/stam/steamapps" ]; then
    echo "Steam library found."
else
    echo "Steam library does not exist, starting Steam."
    sudo -u "$VMUser" /home/$VMUser/.steam/steam/steam.sh -login "vriosk_steamvrloader" "vrioskpassword" -shutdown >/dev/null 2>&1
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

# Install curl for the ALVR updater if Quest is selected
if [ "$hmd" = "quest" ]; then
    apt install -y curl >/dev/null 2>&1
    ./alvrStreamerUpdate.sh
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
    ./alvrClientUpdate.sh

    read -p "Vrman is now going to attempt to load into the headset environment. Please put on the headset." 
    adb shell am start -n alvr.client.stable/android.app.NativeActivity
    adb forward tcp:9943 tcp:9943
    adb forward tcp:9944 tcp:9944
    ./startSVR.sh
fi
