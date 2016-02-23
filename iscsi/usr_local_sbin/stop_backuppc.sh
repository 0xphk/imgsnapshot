#!/bin/bash

LANG=C
PID=/var/run/backuppc/BackupPC.pid

if [[ -f "$PID" ]];
  then
    service backuppc stop || exit 1
    sleep 5
    umount -l /var/lib/backuppc || exit 1
fi
exit 0
