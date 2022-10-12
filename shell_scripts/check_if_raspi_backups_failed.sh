#!/bin/bash
#use find to list out the most recent backups from the past day and show which ones have a file size of 0
find /mnt/disks/HUB/BACKUPS/Backup_of_Pis/ -iname "*.gz" -mtime -1 -printf "%k\n" | cut -d ":" -f2 | grep -w "0" >/dev/null
#if the output of the command above is 0 (which means it found a blank file) continue, if the output was 1 (which means it didn't find a blank file) then end
#https://www.cyberciti.biz/faq/bash-get-exit-code-of-command/
if [ $? -ne 1 ]
  then
    #define an array called backups as the output of the below command which lists out the file name and size (separated by a colon) of the most recent (past day) backups
    backups=($(find /mnt/disks/HUB/BACKUPS/Backup_of_Pis/ -iname "*.gz" -mtime -1 -printf "%f:%k\n"))
    #loop through the whole array
    for i in "${backups[@]}"
    do
      #set the variable zero as just the file size of the output (the output will be like stargazer_2022-02-11.gz:1513752 which is the name of the backup file colon size of file)
      zero=($(echo $i | cut -d ":" -f2))
      #if the variable of zero is equal to zero (which means that the file size of that backup is zero) continue
      if [ $zero -eq 0 ]
      then
        #defines the name of the backup, so if it was voyager's backup file it'll just grab the name "voyager"
        backup_name=($(echo $i | cut -d "_" -f1))
        # echo "Backup for $backup_name is blank! Check to make sure there isn't a problem."
        #use an api call to prowl to let me know that a backup failed
        curl --silent "https://api.prowlapp.com/publicapi/add" --form apikey="580ed4eaff3e772a7671ee3964f99ae3929740f9" --form application="Borg" --form event="Backup for $backup_name is blank!" --form priority="0" >/dev/null 2>&1
      fi
    done
fi
