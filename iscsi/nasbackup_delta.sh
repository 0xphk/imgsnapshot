#!/bin/bash

###################################################
#                                                 #
#  nasbackup.sh on backuppc1.delta.bcs            #
#  automated BackupPC pool backup to iscsi-lun    #
#  using lvm2 snapshot and block based copy       #
#                                                 #
###################################################

### debug
#set -x

LANG=C

### vars
CUSTOMER=delta
DATE=$(date +%Y%m%d)
LOGDIR=/var/log/poolbackup
LOG=$LOGDIR/nasbackup_$DATE.log
PID=/var/run/backuppc/BackupPC.pid
MAIL=backup@bcs.bcs
VOLGRP=vgbackuppc
LVORIGIN=backuppc
LVSNAP=backuppc-snap
LVSIZE=50G
ISCSI_TARGET="iqn.2016.bcs.delta.backup:backuppc"
ISCSI_PATH="/dev/disk/by-path/ip-10.50.2.120\:3260-iscsi-iqn.2016.bcs.delta.backup\:backuppc-lun-0" # ../../sdd
ISCSI_CMD="/usr/bin/iscsiadm -m node --target $ISCSI_TARGET --portal 10.50.2.120" # options --login | --logout

### check log folder
if [[ ! -d $LOGDIR ]];
  then
    mkdir -p $LOGDIR
  if [[ ! $? -eq 0 ]];
    then
      echo "can not create log folder, aborting!"
      exit 1
  fi
fi

### create logfile
printf "$(date)\n\n" > $LOG

### connect to iSCSI target
printf "logout from possible previous session $ISCSI_TARGET\n\n" >> $LOG
$ISCSI_CMD --logout >> $LOG
sleep 5

#exit 1
printf "connecting to iSCSI target $ISCSI_TARGET\n\n" >> $LOG
$ISCSI_CMD --login >> $LOG
if [[ ! $? -eq 0 ]];
  then
    printf "connecting to iSCSI target $ISCSI_TARGET failed\n\n" >> $LOG
    exit 1
fi
sleep 5

### check iSCSI path
while [ ! -e /dev/disk/by-path/ip-10.50.2.120\:3260-iscsi-iqn.2016.bcs.delta.backup\:backuppc-lun-0 ];
  do
    sleep 1
done
sleep 5

### stop BackupPC process
printf "\n" >> $LOG
printf "stopping BackupPC process on backuppc1.delta.bcs\n\n" >> $LOG

if [[ -f "$PID" ]];
  then
    service backuppc stop
      if [[ $? -eq 0 ]];
        then
          sleep 5
          printf "successfully stopped BackupPC\n\n" >> $LOG
          umount -l /var/lib/backuppc # lazy unmount
            if [[ $? -eq 0 ]];
              then
                printf "lazy unmount on /var/lib/backuppc successfull\n\n" >> $LOG
              else
                printf "lazy unmount on /var/lib/backuppc failed, aborting!\n\n" | tee -a $LOG | mail -s "[$CUSTOMER] backuppc pool unmount failed $(date +%Y%m%d\ %H:%M:%S)" $MAIL
                service backuppc start || printf "something went wrong here, check BackupPC process! aborting\n\n" | tee -a $LOG | mail -s "[$CUSTOMER] starting backuppc failed $(date +%Y%m%d\ %H:%M:%S)" $MAIL
                $ISCSI_CMD --logout >> $LOG
            fi
        else
          printf "stopping BackupPC failed, aborting! check service on backuppc1.delta.bcs\n\n" | tee -a $LOG | mail -s "[$CUSTOMER] stop backuppc failed $(date +%Y%m%d\ %H:%M:%S)" $MAIL
          $ISCSI_CMD --logout >> $LOG
          exit 1
      fi
  else
    printf "BackupPC is not running\n\n" >> $LOG
fi

### check/create snapshot
if [[ -L "/dev/mapper/$VOLGRP-$LVORIGIN--snap" ]];
  then
    printf "Existing snapshot detected, $(lvs | grep "$LVSNAP" | awk '{ print $6 }')% used, removing\n\n" >> $LOG
    lvremove -f /dev/$VOLGRP/$LVSNAP >> $LOG
    printf "\n" >> $LOG
      if [[ ! $? -eq 0 ]];
        then
          printf "\n" >> $LOG
          printf "!!! can not remove snapshot, aborting!\n\n" >> $LOG
          $ISCSI_CMD --logout >> $LOG
          exit 1
      fi
    sleep 5
    printf "creating snapshot $LVSNAP\n" >> $LOG
    lvcreate -s -L $LVSIZE -n $LVSNAP /dev/$VOLGRP/$LVORIGIN >> $LOG
    printf "\n" >> $LOG
      if [[ ! $? -eq 0 ]];
        then
          printf "\n" >> $LOG
          printf "!!! can not create snapshot, aborting!\n\n exit 1" >> $LOG
          $ISCSI_CMD --logout >> $LOG
        exit 1
      fi
    sleep 5
  else
    printf "creating snapshot $LVSNAP\n" >> $LOG
    lvcreate -s -L $LVSIZE -n $LVSNAP /dev/$VOLGRP/$LVORIGIN >> $LOG
    printf "\n" >> $LOG
      if [[ ! $? -eq 0 ]];
        then
        printf "\n" >> $LOG
        printf "!!! can not create snapshot, aborting!\n\n" >> $LOG
        $ISCSI_CMD --logout >> $LOG
        exit 1
      fi
    sleep 5
fi

## start BackupPC process
printf "mounting BackupPC pool on /var/lib/backuppc\n\n" >> $LOG
mount /var/lib/backuppc
if [[ ! $? -eq 0 ]];
  then
    printf "mount /var/lib/backuppc failed, check this!" | tee -a $LOG | mail -s "[$CUSTOMER] /var/lib/backuppc mount failed $(date +%Y%m%d\ %H:%M:%S)" $MAIL
    exit 1
  else
    printf "ok\n\n" >> $LOG
fi
printf "start BackupPC process\n\n" >> $LOG
service backuppc start
if [[ $? -eq 0 ]];
  then
    printf "Backuppc started\n\n" >> $LOG
    sleep 5
  else
    printf "BackupPC start failed, check service!" | tee -a $LOG | mail -s "[$CUSTOMER] backuppc service failed $(date +%Y%m%d\ %H:%M:%S)" $MAIL
    exit 1
fi

#printf "#dryrun#\n\n-----\n\n" >> $LOG
printf "creating block based copy on $ISCSI_PATH\n\n" >> $LOG
if dd if=/dev/$VOLGRP/$LVSNAP of=/dev/disk/by-path/ip-10.50.2.120\:3260-iscsi-iqn.2016.bcs.delta.backup\:backuppc-lun-0 bs=16M 2>>$LOG:
#if true
  then
    printf "BackupPC snapshot cloned successfully on $(date +%Y%m%d\ %H:%M:%S)\n\n" | tee -a $LOG | mail -s "[$CUSTOMER] nas backup successful $(date +%Y%m%d\ %H:%M:%S)" $MAIL
  else
    printf "snapshot clone failed\n\n" | tee -a $LOG | mail -s "[$CUSTOMER] nas backup failed $(date +%Y%m%d\ %H:%M:%S)" $MAIL
fi
sleep 5

### remove snapshot
printf "removing snapshot $LVSNAP\n" >> $LOG
lvremove -f /dev/$VOLGRP/$LVSNAP >> $LOG
if [[ ! $? -eq 0 ]];
  then
    printf "\n" >> $LOG
    printf "!!! can not remove snapshot, must be removed manually!\n\n" >> $LOG
    $ISCSI_CMD --logout >> $LOG
    exit 1
fi
sleep 5

### logout from iSCSI target
printf "\n" >> $LOG
printf "logout from iSCSI target\n\n" >> $LOG
$ISCSI_CMD --logout >> $LOG
if [[ ! $? -eq 0 ]];
  then
    printf "\n" >> $LOG
    printf "disconnecting from iSCSI target $ISCSI_TARGET failed\n\n" >> $LOG
    exit 1
fi

printf "\n" >> $LOG
printf "poolbackup created $(date)\n\n" >> $LOG

exit 0
