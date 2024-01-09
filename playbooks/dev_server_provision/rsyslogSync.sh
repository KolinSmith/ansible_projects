#/etc/cron.daily
#!/bin/sh
#sudo rsync -avz -e "ssh -i /home/dax/.ssh/id_ecdsa -o StrictHostKeyChecking=no -o
 UserKnownHostsFile=/dev/null" --progress /var/log/Borg dax@192.168.3.4:/home/dax/
logs/
#sudo rsync -avz -e "ssh -i /home/dax/.ssh/id_ecdsa -o StrictHostKeyChecking=no -o
 UserKnownHostsFile=/dev/null" --progress /var/log/cups dax@192.168.3.4:/home/dax/
logs/
#sudo rsync -avz -e "ssh -i /home/dax/.ssh/id_ecdsa -o StrictHostKeyChecking=no -o
 UserKnownHostsFile=/dev/null" --progress /var/log/pfsense.localdomain dax@192.168
.3.4:/home/dax/logs/