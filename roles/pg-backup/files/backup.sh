#!/bin/bash

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:?BACKUP_DIR is not set}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

FILE="${BACKUP_DIR}/${PGDATABASE}_$(date +%Y%m%d_%H%M%S).dump"
TMP="${FILE}.tmp"

echo "$(date '+%F %T') start: ${PGDATABASE} @ ${PGHOST}"

rm -f "${BACKUP_DIR}"/*.dump.tmp

if ! pg_dump -Fc -f "${TMP}" || ! pg_restore --list "${TMP}" > /dev/null; then
    rm -f "${TMP}"
    echo "$(date '+%F %T') ERROR: backup failed" >&2
    exit 1
fi
mv "${TMP}" "${FILE}"

echo "$(date '+%F %T') saved: ${FILE} ($(du -h "${FILE}" | cut -f1))"

find "${BACKUP_DIR}" -maxdepth 1 -name '*.dump' -mmin +$(( RETENTION_DAYS * 24 * 60 )) -print -delete

echo "$(date '+%F %T') done: $(find "${BACKUP_DIR}" -maxdepth 1 -name '*.dump' | wc -l) backup file(s) kept"
