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


### configuration begins here

SOURCE_DIRS=(
    'source-dir'
#    '/path/to/another/source-dir'
)

ARCHIVE_DIR='./backups'

# MIN_FREE_DISC_SPACE_IN_GB=100
MIN_FREE_DISC_SPACE_IN_GB=30

NUMBER_OF_RECENT_BACKUPS=7

# if low on disc space
ALWAYS_KEEP_AT_LEAST=2
# backups

RSYNC_CMD='/usr/bin/rsync'
RSYNC_COMPARE_CHECKSUM=false
RSYNC_EXCLUDE=(
#    'Cache'
#    'parent.lock'
#    'Temp*'
)

### configuration ends here


low_on_disc_space () {
    local bytes_required=$(expr $MIN_FREE_DISC_SPACE_IN_GB \* 1024 \* 1024)
    local bytes_available=$(df --output=avail . | awk 'NR==2{print $1}')

    (($bytes_required >= $bytes_available))
}

check_dirs () {
    local error=false

    echo -e '# check dirs\n'

    if [[ "${#SOURCE_DIRS[@]}" -eq "0" ]]; then
        echo "no SOURCE_DIRS=('/path/to/source' ...) configured"
        error=true
    fi

    for source_dir in "${SOURCE_DIRS[@]}"; do
        if [[ ! -d "$source_dir" ]]; then
            echo "SOURCE_DIRS=('$source_dir') is not a directory"
            error=true
        fi
    done

    if [[ ! -d "$ARCHIVE_DIR" ]]; then
        echo "ARCHIVE_DIR='$ARCHIVE_DIR' is not a directory"
        error=true
    fi

    if low_on_disc_space; then
        echo "ARCHIVE_DIR='$ARCHIVE_DIR' is low on free disc space"
        error=true
    fi

    if $error; then
        echo 'abort'
        exit 1
    else
        echo 'okay'
    fi
}


latest_backup () {
    eval "ls $ARCHIVE_DIR | tail -n1"
}


create_rsync_cmd () {
    local date="$1"
    local dest_dir="$ARCHIVE_DIR/$date"

    local rsync="$RSYNC_CMD --archive --verbose"

    if $RSYNC_COMPARE_CHECKSUM; then
        rsync="$rsync --checksum"
    fi

    for exclude in ${RSYNC_EXCLUDE[@]}; do
        rsync="$rsync --exclude=$exclude"
    done

    local latest=$(latest_backup)
    if [[ "$latest" ]] && [ "$latest" != "$date" ]; then
        rsync="$rsync --link-dest=$ARCHIVE_DIR/$latest"
    fi

    for source_dir in ${SOURCE_DIRS[@]%/}; do
        rsync="$rsync  $source_dir"
    done

    echo "$rsync  $dest_dir"
}


run () {
    local cmd=$1
    echo "$cmd"
    eval "$cmd"
    echo "[$?]"
}


create_backup () {
    echo -e '\n# create backup\n'

    local date="$(date +%F)"
    local rsync="$(create_rsync_cmd $date)"

    echo "$rsync" > "/tmp/backup-script_rsync.log"
    run "$rsync  &>> /tmp/backup-script_rsync.log"

    run "mv /tmp/backup-script_rsync.log  $ARCHIVE_DIR/$date/rsync.log"
    echo -e '\ndone'
}


# For example, if the archive contains this
# backups:            special_order returns:
# ├── 2019-01-01           2019-02-12 \_
# ├── 2019-02-11           2019-03-02 / rest
# ├── 2019-02-12           2019-01-01  \
# ├── 2019-03-01           2019-02-11   |- firsts in a month
# ├── 2019-03-02           2019-03-01  /
# ├── 2019-03-03           2019-03-03 \
# ├── 2019-03-04           2019-03-04  |
# ├── 2019-03-05           2019-03-05  |
# ├── 2019-03-06           2019-03-06  |- recent backups
# ├── 2019-03-07           2019-03-07  |
# ├── 2019-03-08           2019-03-08  |
# └── 2019-03-09           2019-03-09 /
#
special_order () {
    local archive_dir="$1"
    local ymds=( $(ls "$archive_dir") )

    local special_order="${ymds[@]}"

    if [[ "$NUMBER_OF_RECENT_BACKUPS" -le "${#ymds[@]}" ]]; then

        local index=$(expr ${#ymds[@]} - $NUMBER_OF_RECENT_BACKUPS)

        local recent=( ${ymds[@]:$index} )
        local rest=( ${ymds[@]:0:$index} )

        # yms: year-month array, eg.
        # yms=(2018-12 2019-01 2019-02 2019-03 2019-04 2019-05)
        # parameter extension on arrays: https://stackoverflow.com/a/37698203
        # unique values from an array https://stackoverflow.com/a/13648438
        local yms=( \
            $(echo "${rest[@]%-*}" | tr ' ' '\n' | sort -u | tr '\n' ' ') )

        # firsts: first in a month array, eg.
        # firsts=(2018-12-01 2019-01-01 ... 2019-05-01)
        local firsts=()
        for ym in "${yms[@]}"; do
            # filtering an array: https://stackoverflow.com/a/40375567
            for index in "${!rest[@]}"; do
                [[ ${rest[$index]} =~ ^$ym- ]] && \
                    # ym prefix matches, so add element to array firsts
                    firsts+=("${rest[$index]}") && \
                    # and remove it from array rest
                    unset -v 'rest[$index]' && \
                    rest=("${rest[@]}") && \
                    break
            done
        done

        special_order=("${rest[@]}" "${firsts[@]}" "${recent[@]}")
    fi

    echo "${special_order[@]}"
}


# Remove "old" backups in special_order when low on disc space.
#
remove_backups () {
    echo -e '\n# remove archived backups\n'

    if low_on_disc_space; then
        while low_on_disc_space; do

            local dates=( $(special_order "$ARCHIVE_DIR") )

            if [[ "${#dates[@]}" -le "$ALWAYS_KEEP_AT_LEAST" ]]; then
                echo "only ${#dates[@]} backups exist, abort"
                echo 'no space left for a new backup'
                echo 'LOW ON DISC SPACE'
                break
            fi

            to_remove="$ARCHIVE_DIR/${dates[0]}"
            echo -n "remove $to_remove ..."
            rm -rf "$to_remove"
            echo ' done'
        done
    else
        echo "nothing to do"
    fi
}


main () {
    check_dirs
    create_backup
    remove_backups
    # show/email status
}


main
