#### shellscript for automating "BackupPC" pool backups to iscsi-lun

##### quick features

* block based on lvm2 snapshots
* ~~using lzop compression~~
* tests most success/fail cases
* quick and dirty logging feature

##### common vars

* logging: path, filename
* snapshot: size, name, origin
* various: iscsi, ~~backupfile~~, date, customer

##### checks

* logdir
* ~~drbd resource role (primary/secondary)~~
* remote BackupPC process (pidfile)
* unmount pool to preserve clean fs
* ~~old backup in holding disk~~
* existing snapshot

##### todo

* more testing
* determine best blocksize
* fixing comments
* robust logging
