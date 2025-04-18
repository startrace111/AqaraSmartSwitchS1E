#!/bin/sh

DEBUG=0
VERSION="1.0.8"

# digital photo frame
DPF_CONFIG="/data/etc/dpf.conf"
DPF_DEFAULT_INTERVAL=60
DPF_ENABLE=
DPF_PHOTOS_URL=
DPF_PHOTOS=
DPF_INTERVAL=
CURRENT_THEME=
CURRENT_BG_PNG="time_6_6_digitalbackground_1.png"
CURRENT_PICTURE_INDEX=1
CURRENT_PICTURE=
CURL=
PICTURE_LIST=()
SHUFFLE=0
REFRESH=0

info() {
    echo "INFO: $@"
}

debug() {
    if [ "x$DEBUG" == "x1" ]; then
        echo "DEBUG: $@"
    fi
}

#read_config() {
#    local config=
#    if [ -f $DPF_CONFIG ]; then
#        config=$(cat $DPF_CONFIG)
#        DPF_ENABLE=$(echo $config | jshon -Q -e digital_frame -e enable)
#        DPF_PHOTOS_URL=$(echo $config | jshon -Q -e digital_frame -e url | tr -d '"')
#        DPF_PHOTOS=$(echo $config | jshon -Q -e digital_frame -e photos | tr -d '"')
#        DPF_INTERVAL=$(echo $config | jshon -Q -e digital_frame -e interval)
#        [ -z $DPF_INTERVAL ] && DPF_INTERVAL=$DPF_DEFAULT_INTERVAL
#        if [ "x$DPF_ENABLE" == "x1" ]; then
#            [ -z "$DPF_PHOTOS_URL" -o -z "$DPF_PHOTOS_URL" -o -z "$DPF_PHOTOS" ] && exit 1
#        fi
#        if [ "x$DPF_ENABLE" == "x0" ]; then
#            exit 0
#        fi
#    else
#        exit 1
#    fi
#    if [ -x "/bin/curl" ]; then
#        CURL="/bin/curl"
#    elif [ -x "/data/bin/curl" ]; then
#        CURL="/data/bin/curl"
#    fi
#}
read_config() {
    local config=
    if [ -f $DPF_CONFIG ]; then
        config=$(cat $DPF_CONFIG)
        DPF_ENABLE=$(echo $config | jshon -Q -e digital_frame -e enable)
        DPF_PHOTOS_URL=$(echo $config | jshon -Q -e digital_frame -e url | tr -d '"')
        DPF_INTERVAL=$(echo $config | jshon -Q -e digital_frame -e interval)
        SHUFFLE=$(echo $config | jshon -Q -e digital_frame -e shuffle)
        REFRESH=$(echo "$config" | jshon -Q -e digital_frame -e refresh)
        [ -z $DPF_INTERVAL ] && DPF_INTERVAL=$DPF_DEFAULT_INTERVAL
        [ -z $SHUFFLE ] && SHUFFLE=0
        [ -z "$REFRESH" ] && REFRESH=0


        if [ "x$DPF_ENABLE" == "x1" ]; then
            [ -z "$DPF_PHOTOS_URL" ] && exit 1
        fi
        if [ "x$DPF_ENABLE" == "x0" ]; then
            exit 0
        fi
    else
        exit 1
    fi
    if [ -x "/bin/curl" ]; then
        CURL="/bin/curl"
    elif [ -x "/data/bin/curl" ]; then
        CURL="/data/bin/curl"
    fi
}

load_picture_list() {
    local list_url="$DPF_PHOTOS_URL/img.txt"
    PICTURE_LIST=$($CURL -s "$list_url")

    if [ -z "$PICTURE_LIST" ]; then
        echo "[frame] empty picture list"
        exit 1
    fi

    if [ "x$SHUFFLE" = "x1" ]; then
        PICTURE_LIST=$(echo "$PICTURE_LIST" | awk 'BEGIN{srand()} {print rand() "\t" $0}' | sort -k1,1n | cut -f2-)
    fi

    PICTURE_LIST=$(echo "$PICTURE_LIST" | tr '\n' ' ')
    CURRENT_PICTURE_INDEX=1
}

read_current_theme() {
    local display=; local screenstyle=

    CURRENT_THEME=$(ubus -S call page get.theme | jshon -Q -e themeName | tr -d '"')
    [ -z $CURRENT_THEME ] && exit 1
    display=$(ubus call setting get.display)
    screenstyle=$(echo $display | jshon -Q -e standby -e screenStyle)

    case $screenstyle in
        "clock")
            CURRENT_BG_PNG="time_6_6_digitalbackground_1.png"
        ;;
        "clock2")
            CURRENT_BG_PNG="time_6_6_digitalbackground_2.png"
        ;;
        "weather")
            CURRENT_BG_PNG="weather_unknown.png"
        ;;
        "anaclock")
            CURRENT_BG_PNG="time_6_6_analogbackground_1.png"
        ;;
        "anaclock2")
            CURRENT_BG_PNG="time_6_6_analogbackground_2.png"
        ;;
        "anaclock3")
            CURRENT_BG_PNG="time_6_6_analogbackground_3.png"
        ;;
        *)
            CURRENT_BG_PNG="time_6_6_digitalbackground_1.png"
        ;;
    esac
}

backup_png() {
    cp -f /data/theme/$CURRENT_THEME/homepage/screen/$CURRENT_BG_PNG /data/theme/$CURRENT_THEME/homepage/screen/${CURRENT_BG_PNG}_bak
}

#get_picture() {
#    CURRENT_PICTURE=$(echo $DPF_PHOTOS | tr -d "[" | tr -d "]" | cut -d "," -f $CURRENT_PICTURE_INDEX | awk '{$1=$1};1' | tr -d '"')
#    if [ -z "$CURRENT_PICTURE" ]; then
#        CURRENT_PICTURE_INDEX=1
#        CURRENT_PICTURE=$(echo $DPF_PHOTOS | tr -d "[" | tr -d "]" | cut -d "," -f $CURRENT_PICTURE_INDEX | awk '{$1=$1};1' | tr -d '"')
#    else
#        CURRENT_PICTURE_INDEX=$((CURRENT_PICTURE_INDEX + 1))
#    fi
#
#    $CURL -s -k -L -o "/tmp/$CURRENT_PICTURE" "$DPF_PHOTOS_URL/$CURRENT_PICTURE"
#}
get_picture() {
    set -- $PICTURE_LIST
    local arr=("$@")
    local len=${#arr[@]}

    if [ "$CURRENT_PICTURE_INDEX" -gt "$len" ]; then
        load_picture_list  # 每轮播放完重新加载
    fi

    CURRENT_PICTURE=$(echo $PICTURE_LIST | cut -d ' ' -f $CURRENT_PICTURE_INDEX)
    CURRENT_PICTURE_INDEX=$((CURRENT_PICTURE_INDEX + 1))

    $CURL -s -k -L -o "/tmp/$CURRENT_PICTURE" "$DPF_PHOTOS_URL/$CURRENT_PICTURE"
}

show_picture() {
    [ -f "/tmp/$CURRENT_PICTURE" ] && cp -f /tmp/$CURRENT_PICTURE /data/theme/$CURRENT_THEME/homepage/screen/$CURRENT_BG_PNG
    if [ "$REFRESH" -eq 1 ]; then
        current=$(ubus -S call setting get.display)
        cmd="ubus -S call setting set.display '$current'"
        eval "$cmd"
    fi
}

read_config
sleep 3 # sleep 3s to allow ubus working when booting up
read_current_theme
backup_png
load_picture_list

while true  # Keep an infinite loop to reconnect when connection lost/broker unavailable
do
    get_picture
    show_picture
    sleep $DPF_INTERVAL
done
