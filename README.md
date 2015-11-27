#### shellscript for automating "BackupPC" pool backups with amanda

##### quick features

* based on lvm2 snapshots
* block based for faster backup and restore
* using lzop compression
* tests most success/fail cases
* quick and dirty logging feature
* redump if last amdump failed
* using pv is slightly faster than dd

##### common vars

* logging: path, filename
* snapshot: size, name, origin
* various: pidfile, backupfile, date, customer

##### checks

* logdir
* BackupPC process (pidfile)
* old backup in holding disk
* existing snapshot
* last amdump status

##### todo

* ~~add var for volgroup~~
* rewriting logging 
* testing redump
* removing debug helper
* suppress stderr output
