#!/bin/bash

###################################################
#                                                 #
#  nasbackup.sh on nebel1                         #
#  automating BackupPC pool backup to iscsi-lun   #
#  using lvm2 snapshot and lzop compressed image  #
#                                                 #
###################################################

### debug
#set -x

LANG=C

### vars
DATE=$(date +%Y%m%d)

VOLGRP=nebel1group
LVORIGIN=fordrbd_backuppc
LVSNAP=fordrbd_backuppc-snap
LVSIZE=50G

ISCSI_TARGET="iqn.2012.bcs.bcsnas:backuppc"
ISCSI_PATH="/dev/disk/by-path/ip-10.110.1.140\:3260-iscsi-iqn.2012.bcs.bcsnas\:backuppc-lun-0-part1"
ISCSI_CMD="iscsiadm -m node --target $ISCSI_TARGET --portal 10.110.1.140" # --login | --logout

LOGDIR=/var/log/poolbackup
LOG=$LOGDIR/nasbackup_$DATE.log

MOUNT=/tmp/nas
BACKUPFILE=nasbackup_$DATE.lz
CUSTOMER=bcs

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
if [[ $(drbdadm get-gi backuppc | cut -d":" -f7) -eq 1 ]];
  then
    printf "backuppc pool ist currently in primary role\n\n" >> $LOG
    VOLGRP=nebel1group
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
while [ ! -e /dev/disk/by-path/ip-10.110.1.140\:3260-iscsi-iqn.2012.bcs.bcsnas\:backuppc-lun-0-part1 ];
  do
    sleep 1
done
sleep 5

### check mountpoint
if [[ ! -d $MOUNT ]];
  then
    mkdir -p $MOUNT
fi

### stop remote BackupPC process
printf "\n" >> $LOG
printf "stopping remote BackupPC process on backuppc1.bcs.bcs\n\n" >> $LOG
ssh root@backuppc1.bcs.bcs -- /bin/bash -c /var/lib/backuppc/bin/stop_backuppc.sh
if [[ ! $? -eq 0 ]];
  then
    printf "stopping BackupPC failed, aborting! check service on backuppc1.bcs.bcs\n\n" >> $LOG
    exit 1
fi
printf "Backuppc stopped\n\n" >> $LOG
sleep 5

### check/mount iscsi-lun
if [[ -e /dev/disk/by-path/ip-10.110.1.140\:3260-iscsi-iqn.2012.bcs.bcsnas\:backuppc-lun-0-part1 ]];
  then
    if mount | grep -e "on /tmp/nas" > /dev/null;
      then
        printf "iSCSI-lun already mounted on $MOUNT, going on\n\n" >> $LOG
      else
        printf "mounting iSCSI-lun $ISCSI_TARGET-lun-0\n\n" >> $LOG
        mount /dev/disk/by-path/ip-10.110.1.140\:3260-iscsi-iqn.2012.bcs.bcsnas\:backuppc-lun-0-part1 $MOUNT
          if [[ ! $? -eq 0 ]];
            then
              printf "mount failed\n\n" >> $LOG
          fi
    fi
  else
    printf "iSCSI-lun $ISCSI_PATH not found, check connection\n\n" >> $LOG
    exit 1
fi
sleep 5

### check/create snapshot
if [[ -L "/dev/mapper/$VOLGRP-$LVORIGIN--snap" ]];
  then
    printf "Existing snapshot detected, $(lvs | grep "$LVSNAP" | awk '{ print $6 }')% used, removing\n\n" >> $LOG
    lvremove -f /dev/$VOLGRP/$LVSNAP >> $LOG
    printf "\n" >> $LOG
  if [[ ! $? -eq 0 ]];
    then
      printf "\n"
      printf "!!! can not remove snapshot, aborting!\n\n" >> $LOG
      exit 1
  fi
    sleep 5
    printf "creating snapshot $LVSNAP\n" >> $LOG
    lvcreate -s -L $LVSIZE -n $LVSNAP /dev/$VOLGRP/$LVORIGIN >> $LOG
    printf "\n" >> $LOG
  if [[ ! $? -eq 0 ]];
    then
      printf "\n"
      printf "!!! can not create snapshot, aborting!\n\n exit 1" >> $LOG
      exit 1
  fi
    sleep 5
  else
    printf "creating snapshot $LVSNAP\n" >> $LOG
    lvcreate -s -L $LVSIZE -n $LVSNAP /dev/$VOLGRP/$LVORIGIN >> $LOG #|| printf "snapshot failed" && exit 1
    printf "\n" >> $LOG
  if [[ ! $? -eq 0 ]];
    then
      printf "\n" >> $LOG
      printf "!!! can not create snapshot, aborting!\n\n" >> $LOG
      exit 1
  fi
    sleep 5
fi

## start BackupPC process
ssh root@backuppc1.bcs.bcs -- /bin/bash -c /var/lib/backuppc/bin/start_backuppc.sh
if [[ ! $? -eq 0 ]];
  then
    printf "BackupPC failed to start, check service on backuppc1.bcs.bcs\n\n" >> $LOG
fi
printf "Backuppc started\n\n" >> $LOG
sleep 5

### cleanup old imagefile
printf "cleanup old files\n\n" >> $LOG
if ls /tmp/nas/nasbackup* > /dev/null 2>&1;
  then
    printf "old backupfile found, removing\n\n" >> $LOG
    rm -f /tmp/nas/nasbackup*
  else
    printf "nothing to clean up\n\n" >> $LOG
fi
sleep 5

### create imagefile

### testing with small image
#printf "create testimage\n\n" >> $LOG
#dd if=/dev/$VOLGRP/$LVSNAP of=$MOUNT/$BACKUPFILE bs=16M count=100
#printf "image created successfully\n\n" >> $LOG
#sleep 5

printf "creating lzop image on $MOUNT\n\n" >> $LOG
#if pv -q /dev/$VOLGRP/$LVSNAP | lzop | cat > $MOUNT/$BACKUPFILE 2>>$LOG;
if dd if=/dev/$VOLGRP/$LVSNAP bs=16M 2>>$LOG | lzop | dd of=$MOUNT/$BACKUPFILE 2>>$LOG;
  then
    printf "backuppc pool image created successfully\n\n" | tee -a $LOG | mail -s "\[$CUSTOMER\] nas backup successful $(date +%H:%M:%S)" root
  else
    printf "backuppc pool image failed, check logfile\n\n" | tee -a $LOG | mail -s "\[$CUSTOMER\] nas backup failed $(date +%H:%M:%S)" root
fi
sleep 5

### remove snapshot
printf "removing snapshot $LVSNAP\n" >> $LOG
lvremove -f /dev/$VOLGRP/$LVSNAP >> $LOG
if [[ ! $? -eq 0 ]];
  then
    printf "\n"
    printf "!!! can not remove snapshot, must be removed manually!\n\n" >> $LOG
    exit 1
fi
sleep 5

### unmount iSCSI-lun
printf "unmountig $MOUNT" >> $LOG
umount $MOUNT
if [[ ! $? -eq 0 ]];
  then
    printf "unmount failed\n\n" >> $LOG
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
printf "backupfile created $(date)\n\n" >> $LOG

exit 0
