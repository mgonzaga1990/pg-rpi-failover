#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$1" --dbname "$2" <<-EOSQL
    CREATE USER repmgr WITH SUPERUSER;
    CREATE DATABASE repmgr with owner repmgr;
EOSQL