#!/bin/bash

# workflow
#
# * if exists FLAG_NEW_BACKUP_EXISTS (and not FLAG_NEW_BACKUP_IN_PROGRESS)
#   * do backup
#     * find latest (if symlink exists)
#     * rsync to YYYY-MM-DD
#       * use hardlink to latest
#   * remove old backups
#     * special order (from high to low)
#       * latest n backups
#       * backups with lowest day by month
#       * rest
#     * start with lowest backup
#       * till minimum required free disk space achieved
