#!/bin/bash
# Keepalived notify script for PostgreSQL HA
# Called on VRRP state transitions: MASTER, BACKUP, FAULT
#
# On MASTER transition: promotes standby to primary if still in recovery
# On BACKUP/FAULT: logs state change (manual intervention needed to rejoin as standby)

TYPE=$1   # INSTANCE
NAME=$2   # VI_POSTGRES
STATE=$3  # MASTER|BACKUP|FAULT

case $STATE in
  MASTER)
    if sudo -u postgres psql -tAc "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q "t"; then
      PG_VERSION=$(pg_lsclusters -h | awk '{print $1}')
      sudo -u postgres pg_ctlcluster "$PG_VERSION" main promote
      logger "keepalived: PostgreSQL PROMOTED to primary"
    else
      logger "keepalived: PostgreSQL already primary, VIP acquired"
    fi
    ;;
  BACKUP|FAULT)
    logger "keepalived: PostgreSQL entering $STATE state"
    ;;
esac
