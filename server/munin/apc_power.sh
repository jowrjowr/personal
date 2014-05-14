 #!/bin/sh
 #
 # Plugin to report APC UPS power and monthly running cost.
 #
 # Contributed by Tim Chappell
 #
 # Magic markers - optional - used by installation scripts and
 # munin-config:
 #
 #%# family=manual
 #%# capabilities=autoconf
 # Cost (pence) per kWh
 COST=11
 SRCFILE=/var/log/apcupsd.status
 if [ "$1" = "config" ]; then
       echo 'graph_category power'
       echo 'graph_title UPS Power Consumption'
       echo 'graph_vlabel Watts'
       echo 'apc_ups_power.label Consumed Power'
       echo 'apc_ups_power.draw LINE1'
       echo 'running_cost.label Monthly running cost'
       echo 'running_cost.draw LINE1'
       exit 0
 fi
 NOMPOWER=`awk '{if($1=="NOMPOWER"){print $3}}' $SRCFILE`
 awk -vc=$COST -vp=$NOMPOWER '{if($1=="LOADPCT"){printf"apc_ups_power.value %d\n",($3/100*p)}}' $SRCFILE
 awk -vc=$COST -vp=$NOMPOWER '{if($1=="LOADPCT"){printf"running_cost.value %.2f\n",((($3/100*p)/1000)*24*30*c/100)}}' $SRCFILE
