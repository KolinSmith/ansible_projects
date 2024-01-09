#/etc/cron.daily
#!/bin/bash

DEST_FOLDER='/home/pi/backups/'
DEST_FILE=backup-$(date +%F).tar
BACKUP_CMD='/bin/tar -rvf'
$BACKUP_CMD $DEST_FOLDER/$DEST_FILE /home/pi/bpytop
$BACKUP_CMD $DEST_FOLDER/$DEST_FILE /home/pi/gravity-sync
$BACKUP_CMD $DEST_FOLDER/$DEST_FILE /home/pi/helloThere.txt
/bin/gzip $DEST_FOLDER/$DEST_FILE
/usr/bin/find $DEST_FOLDER -mtime +8 -delete