#!/bin/bash

# slapd_backup.sh
# This script is provided as an example on how to backup OpenLDAP (slapd)
# version 2.4 running on Ubuntu Server 12 LTS. While it should work on other
# distributions, you may need to adjust the location of some files.

# Error codes:
#   0) Backup successful.
#   1) Fatal errors occurred during the process. Backup not generated.
#   2) One or more non-fatal errors occurred during the process. Backup may be
#      corrupted or incomplete.
#   3) Backup aborted or interrupted.

# To do (known limitations):
#   * A restore script that receives the backup archive file as an input and
#     does the right job would be handy. Coming soon...

################################################################################
# Licensing information
################################################################################
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


################################################################################
# Configuration
################################################################################

# Name of the service being backed up
SERVICE="OpenLDAP"
# Prefix used to name the backup file
BACKUP_PREFIX="slapd" 
# Directory where backups will be stored
BACKUP_DIR="/var/backups/slapd"

# Files and directories to include in the backup archive (compressed tarball)
# You may want to backup specific ssl certificates, instead of /etc/ssl/*
# The backup logical dumps will be appended to this list automatically
BACKUP_FILES="/etc/default/slapd /etc/ldap/ldap.conf /etc/ssl"

# Backup rotation schedule in days (0 = disabled)
DAILY_REMOVE_OLDER_THAN=6
WEEKLY_REMOVE_OLDER_THAN=31
MONTHLY_REMOVE_OLDER_THAN=62

################################################################################
# Functions
################################################################################

on_abort() {
  post_backup_rountine
  logger -t "$0" -s "${SERVICE} backup aborted!" 
  exit 3
}

printl() {
  echo "$*" | tee -a ${LOG_FILE}
}

pre_backup_routine() {
  RESTART_SLAPD="false"
  if service slapd status | grep "is running" 1>>/dev/null 2>&1; then
    if service slapd stop 1>>${LOG_FILE} 2>&1; then
      printl "Successfully stopped slapd to perform the backup."
      RESTART_SLAPD="true"
    else
      printl "Could not stop slapd in preparation for the backup. Backup will be performed, but may be inconsistent."
      let ERROR_COUNT++
    fi
  else
    printl "Slapd is not running. Backup will be executed and slapd is not going to be started afterwards."
  fi
}

generate_backup_dump() {
  # Dump slapd configuration database
  # From OpenLDAP 2.3 onwards, slapd configuration is stored in OpenLDAP and
  # not in a plain text file any more.
  CONFIG_DUMP_FILE="${BACKUP_DIR}/${BACKUP_PREFIX}_config.ldif"
  if slapcat -b "cn=config" -l ${CONFIG_DUMP_FILE} 2>>${LOG_FILE}; then
    printl "LDAP configuration database successfully dumped to ${CONFIG_DUMP_FILE}."
    BACKUP_FILES="${BACKUP_FILES} ${CONFIG_DUMP_FILE}"
  else
    printl "Could not dump ldap configuration database to ldif file using slapcat."
    let ERROR_COUNT++
  fi

  # Dump each one of the databases identified
  NUM_DBS=$(grep "dn: olcDatabase=" ${CONFIG_DUMP_FILE} | wc -l)
  let NUM_DBS-=2
  DB=1
  while [[ ${DB} -le ${NUM_DBS} ]]; do
    # Dump the user DIT
    DB_DUMP_FILE="${BACKUP_DIR}/${BACKUP_PREFIX}_dit${DB}.ldif"
    if slapcat -n ${DB} -l ${DB_DUMP_FILE} 2>>${LOG_FILE}; then
      printl "LDAP database ${DB} successfully dumped to ${DB_DUMP_FILE}."
      BACKUP_FILES="${BACKUP_FILES} ${DB_DUMP_FILE}"
    else
      printl "Could not dump ldap directory to ldif file using slapcat."
      let ERROR_COUNT++
    fi
    let DB++
  done
}

post_backup_routine() {
  if [[ "${RESTART_SLAPD}" == "true" ]]; then
    if service slapd start 1>>${LOG_FILE} 2>&1; then
      printl "Successfully restarted slapd after the backup."
    else
      printl "Could not restart slapd."
      let ERROR_COUNT++
    fi
  fi
}

################################################################################
# Main()
################################################################################

# Reset the error count
ERROR_COUNT=0

# Handle signals gracefully using the on_abort() function
trap on_abort SIGHUP SIGINT SIGQUIT SIGTERM

# Setup date variables used by the script to name files and decide the backup
# schedule
DATE_STAMP=$(date +%Y-%m-%d)                    # Date e.g 2011-12-31
DATE_DAY_OF_WEEK=$(date +%A)                    # Day of the week e.g. Monday
DATE_DAY_OF_MONTH=$(date +%d)                   # Date of the Month e.g. 27

# Log file to store the output of the backup proces
LOG_FILE="${BACKUP_DIR}/${BACKUP_PREFIX}_backup.log"
if [ -f "${LOG_FILE}" ]; then
  rm -rf "${LOG_FILE}"
fi
BACKUP_FILES="${BACKUP_FILES} ${LOG_FILE}"

printl "${SERVICE} backup started at `date +"%m/%d/%Y - %H:%M:%S"`"

# Make sure $BACKUP_DIR exists
if ! [ -d "${BACKUP_DIR}" ]; then
  mkdir -m 0700 -p "${BACKUP_DIR}" 
  if  [ $? != 0 ]; then
    printl "Backup destination ${BACKUP_DIR} does not exists and could not be created" 
    exit 1
  fi
fi 

# Make sure the backups files are secured
umask 077

# Determine the backup schedule
if [[ $MONTHLY_REMOVE_OLDER_THAN -gt "0" && $DATE_DAY_OF_MONTH == "01" ]]; then
  SCHEDULE="monthly" 
elif [[ $WEEKLY_REMOVE_OLDER_THAN -gt "0" && $DATE_DAY_OF_WEEK == "Saturday" ]]; then
  SCHEDULE="weekly" 
elif [[ $DAILY_REMOVE_OLDER_THAN -gt "0" ]]; then
  SCHEDULE="daily" 
else
  printl "Invalid backup rotation schedule. Using daily as a fallback." 
  SCHEDULE="daily"
  let ERROR_COUNT++
fi
printl "${SERVICE} backup running under the ${SCHEDULE} schedule."

# Delete old backup archives
find "${BACKUP_DIR}" -mtime +"$MONTHLY_REMOVE_OLDER_THAN" -type f -name "${BACKUP_PREFIX}_monthly*" -exec rm {} \;
find "${BACKUP_DIR}" -mtime +"$WEEKLY_REMOVE_OLDER_THAN" -type f -name "${BACKUP_PREFIX}_weekly*" -exec rm {} \;
find "${BACKUP_DIR}" -mtime +"$DAILY_REMOVE_OLDER_THAN" -type f -name "${BACKUP_PREFIX}_daily*" -exec rm {} \;

pre_backup_routine

generate_backup_dump

# Create a compressed tarball with all the files of our backup
ARCHIVE_FILE="${BACKUP_DIR}/${BACKUP_PREFIX}_${SCHEDULE}_${DATE_STAMP}.tar"
if tar chfP "${ARCHIVE_FILE}" ${BACKUP_FILES}; then
  printl "Backup tarball successfully written to ${ARCHIVE_FILE}. Contents include: ${BACKUP_FILES}." 
else
  printl "Error while creating the compressed tarball ${ARCHIVE_FILE} with: ${BACKUP_FILES}." 
  let ERROR_COUNT++
fi

post_backup_routine

# Verify if errors ocurred during backup and exit with appropriate return code
if [ ${ERROR_COUNT} -gt 1 ]; then
  printl "${SERVICE} backup FAILED! More information on ${LOG_FILE}" 
  logger -t "$0" -s "${SERVICE} backup FAILED! More information on ${LOG_FILE}" 
  RETURN_CODE=2
else
  printl "${SERVICE} backup completed successfully" 
  logger -t "$0" -s "${SERVICE} backup completed successfully" 
  RETURN_CODE=0
fi

printl "${SERVICE} backup completed at `date +"%m/%d/%Y - %H:%M:%S"`"

# Append the log file to the archive and compress the tarball
tar --append --file=${ARCHIVE_FILE} ${LOG_FILE} 
gzip -f ${ARCHIVE_FILE}

exit ${RETURN_CODE}

