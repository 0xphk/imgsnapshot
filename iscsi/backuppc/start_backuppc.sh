#!/bin/bash

LANG=C
PID=/var/run/backuppc/BackupPC.pid

if [[ ! -f "$PID" ]];
  then
    mount /var/lib/backuppc || exit 1
    sleep 5
    service backuppc start || exit 1
fi
exit 0
