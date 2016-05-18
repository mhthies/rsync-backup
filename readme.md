# rsync-backup

A simple but not too simple backup script based on rsync.

Including incremental snapshot backups using hardlinks, weekly and monthly snapshots, automatic backup rotation
(deletion of old backups, while preserving monthly snapshots), interactive dryrun storing transaction list, interactive
option to continue unfinished backups and passing of custom filter (exclude) file.

## Usage

From the commandline help (`rsync-backup.sh -h`):

```
Usage:
  rsync-backup.sh -s <SOURCE> -d <DEST> [-i] [-f <FILTER>]

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
```
