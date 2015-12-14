#!/bin/bash

###################################################
#                                                 #
#  nasbackup.sh on nebel2                         #
#  automating BackupPC pool backup to iscsi-lun   #
#  using lvm2 snapshot and block based copy       #
#                                                 #
###################################################

### debug
#set -x

LANG=C

### vars
CUSTOMER=bcs

DATE=$(date +%Y%m%d)

LOGDIR=/var/log/poolbackup
LOG=$LOGDIR/nasbackup_$DATE.log

VOLGRP=nebel2group
LVORIGIN=fordrbd_backuppc
LVSNAP=fordrbd_backuppc-snap
LVSIZE=50G

ISCSI_TARGET="iqn.2012.bcs.bcsnas:backuppc"
ISCSI_PATH="/dev/disk/by-path/ip-10.110.1.140\:3260-iscsi-iqn.2012.bcs.bcsnas\:backuppc-lun-0"
ISCSI_CMD="/usr/bin/iscsiadm -m node --target $ISCSI_TARGET --portal 10.110.1.140" # options --login | --logout

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

### check primary/secondary role of backuppc pool and set var for volumegroup
if [[ $(/sbin/drbdadm get-gi backuppc | cut -d":" -f7) -eq 1 ]];
  then
    printf "backuppc pool ist currently in primary role\n\n" >> $LOG
    VOLGRP=nebel2group
  else
    printf "backuppc pool ist currently in secondary role, aborting\n\n" >> $LOG
    exit 1
fi
sleep 5

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
while [ ! -e /dev/disk/by-path/ip-10.110.1.140\:3260-iscsi-iqn.2012.bcs.bcsnas\:backuppc-lun-0 ];
  do
    sleep 1
done
sleep 5

### stop remote BackupPC process
printf "\n" >> $LOG
printf "stopping remote BackupPC process on backuppc1.bcs.bcs\n\n" >> $LOG
ssh root@backuppc1.bcs.bcs -- /bin/bash -c /usr/local/sbin/stop_backuppc.sh
if [[ ! $? -eq 0 ]];
  then
    printf "stopping BackupPC failed, aborting! check service on backuppc1.bcs.bcs\n\n" >> $LOG
    $ISCSI_CMD --logout >> $LOG
    exit 1
fi
printf "Backuppc stopped, pool unmounted\n\n" >> $LOG
sleep 5

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
ssh root@backuppc1.bcs.bcs -- /bin/bash -c /usr/local/sbin/start_backuppc.sh
if [[ ! $? -eq 0 ]];
  then
    printf "BackupPC failed to start, check service on backuppc1.bcs.bcs\n\n" >> $LOG
fi
printf "Backuppc started\n\n" >> $LOG
sleep 5

#printf "dryrun\n\n---\n\n" >> $LOG
printf "creating block based copy on $ISCSI_PATH\n\n" >> $LOG
if dd if=/dev/$VOLGRP/$LVSNAP of=/dev/disk/by-path/ip-10.110.1.140\:3260-iscsi-iqn.2012.bcs.bcsnas\:backuppc-lun-0 bs=16M 2>>$LOG:
  then
    printf "snapshot cloned successfully\n\n" | tee -a $LOG | mail -s "[$CUSTOMER] nas backup successful $(date +%H:%M:%S)" root
  else
    printf "snapshot clone failed\n\n" | tee -a $LOG | mail -s "[$CUSTOMER] nas backup failed $(date +%H:%M:%S)" root
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
