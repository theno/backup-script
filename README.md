# backup-script

Yet another simple backup script based on rsync.  Suited for my needs.

For daily backup runs.

Features:
 * be simple (as possible)
 * use hardlinks to save disc space
 * requires a minimum of maintenance work, therefore
 * remove old backups if low on disc space, with respect of a:
   * fine grained short history:
     try to keep at least the recent n backups (eg. up to 7)
   * coarse grained monthly history:
     try to keep first backup in a month
 * this strategy keeps as many backups as possible
 * create markdown formatted log files
 * optionally, consume flag files which signal if a new backup is required
 * optionally, send backup log mail to admin
 * optionally, send summary mail to user

## Setup

### Requirements

`run-backup.sh` needs: `bash`, `postfix`, `rsync`, `tee`

When installing on a debian flavored you could install them by running:

```sh
sudo apt install  bash postfix rsync tee
```

## Usage

```sh
bash run-backup.sh
```
