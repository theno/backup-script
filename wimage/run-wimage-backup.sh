#!/bin/bash

# requirements: wimlib: apt-get install wimtools
# will (always) consume flags

### configuration begins here

SOURCE_WIMAGES=(
    '/path/to/install.wim'
#    '/path/to/another/install.wim'
)

ARCHIVE_WIMAGE='/path/to/merged/install.wim'
ARCHIVE_WIMAGE_COPY='/path/to/copy/of/merged/install.wim'

MIN_FREE_DISC_SPACE_IN_GB=100

# if low on disc space
ALWAYS_KEEP_AT_LEAST=7
# wimages

### configuration ends here


# Return `true` only if FLAG_NEW_WIMAGE_EXISTS exists and
# not a FLAG_NEW_WIMAGE_IN_PROGRESS, `false` else
flags_signal_a_new_backup_job () {
    local flags_dir="$1"
    [ -f "$flags_dir/FLAG_NEW_WIMAGE_EXISTS" ] && \
        [ ! -f "$flags_dir/FLAG_NEW_WIMAGE_IN_PROGRESS" ]
}


low_on_disc_space () {
    local bytes_required=$(expr $MIN_FREE_DISC_SPACE_IN_GB \* 1024 \* 1024)
    local bytes_available=$(df --output=avail . | awk 'NR==2{print $1}')

    (($bytes_required >= $bytes_available))
}


check () {
    echo -e '\n# check\n'

    local error=false

    if [ "${#SOURCE_WIMAGES[@]}" -eq "0" ]; then
        echo "* no SOURCE_WIMAGES=('/path/to/install.wim' ...) configured"
        error=true
    fi
    for source_wimage in "${SOURCE_WIMAGES[@]}"; do
        local source_dir="$(dirname "$source_wimage")"
        if [ ! -d "$source_dir" ]; then
            echo "* directory of SOURCE_WIMAGES=('$source_dir') does not exist"
            error=true
        elif [ ! -r "$source_dir" ]; then
            echo "* no permission to read directory of SOURCE_WIMAGES=('$ource_wimage') "
            error=true
        fi
    done

    for source_wimage in "${SOURCE_WIMAGES[@]}"; do
        local source_dir="$(dirname "$source_wimage")"
        if [ ! -f "$source_dir/FLAG_NEW_WIMAGE_EXISTS" ] && \
                [ ! -f "$source_dir/FLAG_NEW_WIMAGE_IN_PROGRESS" ] && \
                [ ! -f "$source_dir/FLAG_LATEST_ARCHIVED" ]; then
            echo "* WARNING: no flag files exist in '$source_dir'"
            # only warn, do not set error=true
        fi
        if flags_signal_a_new_backup_job "$source_dir"; then
            if [ ! -w "$source_dir" ]; then
                echo -n "* could not move $source_dir/FLAG_NEW_WIMAGE_EXISTS "
                echo "to $source_dir/FLAG_LATEST_ARCHIVED (check permissions)"
                error=true
            fi
        fi
    done

    local archive_dir="$(dirname "$ARCHIVE_WIMAGE")"
    if [ ! -d "$archive_dir" ]; then
        echo "* directory of ARCHIVE_WIMAGE='$ARCHIVE_WIMAGE' does not exist"
        error=true
    elif [ -f "$ARCHIVE_WIMAGE" ] && [ ! -w "$ARCHIVE_WIMAGE" ]; then
        echo "* cannot write to ARCHIVE_WIMAGE='$ARCHIVE_WIMAGE' (check permissions)"
        error=true
    fi

    local archive_copy_dir="$(dirname "$ARCHIVE_WIMAGE_COPY")"
    if [ ! -d "$archive_copy_dir" ]; then
        echo "* directory of ARCHIVE_WIMAGE_COPY='$ARCHIVE_WIMAGE_COPY' does not exist"
        error=true
    elif [ ! -w "$ARCHIVE_WIMAGE_COPY" ]; then
        echo "* cannot write to ARCHIVE_WIMAGE_COPY='$ARCHIVE_WIMAGE_COPY' (check permissions)"
        error=true
    fi

    if low_on_disc_space; then
        echo "* file system for ARCHIVE_WIMAGE='$ARCHIVE_WIMAGE' is low on free disc space"
        if ! $error; then
            remove_wimages
            if low_on_disc_space; then
                error=true
            fi
        fi
    fi

    if $error; then
        echo -e '\nabort'
        exit 1
    else
        echo 'okay'
    fi
}


run ()  {
    cmd="$1"
    echo "$cmd"
    cmd="time $cmd"
    eval "$cmd"
    return_code=$?
    if [ "$return_code" -gt "0" ]; then
        echo "[$return_code]"
        summary
        echo ''
        echo -e '# ERROR\n'
        echo -e "error executing command:\n\n'''"
        echo -e "$cmd\n[$return_code]\n'''"
        exit $return_code
    fi
}


archive_wimage () {
    local source_wimage="$1"

    echo -e "\n## archive $1\n"
    local image_archived=false
    local source_dir="$(dirname "$source_wimage")"
    if flags_signal_a_new_backup_job "$source_dir"; then
        if [ -f "$source_wimage" ]; then
            # FIXME: export latest wimage instead of first
            run "wimexport $source_wimage 1 "$ARCHIVE_WIMAGE"  --no-check"
            mv "$source_dir/FLAG_NEW_WIMAGE_EXISTS" "$source_dir/FLAG_LATEST_ARCHIVED"
            image_archived=true
        else
            echo "flags signal to archive a new wimage"
            echo "but source-wimage not exists at '$source_wimage'"
        fi
    else
        echo 'nothing to do'
    fi
    $image_archived
}


archive_wimages () {
    echo -e '\n# archive wimages'
    local images_archived=false
    for source_wimage in "${SOURCE_WIMAGES[@]}"; do
        if archive_wimage "$source_wimage"; then
            images_archived=true
        fi
    done
    $images_archived
}


remove_wimages () {
    echo -e '\n# remove wimages from archive\n'
    if [ -f "$ARCHIVE_WIMAGE" ]; then
        if low_on_disc_space; then
            while low_on_disc_space; do
                count="$(wiminfo "$ARCHIVE_WIMAGE" | sed -n 's/^Image Count:\s\+\([0-9]\+\)/\1/p')"
                if [ "$count" -le "$ALWAYS_KEEP_AT_LEAST" ]; then
                    echo "only $count wimages exist (skip)"
                    echo 'no space left for a new wimage'
                    echo 'LOW ON DISC SPACE'
                    break
                fi
                break
                run "wimdelete "$ARCHIVE_WIMAGE" 1 --unsafe-compact"
            done
        else
            echo -e 'nothing to remove\n'
        fi
        run "wimoptimize "$ARCHIVE_WIMAGE" --check --unsafe-compact"
    else
        echo "$ARCHIVE_WIMAGE does not exist"
    fi
}


copy_archive () {
    echo -e '\n# copy wimages archive\n'
    if [ -f "$ARCHIVE_WIMAGE" ]; then
        run "rsync --progress --human-readable "$ARCHIVE_WIMAGE"  "$ARCHIVE_WIMAGE_COPY""
    else
        echo "$ARCHIVE_WIMAGE does not exist"
    fi
}


summary () {
    echo -e '\n# summary\n'

    echo -e '## configuration\n'
    echo -e "'''\nSOURCE_WIMAGES=("
    for source_wimage in ${SOURCE_WIMAGES[@]}; do
        echo "    '$source_wimage'"
    done
    echo ')'
    echo "ARCHIVE_WIMAGE='$ARCHIVE_WIMAGE'"
    echo "ARCHIVE_WIMAGE_COPY='$ARCHIVE_WIMAGE_COPY'"
    echo "MIN_FREE_DISC_SPACE_IN_GB=$MIN_FREE_DISC_SPACE_IN_GB"
    echo "ALWAYS_KEEP_AT_LEAST=$ALWAYS_KEEP_AT_LEAST"
    echo "'''"

    echo -e '\n## source wimages'
    for source_wimage in "${SOURCE_WIMAGES[@]}"; do
        echo -e "\n'''"
        ls -hl "$source_wimage"
        local source_dir="$(dirname "$source_wimage")"
        for i in $source_dir/{FLAG_*,START,END}; do
            echo -n "$i  "
            cat $i
        done
        echo "'''"
    done

    echo -e '\n## timing\n'
    echo "* start: $START"
    echo "* end:   $(date "+%F %T")"
    local h="$((${SECONDS}/3600))"
    local m="$((${SECONDS}%3600/60))"
    local s="$((${SECONDS}%60))"
    printf "* duration: %02d:%02d:%02d [hh:mm:ss]\n" $h $m $s

    echo -e '\n## archived wimages\n'
    echo "'''"
    wiminfo "$ARCHIVE_WIMAGE" | grep -A1 '^Index:'
    echo ''
    wiminfo "$ARCHIVE_WIMAGE" | grep '^Image Count:'
    echo ''
    ls -hs "$ARCHIVE_WIMAGE"
    ls -hs "$ARCHIVE_WIMAGE_COPY"
    echo "'''"

    echo -e '\n## disc space (`df -h $ARCHIVE_IMAGE $ARCHIVE_IMAGE_COPY`)\n'
    echo -e "'''\n$(df -h $ARCHIVE_WIMAGE $ARCHIVE_WIMAGE_COPY)\n'''"
}


main () {
    check
    local images_archived=archive_wimages
    if $images_archived; then
        remove_wimages
        copy_archive
    fi
    summary
}


SECONDS=0  # reset seconds counter (bash built-in), used in summary()
START="$(date "+%F %T")"  # used in summary()

main
