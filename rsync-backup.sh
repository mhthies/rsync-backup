#!/bin/bash

#COLOR definitions
COLOR_ERR=$'\033[0;31m'
COLOR_WARN=$'\033[0;33m'
COLOR_SUCC=$'\033[0;32m'
COLOR_INFO=$''
COLOR_QUEST=$'\033[0;34m'
COLOR_RESET=$'\033[0m'

DAYPREFIX="day-"
WEEKPREFIX="weekly-"
MONTHPREFIX="monthly-"
LATEST_LINK="latest"
UNFINISHED_LINK="unfinished"
EMPTY_DIR="empty" # Used for dryruns
DRYRUN_LIST="transferlist.txt"

#How long to keep daily and weekly backups (in days)
KEEP_DAILY=14
KEEP_WEEKLY=60


# The main function
main() {
    # Check parameters
    SOURCE=
    DEST=
    FILTER=
    INTERACTIVE=true
        
    while getopts "s:d:f:ih" OPT; do
        case $OPT in
            s) SOURCE=$OPTARG;;
            d) DEST=$OPTARG;;
            f) FILTER=$OPTARG;;
            i) INTERACTIVE=false;;
            h) display-help
               exit;;
        esac
    done
    
    # Check parameters
    if [ ! -d "$SOURCE" ]; then
        echo $COLOR_ERR"Error: Source not set or no existing directory. Exiting"$COLOR_RESET
        exit 1
    fi
    if [ ! -d "$DEST" ]; then
        echo $COLOR_ERR"Error: Destination not set or no existing directory. Exiting"$COLOR_RESET
        exit 1
    fi
    if [ ! -z "$FILTER" ] && [ ! -f "$FILTER" ]; then
        echo $COLOR_ERR"Error: Filter file does not exist. Exiting"$COLOR_RESET
        exit 1
    fi
    
    
    # Check for unfinished backup
    CONTINUE_DIR=
    if [[ "$INTERACTIVE" = true && -L "$DEST/$UNFINISHED_LINK" && -d "$DEST/$UNFINISHED_LINK" ]]; then
        echo $COLOR_WARN"Found unfinished backup in "`readlink "$DEST/$UNFINISHED_LINK"`.$COLOR_RESET
        read -p $COLOR_QUEST"Continue unfinished backup [y/n]? "$COLOR_RESET -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]?$ ]]; then
            CONTINUE_DIR=`readlink "$DEST/$UNFINISHED_LINK"`
        fi
    fi
    # Remove unfinished-link, if existing
    if [[ -L "$DEST/$UNFINISHED_LINK" ]]; then
        rm "$DEST/$UNFINISHED_LINK"
    fi
    
    
    # Check for latest complete backup and build rsync parameters (--link-dest and --exclude-from)
    LINK_ARG=
    if [[ -L "$DEST/$LATEST_LINK" && -d "$DEST/$LATEST_LINK" ]]; then
        echo $COLOR_INFO"Found complete backup in "`readlink "$DEST/$LATESTLINK"`". Using it as source for hard links."$COLOR_RESET
        LINK_ARG="../$LATEST_LINK"
    else
        echo $COLOR_INFO"Could not find existing complete backup. So, we will run a full backup."$COLOR_RESET
    fi
    
    # Get backup target directory
    computeBackupDir
    
    
    # Dryrun
    if [ "$INTERACTIVE" = true ]; then
        read -p $COLOR_QUEST"Perform dry run [y/n]? "$COLOR_RESET -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]?$ ]]; then
            # If we continue an unfinished backup, run dryrun against this backup
            # else use empty directory
            if [ ! -z "$CONTINUE_DIR" ]; then
                DRYRUN_DEST="$DEST/$CONTINUE_DIR"
            else
                if [ ! -d "$DEST/$EMPTY_DIR" ]; then
                    mkdir "$DEST/$EMPTY_DIR"
                fi
                DRYRUN_DEST="$DEST/$EMPTY_DIR"
            fi
            # Now, perform the dryrun
            echo $COLOR_INFO"Starting rsync for dryrun ..."$COLOR_RESET
            rsync -a ${LINK_ARG:+--link-dest="$LINK_ARG"} -n ${FILTER:+--exclude-from="$FILTER"} "$SOURCE/" "$DRYRUN_DEST" --info=NAME,REMOVE,STATS2 --out-format="%o %f (%lB)" > "$DEST/$DRYRUN_LIST"
            result=$?
            # Exit on rsync error while dryrun
            if [ $result != 0 ]; then
                echo $COLOR_ERR"Error: rsync aborted with exit code $result while performing dryrun."$COLOR_RESET
                exit $result
            fi
            
            # Else show dryrun result filelist in less and ask user to continue
            less "$DEST/$DRYRUN_LIST"
            read -p $COLOR_QUEST"Continue with actual backup [y/n]? "$COLOR_RESET -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]?$ ]]; then
                exit 1;
            fi
            rm "$DEST/$DRYRUN_LIST"
        fi
    fi
    
    
    # Create backup destination directory (or move it, if continued backup)
    if [ ! -z "$CONTINUE_DIR" ]; then
        mv "$DEST/$CONTINUE_DIR" "$DEST/$BACKUP_DIR"
    else
        mkdir "$DEST/$BACKUP_DIR"
    fi
    # Create unfinished-link
    ln -sfT "$BACKUP_DIR" "$DEST/$UNFINISHED_LINK"
    
    # Run backup
    echo $COLOR_INFO"Starting rsync for backup ..."$COLOR_RESET
    rsync -a ${LINK_ARG:+--link-dest="$LINK_ARG"} ${FILTER:+--exclude-from="$FILTER"} "$SOURCE/" "$DEST/$BACKUP_DIR"
    result=$?
    # Exit on rsync error
    if [ $result != 0 ]; then
        echo $COLOR_ERR"Error: rsync aborted with exit code $result."$COLOR_RESET
        exit $result
    else
        echo $COLOR_SUCC"rsync exited with success."$COLOR_RESET
    fi
    
    # Rsync finished with success, so remove unfinished-link and (re)create latest-link
    rm "$DEST/$UNFINISHED_LINK"
    ln -sfT "$BACKUP_DIR" "$DEST/$LATEST_LINK"
    
    # Add weekly and monthly link-copies
    copyIfFirstInWeek
    copyIfFirstInMonth
    
    # Delete old backups
    deleteOldDaily
    deleteOldWeekly
}

# Function for showing comandline help
display-help() {
    local bname=$(basename $0)
    cat <<EOF
$bname, automatic versionated backup using rsync.
(c) 2016 Michael Thies <mail@mhthies.de>

Usage:
  $bname -s <SOURCE> -d <DEST> [-i] [-f <FILTER>]

Options:
  -s <SOURCE>
        Source directory. This is the source folder, that will be
        backuped.
        
        Warning: The source path must not include a trailing slash.
  
  -d <DEST>
        Destination directory. The backups are stored in sub-directories
        of the destination directory. Each run of this backup script will
        create a new folder here containing a full snapshot of the source
        direcotry.
        There will also be folders containing weekly and monthly backups
        of the source directory. All unchanged files are only stored once
        on drive and hardlinked between all those folders.
        
        Warning: The destination path must not include a trailing slash.
  
  -f <FILTER>   (optional)
        Path to filter file. This file will be passed to rsync with the
        --exclude-from option. It should contain relative paths inside
        the source directory, that will be excluded from backup.
    
  -i            (optional)
        Disable interactive mode. The user will not be asked for a dry run
        or to continue an incomplete backup.
        
  -h
        Show this help message and exit without doing anything.
EOF
}

# Get name of destination subdirectory for this backup
computeBackupDir() {
    local base_destdir="$DAYPREFIX"`date +%Y-%m-%d`
    BACKUP_DIR="$base_destdir"
        
    # TODO: fix behaviour if "day-<date>_1" exists, but "day-<date>" was deleted
    local inc=1
    while [ -e "$DEST/$BACKUP_DIR" ]; do
        echo $COLOR_INFO"Destination folder $DEST/$BACKUP_DIR exists already."$COLOR_RESET
        BACKUP_DIR="$base_destdir"_$inc
        inc=$((inc+1))
    done
    
    echo $COLOR_INFO"Using destination folder $DEST/$BACKUP_DIR."$COLOR_RESET
}

# Check if first backup this week and make a 'monthly' hard link copy in this case
copyIfFirstInWeek() {    
    # Try to find weekly backup from current week
    local current_week=`date +"%Y-%W"`
    for f in "$DEST/$WEEKPREFIX"*; do
        local f_date=`echo $f | grep -Eo '[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}'`
        local f_week=`date +"%Y-%W" -d $f_date`
        if [ "$current_week" == "$f_week" ]; then
            return
        fi
    done
    
    # if none is found, make a deep hard link copy of our backup
    echo $COLOR_INFO"First backup this week. So we make a 'weekly' deep link copy."$COLOR_RESET
    cp -al "$DEST/$BACKUP_DIR" "$DEST/$WEEKPREFIX"`date +%Y-%m-%d`
}

# Check if first backup this month and make a 'monthly' hard link copy in this case
copyIfFirstInMonth() {    
    # Try to find monthly backup from current month
    local current_month=`date +"%Y-%m"`
    for f in "$DEST/$MONTHPREFIX"*; do
        local f_date=`echo $f | grep -Eo '[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}'`
        local f_month=`date +"%Y-%m" -d $f_date`
        if [ "$current_month" == "$f_month" ]; then
            return
        fi
    done
    
    # if none is found, make a deep hard link copy of our backup
    echo $COLOR_INFO"First backup this month. So we make a 'monthly' deep link copy."$COLOR_RESET
    cp -al "$DEST/$BACKUP_DIR" "$DEST/$MONTHPREFIX"`date +%Y-%m-%d`
}

# Delete daily backups in $DEST, that are older than $KEEP_DAILY days
deleteOldDaily() {
    # current unix timestamp
    local current_timestamp=`date +%s`    
    # For all daily backups ...
    for f in "$DEST/$DAYPREFIX"*; do
        local f_date=`echo $f | grep -Eo '[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}'`
        local f_timestamp=`date +%s -d $f_date`
        local f_age_days=$(( ($current_timestamp - $f_timestamp) / (24*3600) ))
        if [ "$f_age_days" -ge "$KEEP_DAILY" ]; then
            echo $COLOR_INFO"Deleting $f. It is $f_age_days days old."$COLOR_RESET
            rm -r "$f"
        fi
    done
}

# Delete weekly backups in $DEST, that are older than $KEEP_WEEKLY days
deleteOldWeekly() {
    # current unix timestamp
    local current_timestamp=`date +%s`    
    # For all daily backups ...
    for f in "$DEST/$WEEKPREFIX"*; do
        local f_date=`echo $f | grep -Eo '[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}'`
        local f_timestamp=`date +%s -d $f_date`
        local f_age_days=$(( ($current_timestamp - $f_timestamp) / (24*3600) ))
        if [ "$f_age_days" -ge "$KEEP_WEEKLY" ]; then
            echo $COLOR_INFO"Deleting $f. It is $f_age_days days old."$COLOR_RESET
            rm -r "$f"
        fi
    done
}

# Run script
main "$@"
