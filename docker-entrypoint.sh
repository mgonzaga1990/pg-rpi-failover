#!/bin/bash

# Based on official postgres package's entrypoint script (https://hub.docker.com/_/postgres/)
# Modified to be able to set up a slave. The docker-entrypoint-initdb.d hook provided is inadequate.
set -e

_log(){
    echo "[INFO] " $1
}

_set_up_dir(){
  mkdir -p $PGDATA
  chmod 0700 $PGDATA
  chown -R postgres $PGDATA

  mkdir -p /run/postgresql
	chmod g+s /run/postgresql
	chown -R postgres /run/postgresql

  mkdir -p /var/lib/pg/
  touch /var/lib/pg/log.txt
  chmod 777 /var/lib/pg/log.txt

  export repmgr_path='/etc'

  touch $repmgr_path/repmgr.conf
  chmod 777 $repmgr_path/repmgr.conf 

  _log "Directory created [$PGDATA]"
}

_pg_conf(){
    sed -i "s/#max_wal_senders = 0/max_wal_senders = ${PG_MAX_WAL_SENDERS}/g"  ${PGDATA}/postgresql.conf
    sed -i "s/#wal_level = minimal/wal_level = hot_standby/g"  ${PGDATA}/postgresql.conf
    sed -i "s/#max_replication_slots = 0/max_replication_slots = 10/g"  ${PGDATA}/postgresql.conf
    sed -i "s/#hot_standby = off/hot_standby = on/g"  ${PGDATA}/postgresql.conf

    sed -i "s/#archive_mode = off/archive_mode = on/g"  ${PGDATA}/postgresql.conf
    
    echo "archive_command = '/bin/true'" >>  ${PGDATA}/postgresql.conf

    sed -i "s/#shared_preload_libraries = ''/shared_preload_libraries = 'repmgr'/g"  ${PGDATA}/postgresql.conf
}

_hba_conf(){
  { echo; echo "local    replication     repmgr                        trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
  { echo; echo "host     replication     repmgr       127.0.0.1/32     trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
  { echo; echo "host     replication     repmgr       192.168.1.0/24   trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null

  { echo; echo "host     replication     repmgr       0.0.0.0/0        trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
  { echo; echo "host     replication     repmgr       ::/0             trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
  
  { echo; echo "local    repmgr          repmgr                        trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
  { echo; echo "host     repmgr          repmgr       127.0.0.1/32     trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
  { echo; echo "host     repmgr          repmgr       192.168.1.0/24   trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null  

  { echo; echo "host     repmgr          repmgr       0.0.0.0/0        trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
  { echo; echo "host     repmgr          repmgr       ::/0             trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null

  { echo; echo "host     all             all          0.0.0.0/0        trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
  { echo; echo "host     all             all          ::/0             trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
}

_setup_repmgrd(){
  local repmgrd_file='/etc/default'
  
  sed -i "s/REPMGRD_ENABLED=no/REPMGRD_ENABLED=yes/g"  ${repmgrd_file}/repmgrd
  sed -i "s/#REPMGRD_OPTS=""/REPMGRD_OPTS='--daemonize=false'/g"  ${repmgrd_file}/repmgrd
  sed -i "s/#REPMGRD_USER/REPMGRD_USER/g"  ${repmgrd_file}/repmgrd
  sed -i "s/#REPMGRD_BIN/REPMGRD_BIN/g"  ${repmgrd_file}/repmgrd
  sed -i "s/#REPMGRD_PIDFILE/REPMGRD_PIDFILE/g"  ${repmgrd_file}/repmgrd

  echo REPMGRD_CONF="${repmgr_path}/repmgr.conf" > ${repmgrd_file}/repmgrd

}

_set_slave(){
  echo "==========================================================================================="
  echo "            SETTING UP AS STANDBY SERVER ( pinging MASTER [${1}]. . . )    "
  echo "==========================================================================================="
  until ping -c 1 -W 1 ${1}
    do
       _log "Waiting for master to ping..."
          sleep 1s
    done
  
  _hba_conf
  
  #cat $PGDATA/pg_hba.conf
  #gosu postgres pg_ctl -D $PGDATA -w stop

  _configure_repmgr
  
  echo "==========================================================================================="
  echo "                           DRY-RUN CLONING    "
  echo "==========================================================================================="
  #perform the dry run and test if our configuration is correct:
  gosu postgres repmgr -h ${1} -U repmgr -d repmgr -f ${repmgr_path}/repmgr.conf standby clone --dry-run

  ls -l $PGDATA

  echo "==========================================================================================="
  echo "                           ACTUAL CLONING"
  echo "==========================================================================================="
  #start cloning:
  gosu postgres repmgr -h ${1} -U repmgr -d repmgr -f ${repmgr_path}/repmgr.conf standby clone --force

  echo "==========================================================================================="
  echo "                           REPLICA SERVER STARTING"
  echo "===========================================================================================" 
  #_log "Temporary Server start"
  #gosu postgres pg_ctl -D "$PGDATA" -m fast -w stop
  gosu postgres pg_ctl -D $PGDATA start;

  
  #Register the standby server with repmgr:
  gosu postgres repmgr -f ${repmgr_path}/repmgr.conf standby register

  gosu postgres repmgr -f ${repmgr_path}/repmgr.conf cluster show

  gosu postgres repmgrd restart

  #tail /var/log/postgresql/repmgrd.log
}

_set_master(){
  _log "Setting up as MASTER."
  
  eval "gosu postgres initdb $POSTGRES_INITDB_ARGS"
    
  _pg_conf
  _hba_conf

  _execute_script $1 $2 

  _configure_repmgr

  _log "Register the MASTER SERVER with repmgr."
  gosu postgres repmgr -f ${repmgr_path}/repmgr.conf primary register

  _log "Checking the status of the cluster."
  gosu postgres repmgr -f ${repmgr_path}/repmgr.conf cluster show

  gosu postgres repmgrd restart
  # tail /var/log/postgresql/repmgrd.log
}

_configure_repmgr(){
    _log "Setting up repmgr.conf"

    local NET_IF=`netstat -rn | awk '/^0.0.0.0/ {thif=substr($0,74,10); print thif;} /^default.*UG/ {thif=substr($0,65,10); print thif;}'`
    local NET_IP=`ifconfig ${NET_IF} | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'` 

    echo "node_id=$PGID" >> $repmgr_path/repmgr.conf
    echo "node_name=$PGNODE" >> $repmgr_path/repmgr.conf
    echo "conninfo='host=$NET_IP user=repmgr dbname=repmgr connect_timeout=2'" >> $repmgr_path/repmgr.conf
    echo "data_directory='$PGDATA'" >> $repmgr_path/repmgr.conf
    
    echo "failover=automatic" >> $repmgr_path/repmgr.conf
    echo "promote_command='/usr/bin/repmgr standby promote -f ${repmgr_path}/repmgr.conf --log-to-file'" >> $repmgr_path/repmgr.conf
    echo "follow_command='/usr/bin/repmgr standby follow -f ${repmgr_path}/repmgr.conf --log-to-file --upstream-node-id=%n'" >> $repmgr_path/repmgr.conf
    
    echo "monitoring_history=yes" >> $repmgr_path/repmgr.conf
    echo "monitor_interval_secs=10" >> $repmgr_path/repmgr.conf
}

_execute_script(){
    _log "Executing script in DIR docker-entrypoint-initdb.d/"

    gosu postgres pg_ctl -D $PGDATA -o "-c listen_addresses='*'" -w start

	for f in /docker-entrypoint-initdb.d/*; do
        bash "$f" $1 $2
	done   
}

_main(){
   if [ -s "$PGDATA/PG_VERSION" ]; then
     echo '======================================================================================'
	   echo ' PostgreSQL Database directory appears to contain a database.'
     echo ' Will Rejoin as Slave'
	   echo '======================================================================================'
     #gosu postgres pg_ctl -D $PGDATA -w stop
     gosu postgres repmgrd stop
     
     local node_primary=$(repmgr -f /etc/repmgr.conf cluster show)  
     local node_spot=$(echo "$node_primary" | grep -w '* running')
     local node_host=$(echo $"node_spt" | grep -o node[^,])

     _log "Rejoining ...." 
     _log "Node Found : " $node_host
     gosu postgres repmgr  -f ${repmgr_path}/repmgr.conf node service --action=stop --checkpoint
     gosu postgres repmgr  -f ${repmgr_path}/repmgr.conf -d 'host=$node_host user=repmgr dbname=repmgr' node rejoin

     gosu postgres repmgrd start
   else
     _log "No Existing set-up found."
     
     _set_up_dir #set up directory

     _setup_repmgrd

     if [ -z $4 ]; then
        _log "Searching Active Master Server (if any)"
        local MASTER_HOST=$(nslookup pg-master-0.pg-master-headless | awk 'FNR == 5 {print $2}')
        if [ -z $MASTER_HOST ]; then
            _log "MASTER server NOT FOUND."
            _set_master $1 $3
        else
          _log "MASTER SERVER found [$MASTER_HOST]."
          _set_slave $4
        fi
     else
        _log "MASTER SERVER found [$4]."
        _set_slave $4 
     fi

	echo '=========================================================================================='
	echo '                PostgreSQL init process complete; ready for start up.'
	echo '=========================================================================================='

  fi

  #check the events for the cluster:
  gosu postgres repmgr   -f ${repmgr_path}/repmgr.conf cluster event

  gosu postgres pg_ctl -D $PGDATA -l /var/lib/pg/log.txt restart
  tail -f /var/lib/pg/log.txt > /dev/null
}

_main "$@"