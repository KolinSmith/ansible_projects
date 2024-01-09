#/etc/cron.weekly

#!/bin/sh
#my raspberry pi update script located in /etc/cron.daily
#run sudo chmod +x myUpdate.sh after you put this script in the folder
sudo apt update -y
sudo apt upgrade -y
sudo apt dist-upgrade -y
sudo apt autoremove
sudo apt autoclean
#sudo reboot