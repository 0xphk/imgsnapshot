#!/bin/bash

LANG=C
PID=/var/run/backuppc/BackupPC.pid

if [[ ! -f "$PID" ]];
  then
    service backuppc start || exit 1
fi
exit 0
