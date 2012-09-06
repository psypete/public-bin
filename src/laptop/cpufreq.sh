#!/bin/sh
cpufd="/sys/devices/system/cpu/cpu0/cpufreq"
[ $# -lt 1 ] && echo -en "Usage: $0 fast|slow\nSets cpu frequency scaling to fastest or slowest setting\nCurrent speed:\t\t`cat $cpufd/scaling_cur_freq`\n" && exit 1
/sbin/modprobe acpi-cpufreq || exit 1
if [ "$1" = "fast" ] ; then
	SPEED=`cat $cpufd/scaling_max_freq`
elif [ "$1" = "slow" ] ; then
	SPEED=`cat $cpufd/scaling_min_freq`
fi
echo "$SPEED" > $cpufd/scaling_setspeed || ( echo "Error: could not set cpufreq scaling to \"$SPEED\"" && exit 1 )
echo "Successfully set cpufreq scaling to \"$SPEED\""
