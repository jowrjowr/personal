 #!/bin/sh
 #
 # Plugin to report APC Battery statistics. Relies on apcupsd package being installed.
 #
 # Contributed by Tim Chappell
 #
 # Magic markers - optional - used by installation scripts and
 # munin-config:
 #
 #%# family=manual
 #%# capabilities=autoconf
 SRCFILE=/var/log/apcupsd.status
 if [ "$1" = "config" ]; then
       echo 'graph_category power'
       echo 'graph_title UPS Battery Stats'
       echo 'graph_vlabel Battery condition'
       echo 'apc_ups_battery_volts.label Battery (V)'
       echo 'apc_ups_battery_volts.draw LINE1'
       echo 'apc_ups_battery_charge.label Battery Charge (%)'
       echo 'apc_ups_battery_charge.draw LINE1'
       echo 'apc_ups_battery_temp.label Battery Temp (degC)'
       echo 'apc_ups_battery_temp.draw LINE1'
       echo 'apc_ups_battery_rtr.label Battery Runtime (mins)'
       echo 'apc_ups_battery_rtr.draw LINE1'
       exit 0
 fi
 /bin/cat $SRCFILE | /usr/bin/awk '{if ($1=="BATTV") {printf "apc_ups_battery_volts.value %s\n",$3}}'
 /bin/cat $SRCFILE | /usr/bin/awk '{if ($1=="BCHARGE") {printf "apc_ups_battery_charge.value %s\n",$3}}'
 /bin/cat $SRCFILE | /usr/bin/awk '{if ($1=="ITEMP") {printf "apc_ups_battery_temp.value %s\n",$3}}'
 /bin/cat $SRCFILE | /usr/bin/awk '{if ($1=="TIMELEFT") {printf "apc_ups_battery_rtr.value %s\n",$3}}'
