#!/bin/bash


### configuration begins here

SOURCE_DIRS=(
    'source-dir'
#    '/path/to/another/source-dir'
)

ARCHIVE_DIR='./backups'
# ARCHIVE_DIR='/path/to/archive/dir'

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

CONSUME_FLAGS=false
FLAGS_DIR='/path/to/flag-files/dir'

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

    if $CONSUME_FLAGS; then
        if [[ ! -d "$FLAGS_DIR" ]]; then
            echo "FLAGS_DIR='$FLAGS_DIR' is not a directory"
            error=true
        fi
    fi

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

    local create=false

    if $CONSUME_FLAGS; then
        # only create backup if FLAG_NEW_BACKUP_EXISTS and
        # not a FLAG_NEW_BACKUP_IN_PROGRESS
        if [ -f "$FLAGS_DIR/FLAG_NEW_BACKUP_EXISTS" ] && \
                [ ! -f "$FLAGS_DIR/FLAG_NEW_BACKUP_IN_PROGRESS" ]; then
            create=true
            BACKUP_DATE="$(cat $FLAGS_DIR/FLAG_NEW_BACKUP_EXISTS)"
        fi
    else
        create=true
    fi

    LOGFILE_RSYNC="$ARCHIVE_DIR/$BACKUP_DATE/rsync.log"

    if $create; then
        local rsync="$(create_rsync_cmd $BACKUP_DATE)"

        local logfile_rsync_tmp="$ARCHIVE_DIR/rsync.${BACKUP_DATE}.log"

        echo "$rsync" > "$logfile_rsync_tmp"
        run "$rsync  &>> $logfile_rsync_tmp"

        run "mv $logfile_rsync_tmp  $LOGFILE_RSYNC"
        echo -e '\ndone'
        if $CONSUME_FLAGS; then
            mv "$FLAGS_DIR/FLAG_NEW_BACKUP_EXISTS"  \
                "$FLAGS_DIR/FLAG_LATEST_ARCHIVED"
        fi
    else
        echo 'nothing to do'
    fi
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


summary () {
    local start="$1"
    echo -e '\n# summary\n'

    echo "created backup: $BACKUP_DATE"

    echo -e '\n## timing\n'
    echo "* start: $start"
    echo "* end:   $(date "+%F %T")"
    local h="$((${SECONDS}/3600))"
    local m="$((${SECONDS}%3600/60))"
    local s="$((${SECONDS}%60))"
    printf "* duration: %02d:%02d:%02d [hh:mm:ss]\n" $h $m $s

    echo -e '\n## disc space (`df -h $ARCHIVE_DIR`)\n'
    echo -e "'''\n$(df -h $ARCHIVE_DIR)\n'''"
}


main () {
    local start="$(date "+%F %T")"

    check_dirs
    create_backup
    remove_backups
    summary "$start"
    # show/email status
}


SECONDS=0  # used in summary()
BACKUP_DATE="$(date +%F)"  # used in create_backup(), summary()
LOGFILE_RSYNC=''  # used in create_backup(), summary()


main
