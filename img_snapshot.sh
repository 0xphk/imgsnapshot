#!/bin/bash

###################################################
#                                                 #
#  img_snapshot.sh                                #
#  automating BackupPC pool backup with amanda    #
#  using lvm2 snapshot and lzop compressed image  #
#                                                 #
#  https://github.com/0xphk/imgsnapshot           #
#  https://zmanda.com/                            #
#  http://backuppc.sourceforge.net/               #
#                                                 #
###################################################


### debug
set -x

LANG=C

### vars
PID=/var/run/backuppc/BackupPC.pid
DATE=$(date +%Y%m%d)
LVORIGIN=xfs_backuppc
LVSNAP=xfs_backuppc-snap
LVSIZE=5G
LOGDIR=/var/log/poolbackup
LOG=$LOGDIR/imgbackup_$DATE.log
BACKUPFILE=imgbackup_$DATE.lz
CUSTOMER=agrar

### faster testing
#LVORIGIN=log
#LVSNAP=log-snap
#BACKUPFILE=log_backuppc_$DATE.img.lz
#LOG=/var/log/poolbackup/logbackup_$DATE.log

### check log folder
if [[ ! -d "$LOGDIR" ]];
  then
    mkdir -p "$LOGDIR"
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

if sudo -u backup /usr/sbin/amreport "$CUSTOMER" | grep -e "FAILED" && printf "last dump failed, checking image\n\n" >> "$LOG";
  then
    if ls /media/amandaspool/imgbackup* > /dev/null 2>&1 && printf "previous image found, try to redump\n\n" >> "$LOG";
      then
        ### redump manual tapecheck
        if sudo -u backup /usr/sbin/amcheck "$CUSTOMER" > /dev/null 2>&1;
          then sudo -u backup /usr/sbin/amdump "$CUSTOMER"
            if [[ ! $? -eq 0 ]];
              then
                printf "amdump failed again!\n\n" >> "$LOG"
                printf "\nAmanda Report:\n--------------\n\n" >> "$LOG"
                sudo -u backup /usr/sbin/amreport "$CUSTOMER" | tee -a "$LOG" | mail -s "\[$CUSTOMER\] pool redump failed! $(date +%H:%M:%S)" root
                exit 1
            fi
            printf "amdump successful\n\n" >> "$LOG"
            printf "\nAmanda Report:\n--------------\n\n" >> "$LOG"
            sudo -u backup /usr/sbin/amreport "$CUSTOMER" | tee -a "$LOG" | mail -s "\[$CUSTOMER\] BackupPC pool dump successful $(date +%H:%M:%S)" root
            printf "cleaning up\n\n" >> "$LOG"
            rm -f /media/amandaspool/imgbackup*
            rm -f /tmp/tapecheck.successful
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
    lvcreate -s -L "$LVSIZE" -n "$LVSNAP" /dev/backupgroup/"$LVORIGIN" >> "$LOG"
    printf "\n" >> "$LOG"
  if [[ ! $? -eq 0 ]];
    then
      printf "\n!!! can not create snapshot, aborting!\n\n exit 1" >> "$LOG"
      exit 1
  fi
    sleep 10
  else
    printf "creating snapshot $LVSNAP\n" >> "$LOG"
    lvcreate -s -L "$LVSIZE" -n "$LVSNAP" /dev/backupgroup/"$LVORIGIN" >> "$LOG" #|| printf "snapshot failed" && exit 1
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

if pv -q /dev/backupgroup/"$LVSNAP" | lzop | cat > /media/amandaspool/"$BACKUPFILE";
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
    printf "\n!!! can not remove snapshot, must be removed manually!\n\n exit 1" >> "$LOG"
fi

### dump to tape
printf "\n" >> "$LOG"
printf "checking tape\n\n" >> "$LOG"

if [[ -e /tmp/tapecheck.successful ]];
  then
    printf "valid tape found, running amdump\n\n" >> "$LOG"
    sudo -u backup /usr/sbin/amdump "$CUSTOMER" || printf "amdump failed!\n\n" >> "$LOG"

    printf "\nAmanda Report:\n--------------\n\n" >> "$LOG"
    sudo -u backup /usr/sbin/amreport "$CUSTOMER" >> "$LOG"
  else
    printf "\n!!! no valid tape found, aborting!\n\n exit 2" >> "$LOG"
fi
sleep 5

### create report, mail, cleanup
if sudo -u backup /usr/sbin/amreport "$CUSTOMER" | grep -e "FAILED";
  then
    printf "\n!!! - amdump failed $(date +%Y%m%d\ %H:%M:%S)\n\n" >> "$LOG"
    sudo -u backup /usr/sbin/amreport "$CUSTOMER" | mail -s "\[$CUSTOMER\] pool dump failed! $(date +%H:%M:%S)" root
    rm -f /tmp/tapecheck.successful
    exit 1
  else
    printf "\n\n" >> "$LOG"
    sudo -u backup /usr/sbin/amreport "$CUSTOMER" | mail -s "\[$CUSTOMER\] pool dump successful $(date +%H:%M:%S)" root
    rm -f /media/amandaspool/imgbackup*
    rm -f /tmp/tapecheck.successful
    exit 0
fi
