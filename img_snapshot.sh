#!/bin/bash

set -x

LANG=C

PID=/var/run/backuppc/BackupPC.pid
DATE=$(date +%Y%m%d)
LVORIGIN=xfs_backuppc
LVSNAP=xfs_backuppc-snap
BACKUPFILE=imgbackup_$DATE.lz
LOG=/var/log/poolbackup/imgbackup_$DATE.log

### faster testing
#LVORIGIN=log
#LVSNAP=log-snap
#BACKUPFILE=log_backuppc_$DATE.img.lz
#LOG=/var/log/poolbackup/logbackup_$DATE.log

### check log folder
if [[ ! -d /var/log/poolbackup ]];
  then
    mkdir -p /var/log/poolbackup
  if [[ ! $? -eq 0 ]];
    then
      echo "can not create log folder, aborting!"
      exit 1
  fi
fi

### create logfile
printf "$(date)\n\n" > "$LOG"

### check BackupPC process
if [[ -f "$PID" ]];
  then
    printf "BackupPC is running, will stop it now\n\n" >> "$LOG"
    systemctl stop backuppc.service || exit 1
  else
    printf "BackupPC is not running\n\n" >> "$LOG"
fi

### redump image if last dump failed
printf "checking last dumpstate\n\n" >> "$LOG"

if sudo -u backup /usr/sbin/amreport agrar | grep -e "FAILED" && printf "last dump failed, try to redump\n\n" >> "$LOG";
  then
    if ls /media/amandaspool/imgbackup* > /dev/null 2>&1 && printf "previous image found, dump again\n\n" >> "$LOG";
      then
        ### redump manual tapecheck
        if sudo -u backup /usr/sbin/amcheck agrar > /dev/null 2>&1;
          then sudo -u backup /usr/sbin/amdump agrar
            if [[ ! $? -eq 0 ]];
              then
                printf "amdump failed again!\n\n" >> "$LOG"
                printf "\nAmanda Report:\n--------------\n\n" >> "$LOG"
                sudo -u backup /usr/sbin/amreport agrar | tee -a "$LOG" | mail -s "BackupPC pool redump failed!" root
                exit 1
            fi
            printf "amdump successful\n\n" >> "$LOG"
            printf "\nAmanda Report:\n--------------\n\n" >> "$LOG"
            sudo -u backup /usr/sbin/amreport agrar | tee -a "$LOG" | mail -s "BackupPC pool amdump successful" root
            exit 0
          else
            printf "can not dump, check tape!\n\n" >> "$LOG"
            exit 1
        fi
      else
        printf "no previous image found, going on with image routine\n\n" >> "$LOG"
    fi
  else
    printf "last dump successful\n\n" >> "$LOG"
fi

### cleanup
printf "cleaning up old backupfiles\n\n" >> "$LOG"

if ls /media/amandaspool/imgbackup* > /dev/null 2>&1;
  then
    printf "old backupfile found, removing\n\n" >> "$LOG"
    rm -f /media/amandaspool/imgbackuppc*
  else
    echo "nothing to clean up\n\n" >> "$LOG"
fi

### check/create snapshot
if [[ -L "/dev/mapper/backupgroup-xfs_backuppc--snap" ]];
  then
    printf "Existing snapshot detected, $(lvs | grep "$LVSNAP" | awk '{ print $6 }') % used, removing\n\n" >> "$LOG"
    lvremove -f /dev/backupgroup/"$LVSNAP" >> "$LOG"
    printf "\n" >> "$LOG"
  if [[ ! $? -eq 0 ]];
    then
      printf "\n!!! can not remove snapshot, aborting!\n\n exit 1" >> "$LOG"
      exit 1
  fi
    sleep 10
    printf "creating snapshot $LVSNAP\n" >> "$LOG"
    lvcreate -s -L 5G -n "$LVSNAP" /dev/backupgroup/"$LVORIGIN" >> "$LOG"
    printf "\n" >> "$LOG"
  if [[ ! $? -eq 0 ]];
    then
      printf "\n!!! can not create snapshot, aborting!\n\n exit 1" >> "$LOG"
      exit 1
  fi
    sleep 10
  else
    printf "creating snapshot $LVSNAP\n" >> "$LOG"
    lvcreate -s -L 5G -n "$LVSNAP" /dev/backupgroup/"$LVORIGIN" >> "$LOG" #|| printf "snapshot failed" && exit 1
    printf "\n" >> "$LOG"
  if [[ ! $? -eq 0 ]];
    then
      printf "\n!!! can not create snapshot, aborting!\n\n exit 1" >> "$LOG"
      exit 1
  fi
    sleep 10
fi

## start BackupPC process
printf "starting BackupPC\n\n" >> "$LOG"
systemctl start backuppc.service
if [[ ! $? -eq 0 ]];
  then
    printf "\n!!! BackupPC failed to start!\n\n exit 1" >> "$LOG"
    exit 1
fi
sleep 2

### create imagefile
printf "creating lzop image on /media/amandaspool\n\n" >> "$LOG"
#printf "testrun! with small image\n\n" >> "$LOG"

if pv /dev/backupgroup/"$LVSNAP" | lzop | cat > /media/amandaspool/"$BACKUPFILE";
  then
    printf "image created successfully\n\n" >>"$LOG"
  else
    printf "\n!!! image failed\n\n?" >> "$LOG"
fi
sleep 2

printf "removing snapshot $LVSNAP\n" >> "$LOG"
lvremove -f /dev/backupgroup/"$LVSNAP" >> "$LOG"
if [[ ! $? -eq 0 ]];
  then
    printf "\n!!! can not remove snapshot, has to removed manually!\n\n exit 1" >> "$LOG"
fi

### dump to tape
printf "\n" >> "$LOG"
printf "checking tape\n\n" >> "$LOG"

if [[ -e /tmp/tapecheck.successful ]];
  then
    printf "valid tape found, running amdump\n\n" >> "$LOG"
    sudo -u backup /usr/sbin/amdump agrar || printf "amdump failed!\n\n" >> "$LOG"

    printf "\nAmanda Report:\n--------------\n\n" >> "$LOG"
    sudo -u backup /usr/sbin/amreport agrar >> "$LOG"
  else
    printf "\n!!! no valid tape found, aborting!\n\n exit 2" >> "$LOG"
fi
sleep 5

### create report, mail, cleanup
if sudo -u backup /usr/sbin/amreport agrar | grep -e "FAILED";
  then
    printf "\n!!! - amdump failed\n\n\n\n" >> "$LOG"
    sudo -u backup /usr/sbin/amreport agrar | mail -s "BackupPC pool amdump failed!" root
    rm -f /tmp/tapecheck.successful
    exit 1
  else
    printf "\n\n" >> "$LOG"
    printf "amdump successful $(date)\n\n"  >> "$LOG"
    sudo -u backup /usr/sbin/amreport agrar | mail -s "BackupPC pool amdump successful" root
    rm -f /media/amandaspool/imgbackup*
    rm -f /tmp/tapecheck.successful
    exit 0
fi
