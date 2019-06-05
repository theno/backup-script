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

SOURCE_DIRS=()
ARCHIVE_DIR='./backups'

MIN_FREE_GB=100
# MIN_FREE_GB=30

NUMBER_OF_RECENT_BACKUPS=7

# if low on disc space
ALWAYS_KEEP_AT_LEAST=2
# backups

### configuration ends here


low_on_disc_space () {
    local bytes_required=$(expr $MIN_FREE_GB \* 1024 \* 1024)
    local bytes_available=$(df --output=avail . | awk 'NR==2{print $1}')

    (($bytes_required >= $bytes_available))
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
    local archive_dir="$1"

    echo -e "# remove archived backups in $archive_dir\\n"

    if low_on_disc_space; then
        while low_on_disc_space; do

            local dates=( $(special_order "$archive_dir") )

            if [[ "${#dates[@]}" -le "$ALWAYS_KEEP_AT_LEAST" ]]; then
                echo "only ${#dates[@]} backups exist, abort"
                echo 'no space left for a new backup'
                echo 'LOW ON DISC SPACE'
                break
            fi

            to_remove="$archive_dir/${dates[0]}"
            echo -n "remove $to_remove ..."
            rm -rf "$to_remove"
            echo ' done'
        done
    else
        echo "nothing to do"
    fi
}

main () {
    # check if archive and source dirs exist
    # create backup (when enough disc space)
    remove_backups $ARCHIVE_DIR
    # show/email status
}

main
