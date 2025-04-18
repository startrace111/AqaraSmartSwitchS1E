#!/bin/sh

DEBUG=0
VERSION="1.0.8"

# digital photo frame
DPF_CONFIG="/data/etc/dpf.conf"


/data/bin/mqtt_sub.sh &
/data/bin/ubus_monitor.sh &
/data/bin/res_monitor.sh &

if [ -f "$DPF_CONFIG" ]; then
    enable=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e enable)
    [ -z "$enable" ] && enable=0
    if [ "x$enable" == "x1" ]; then
        # call frame.sh
        /data/bin/frame.sh &
    fi
fi
