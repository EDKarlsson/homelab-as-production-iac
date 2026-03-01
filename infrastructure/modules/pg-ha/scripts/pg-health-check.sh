#!/bin/bash
# PostgreSQL health check for keepalived VRRP
# Returns 0 if PG is accepting connections (running), 1 otherwise.
# Role detection (primary vs standby) is NOT checked here —
# keepalived priorities handle VIP placement, notify script handles promotion.

pg_isready -q || exit 1
exit 0
