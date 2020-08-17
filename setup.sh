#!/bin/bash

set -e

_log(){
    echo "[INFO] " $1
}
_log_err(){
    echo "[ERROR] " $1
}

_log "================================================================================="
_log "         STARTING UP POSTGRES REPLICATION AND FAILOVER SETUP"
_log "================================================================================="


#validate required input
if [[ -z "$PGUSER" || -z "$PGPASS" || -z "$PGDB" ]]; then
    _log_err 'Please enter username/password and database!'
    exit 1
else
    if [[  -z "$PGID" || -z "$PGNODE" ]]; then
        _log_err 'Node id and Node name are required!'
        exit 1
    else
        # Forwards-compatibility for old variable names (pg_basebackup uses them)
        export PGPASSWORD=$POSTGRES_PASSWORD
        ./docker-entrypoint.sh $PGUSER $PGPASS $PGDB $MASTER_HOST
    fi
fi