#!/bin/bash

MYSQL_USER="emdr_user"
MYSQL_PASS="oMTNziop0EAOs"
CUR_DATE=`date +%s`

for table in `mysql -BN emdr -e "show tables"`; do 
	if echo "$table" | grep -q "history"; then
		# nothing older than a year
		mysql emdr -u $MYSQL_USER -p$MYSQL_PASS -e "delete from $table where date < $CUR_DATE - 86400*180" 2>&1 > /dev/null
	fi
	if echo $table | grep -q "orders"; then
		# nothing older than a day
		mysql emdr -u $MYSQL_USER -p$MYSQL_PASS -e "delete from $table where gendate < $CUR_DATE - 86400*7" 2>&1 > /dev/null
	fi
done
