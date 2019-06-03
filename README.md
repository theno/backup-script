# backup-script

Yet another simple backup script based on rsync.  Suited for my needs.

For daily backup runs.

Features:
 * use hardlinks to save disc space
 * requires a minimum of maintenance work, therefore
 * remove old backups if low on disc space, with respect of a:
   * fine grained short history:
     try to keep at least the latest n backups (eg. up to 7)
   * coarse grained monthly history:
     try to keep first backup in a month
 * send short status mails

## Usage

```sh
./run-backup.sh
```
