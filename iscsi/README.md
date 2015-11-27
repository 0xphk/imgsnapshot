#### shellscript for automating "BackupPC" pool backups to iscsi-lun

##### quick features

* based on lvm2 snapshots
* block based for faster backup and restore
* using lzop compression
* tests most success/fail cases
* quick and dirty logging feature

##### common vars

* logging: path, filename
* snapshot: size, name, origin
* various: iscsi, backupfile, date, customer

##### checks

* logdir
* BackupPC process (pidfile)
* old backup in holding disk
* existing snapshot

##### todo

* more testing
