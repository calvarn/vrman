sudo systemctl stop unattended-upgrades
sudo systemctl disable unattended-upgrades
rm -f -r vrman/
sudo apt install -y git
git clone https://github.com/calvarn/vrman/ >/dev/null
cd vrman
sudo ./viseCore.sh
