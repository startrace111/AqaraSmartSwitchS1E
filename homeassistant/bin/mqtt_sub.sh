#!/bin/sh

DEBUG=0
VERSION="1.0.8"
LATEST_VERSION_URL="https://gh-proxy.com/raw.githubusercontent.com/startrace111/AqaraSmartSwitchS1E/master/homeassistant/release.json"

# homeassistant discovery prefix
HASS_PREFIX="homeassistant"

# S1E info
PRODUCT_INFO=""
DEVICE_NAME=""
DID=""
MODEL=""
SW_VERSION=""
IDENTIFIERS=""
CONFIG=""
WCONFIG=""

# mqtt configuration
PUB=""
SUB=""
MQTT_CONF="/data/etc/mqtt.conf"
MQTT_IP=127.0.0.1
MQTT_USER=""
MQTT_PASSWORD=""
MQTT_PORT=1883
MQTT_ARGS=""
MQTT_SLEEP=10

# digital photo frame
DPF_CONFIG="/data/etc/dpf.conf"
DPF_DEFAULT_INTERVAL=60

# firmware lock
FW_LOCK_FILE="/data/ota_dir/lumi_fw.tar"

info() {
    echo "INFO: $@"
}

debug() {
    if [ "x$DEBUG" == "x1" ]; then
        echo "DEBUG: $@"
    fi
}

check_mqtt() {
    if [ -x "/bin/mosquitto_sub" ]; then
        SUB="/bin/mosquitto_sub"
    elif [ -x "/data/bin/mosquitto_sub" ]; then
        SUB="/data/bin/mosquitto_sub"
    fi
    if [ -x "/bin/mosquitto_pub" ]; then
        PUB="/bin/mosquitto_pub"
    elif [ -x "/data/bin/mosquitto_pub" ]; then
        PUB="/data/bin/mosquitto_pub"
    fi

    if [ -z "$PUB" -o -z "$SUB" ]; then
        error "The mosquitto_sub or mosquitto_pub are not exist!"
    fi

    if [ ! -f "$MQTT_CONF" ]; then
        error "The config of mqtt is not exist!"
    fi
}

read_mqtt_config() {
    local ret=""

    while read conf; do
        if [ "x$conf" != "x" ]; then
            ret=$(echo $conf | grep MQTT_IP | cut -d "=" -f 2 | tr -d '"')
            if [ "x$ret" != "x" ]; then
                MQTT_IP=$ret
            fi
            ret=$(echo $conf | grep MQTT_USER | cut -d "=" -f 2 | tr -d '"')
            if [ "x$ret" != "x" ]; then
                MQTT_USER=$ret
            fi
            ret=$(echo $conf | grep MQTT_PASSWORD | cut -d "=" -f 2 | tr -d '"')
            if [ "x$ret" != "x" ]; then
                MQTT_PASSWORD=$ret
            fi
            ret=$(echo $conf | grep MQTT_PORT | cut -d "=" -f 2 | tr -d '"')
            if [ "x$ret" != "x" ]; then
                MQTT_PORT=$ret
            fi
        fi
    done < $MQTT_CONF

    MQTT_ARGS="`[ ! -z $MQTT_IP ] && echo "-h $MQTT_IP" || echo "-h localhost"` `[ ! -z $MQTT_USER ] && echo "-u $MQTT_USER -P $MQTT_PASSWORD"` `[ ! -z $MQTT_PORT ] && echo "-p $MQTT_PORT" || echo "-p 1883"`"
}

get_product_info() {
    PRODUCT_INFO=$(ubus -S call setting product.info)
    DEVICE_NAME=$(echo $PRODUCT_INFO | jshon -e name | tr -d '"')
    DID=$(echo $PRODUCT_INFO | jshon -e did | tr -d '"')
    MODEL=$(echo $PRODUCT_INFO | jshon -e model | tr -d '"')
    SW_VERSION=$(echo $PRODUCT_INFO | jshon -e version | tr -d '"')
    IDENTIFIERS=$(echo $PRODUCT_INFO | jshon -e sn | tr -d '"')
    debug "{\"name\": \"$DEVICE_NAME\", \"identifiers\": \"$IDENTIFIERS\", \"sw_version\": \"$SW_VERSION\", \"model\": \"$MODEL\", \"manufacturer\": \"Aqara\"}"
}

get_config() {
    CONFIG=$(ubus -S call switch get.config)
    debug $CONFIG
}

get_wconfig() {
    WCONFIG=$(ubus -S call switch get.wconfig)
    debug $WCONFIG
}

mqtt_pub() {
    local topic=$1
    local msg=$2
    local use_device=$3
    local args=$4
    local device="\"dev\":{\"name\":\"$DEVICE_NAME\",\"ids\":\"$IDENTIFIERS\",\"mf\":\"Aqara\",\"sw\":\"$SW_VERSION\",\"model\":\"$MODEL\"}"

    if [ -z $use_device ]; then
        use_device=0
    fi

    msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s#^(.*)[}]#\1,$device}#"`

    debug "Topic: $topic"
    debug "Message: $msg"
    cmd="$PUB $MQTT_ARGS $args -t $topic -m '$msg'"
    eval "$cmd"
}

change_status() {
    local topic=; local msg=

    info Signal caught: set status to "offline" and exit

    prefix_topic="$HASS_PREFIX/binary_sensor/0x00${DID}/connectivity"
    topic="$prefix_topic/state"
    msg="OFF"
    mqtt_pub $topic "$msg"
}

set_ftp() {
    local enable=$1
    local unique_id=

    unique_id="0x00${DID}/ftp"
    if [ "x$msg" == "xON" -o "x$msg" == "x1" ]; then
        ftp_running=$(pgrep tcpsvd)
        if [ "x$ftp_running" != "x" ]; then
            debug "The ftp server is running!"
            return
        else
            info "Run ftp server!"
            cmd="tcpsvd -vE 0.0.0.0 21 ftpd -w /data &"
            eval $cmd
            mqtt_pub "$HASS_PREFIX/switch/$unique_id/state" "ON"
        fi
    else
        ps_id=$(pgrep -o tcpsvd)
        if [ -n "$ps_id" ]; then
            cmd="kill -9 $ps_id"
            eval $cmd
            mqtt_pub "$HASS_PREFIX/switch/$unique_id/state" "OFF"
        fi
    fi
}

set_reboot() {
    local enable=$1

    if [ "x$enable" == "xPRESS" ]; then
        change_status
        sleep 1
        ubus call system reboot
    fi
}

set_display() {
    local type=$1
    local value=$2
    local current=; local new=

    current=$(ubus -S call setting get.display)
    msg=$value
    case $type in
            standby)
                [ "x$value" == "xON" -o "x$value" == "x1" ] && value=1 || value=0
                new=$(echo $current | sed -r "s/\"enable\":[0-1],\"seconds/\"enable\":$value,\"seconds/g")
            ;;
            screen_saver)
                [ "x$value" == "xON" -o "x$value" == "x1" ] && value=1 || value=0
                new=$(echo $current | sed -r "s/\"screen\":[0-1],\"screenStyle/\"screen\":$value,\"screenStyle/g")
            ;;
            brightness)
                new=$(echo $current | sed -r "s/\"autoBrightness\":([0-1]),\"brightness\":(.*),\"homePage\"/\"autoBrightness\":\1,\"brightness\":$value,\"homePage\"/g")
            ;;
            standby_time)
                new=$(echo $current | sed -r "s/\"seconds\":(.*),\"screen\"/\"seconds\":$value,\"screen\"/g")
            ;;
            standby_brightness)
                new=$(echo $current | sed -r "s/\"screenStyle\":(.*),\"brightness\":(.*),/\"screenStyle\":\1,\"brightness\":$value,/g")
            ;;
            font_size)
                new=$(echo $current | sed -r "s/\{\"fontSize\":\"(.*)\",\"language/\{\"fontSize\":\"$value\",\"language/g")
            ;;
            home_page)
                #new=$(echo $current | sed -r "s/\{\"homePage\":\"(.*)\",\"showHomeTitle/\{\"homePage\":\"$value\",\"showHomeTitle/g")
                new=$(echo "$current" | sed -r "s/\"homePage\":\"[^\"]+\",\"showHomeTitle\"/\"homePage\":\"$value\",\"showHomeTitle\"/")

            ;;
            standby_screen)
                #new=$(echo $current | sed -r "s/\{\"screenStyle\":\"(.*)\",\"clock/\{\"screenStyle\":\"$value\",\"clock/g")
                #new=$(echo $current | sed -r "s/\"screenStyle\":\"[^\"]+\"/\"screenStyle\":\"$value\"/g")
                new=$(echo "$current" | sed -r "s/\"screenStyle\":\"[^\"]+\",\"brightness\"/\"screenStyle\":\"$value\",\"brightness\"/")

            ;;
            language)
                case $value in
                    Simplified_Chinese)
                        new_value="zh"
                    ;;
                    English)
                        new_value="en"
                    ;;
                    Traditional_Chinese)
                        new_value="zh-TW"
                    ;;
                esac
                new=$(echo $current | sed -r "s/\"language\":\"(.*)\",\"autoBrightness/\"language\":\"$new_value\",\"autoBrightness/g")
            ;;
    esac

    cmd="ubus -S call setting set.display '$new'"
    [ -n "$new" ] && ret=$(eval $cmd)
    ret=$(echo $ret | jshon -Q -e status)
    if [ "x$ret" == "x0" ]; then
        case $type in
            screen_saver | standby)
                topic="$HASS_PREFIX/switch/0x00${DID}/$type/state"
                mqtt_pub $topic "$msg"
            ;;
            font_size | home_page | standby_screen | language)
                topic="$HASS_PREFIX/select/0x00${DID}/$type/state"
                mqtt_pub $topic "$msg"
            ;;
        esac
    fi
}

set_audio() {
    local type=$1
    local value=$2
    local current=; local new=

    current=$(ubus -S call setting get.audio)
    new=""
    case $type in
            mute)
                [ "x$value" == "xON" -o "x$value" == "x1" ] && value=1 || value=0
                new=$(echo $current | sed -r "s/\"mute\":[0-1],/\"mute\":$value,/g")
            ;;
            touch_sound)
                [ "x$value" == "xON" -o "x$value" == "x1" ] && value=1 || value=0
                new=$(echo $current | sed -r "s/\"touchSound\":[0-1],/\"touchSound\":$value,/g")
            ;;
            slient_mode)
                [ "x$value" == "xON" -o "x$value" == "x1" ] && value=1 || value=0
                new=$(echo $current | sed -r "s/\"silentMode\":[0-1],/\"silentMode\":$value,/g")
            ;;
            volume_level)
                new=$(echo $current | sed -r "s/\"volumeLevel\":\"[a-z]*\",/\"volumeLevel\":\"$value\",/g")
            ;;
    esac
    cmd="ubus -S call setting set.audio '$new'"
    [ "x$new" != "x" ] && ret=$(eval $cmd)
}

set_frame() {
    local topic=$1
    local msg=$2
    local info=; local photos_url=; local photos=; local interval=

    if [ -f "$DPF_CONFIG" ]; then
        [ "x$msg" == "xON" ] && enable=1 || enable=0
        photos_url=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e url | tr -d '"')
        #photos=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e photos)
        interval=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e interval)
        shuffle=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e shuffle | tr -d '"')
        refresh=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e refresh | tr -d '"')


        topic="$HASS_PREFIX/switch/0x00${DID}/digital_frame"
        [ -z "$interval" ] && interval=$DPF_DEFAULT_INTERVAL
        [ -z "$refresh" ] && refresh=1
        [ -z "$shuffle" ] && shuffle=1
        #[ -z "$photos" ] && photos="[]"
        if [ "x$enable" == "x1" ]; then
            if [ -n "$photos_url" ] && [ -x "/data/bin/frame.sh" ]; then
                info="{\"digital_frame\":{\"setframe\":\"$topic/setframe\",\"enable\":$enable,\"url\":\"$photos_url\",\"interval\":$interval,\"refresh\":$refresh,\"shuffle\":$shuffle}}"
                msg=ON
                echo "{\"digital_frame\":{\"setframe\":\"$topic/setframe\",\"enable\":$enable,\"url\":\"$photos_url\",\"interval\":$interval,\"refresh\":$refresh,\"shuffle\":$shuffle}}" > $DPF_CONFIG
                # call frame.sh
                /data/bin/frame.sh &
            else
                info="{\"digital_frame\":{\"setframe\":\"$topic/setframe\",\"return value\":\"Missing Photos url, or Photos info, or frame.sh!\"}}"
                msg=OFF
                enable=0
                echo "{\"digital_frame\":{\"setframe\":\"$topic/setframe\",\"enable\":$enable,\"url\":\"$photos_url\",\"interval\":$interval,\"refresh\":$refresh,\"shuffle\":$shuffle}}" > $DPF_CONFIG
            fi
        else
            info="{\"digital_frame\":{\"setframe\":\"$topic/setframe\",\"enable\":$enable,\"url\":\"$photos_url\",\"interval\":$interval,\"refresh\":$refresh,\"shuffle\":$shuffle}}"
            msg=OFF
            killall -9 frame.sh
            enable=0
            echo "{\"digital_frame\":{\"setframe\":\"$topic/setframe\",\"enable\":$enable,\"url\":\"$photos_url\",\"interval\":$interval,\"refresh\":$refresh,\"shuffle\":$shuffle}}" > $DPF_CONFIG
        fi
        mqtt_pub $topic "$info"
        sleep .1
        mqtt_pub "$topic/state" "$msg"
    else
        info="{\"digital_frame\":{\"setframe\":\"$topic/setframe\",\"return value\":\"No $PDF_CONFIG\"}}"
        topic="$HASS_PREFIX/switch/0x00${DID}/digital_frame"
        mqtt_pub $topic "$info"
    fi
}

set_frame_info() {
    local topic=$1
    local msg=$2
    local url=; local enable= ; local photos_url=; local photos=
    local ret=; local target=

    ret=$(echo $topic | grep $DID)
    if [ "x$ret" != "x" ]; then
        url=$msg
        if [ -x "/bin/curl" ]; then
            /bin/curl -s -k -L -o $DPF_CONFIG "$url/config.json"
        elif [ -x "/data/bin/curl" ]; then
            /data/bin/curl -s -k -L -o $DPF_CONFIG "$url/config.json"
        else
            info="{\"digital_frame\":{\"setframe\":\"$topic/setframe\",\"return value\":\"No curl.\"}}"
            topic="$HASS_PREFIX/switch/0x00${DID}/digital_frame"
            mqtt_pub $topic "$info"
            return
        fi

        if [ -f "$DPF_CONFIG" ]; then
            enable=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e enable)
            [ "x$enable" == "x1" ] && msg="ON" || msg="OFF"
        else
            msg="OFF"
        fi
        set_frame $topic $msg
    fi
}

set_firmware_lock() {
    local topic=$1
    local msg=$2

    topic="$HASS_PREFIX/switch/0x00${DID}/firmware_lock/state"
    if [ -f $FW_LOCK_FILE ]; then
        if [ "x$msg" == "xOFF" ]; then
            chattr -i $FW_LOCK_FILE
            rm -f $FW_LOCK_FILE
        else
            rm -f $FW_LOCK_FILE
            echo "lock" > $FW_LOCK_FILE
            chattr +i $FW_LOCK_FILE
        fi
    else
        if [ "x$msg" == "xON" ]; then
            mkdir -p "/data/ota_dir"
            echo "lock" > $FW_LOCK_FILE
            chattr +i $FW_LOCK_FILE
        else
            chattr -i $FW_LOCK_FILE
            rm -f $FW_LOCK_FILE
        fi
    fi
    [ -n "$msg" ] && mqtt_pub $topic $msg
}

set_s1e2ha_upgrade () {
    local msg=$1
    if [ "x$msg" == "xPRESS" ]; then
        /data/bin/curl -s -k -L -o /tmp/release.json $LATEST_VERSION_URL
        ret=$?
        if [ "x$ret" == "x0" ]; then
            latest_version=$(cat /tmp/release.json | jshon -Q -e models -e $MODEL -e default -e version | tr -d "." | tr -d '"')
            version=$(echo $VERSION | tr -d "." | tr -d '"')
            [ $((latest_version - version)) -gt 0 ] && /data/bin/install_s1e2ha.sh -u
            rm -f /tmp/release.json
        fi
    fi
}

set_switch() {
    local topic=$1
    local msg=$2
    local current=; local new=
    local ret=; local target=

    ret=$(echo $topic | grep $DID)
    if [ "x$ret" != "x" ]; then
        target=$(echo $topic | cut -d "/" -f 4)
        case $target in
            restore_state)
                msg=$(echo $msg | tr 'a-z' 'A-Z')
                current=$(ubus -S call switch get.config)
                restore_state=$(echo $current | jshon -Q -e restoreState)
                new=""
                if [ "x$msg" == "xON" -o "x$msg" == "x1" ] && [ "x$restore_state" == "x0" ]; then
                    new=$(echo $current | sed -r "s/\"restoreState\":[0-1],/\"restoreState\":1,/g")
                elif [ "x$msg" == "xOFF" -o "x$msg" == "x0" ] && [ "x$restore_state" == "x1" ]; then
                    new=$(echo $current | sed -r "s/\"restoreState\":[0-1],/\"restoreState\":0,/g")
                fi

                cmd="ubus call switch set.config '$new'"
                [ -n "$new" ] && ret=$(eval $cmd)
                ret=$(echo $ret | jshon -Q -e status)
                if [ "x$ret" == "x0" ]; then
                    topic="$HASS_PREFIX/switch/0x00${DID}/restore_state/state"
                    mqtt_pub $topic $msg
                fi
            ;;
            channel*)
                id=$(echo $topic | cut -d "/" -f 4 | cut -d "_" -f 2)
                if [ -n "$id" ]; then
                    msg=$(echo $msg | tr 'a-z' 'A-Z')
                    if [ "x$msg" == "xON" -o "x$msg" == "x1" ]; then
                        cmd="ubus call switch set.state '{\"id\":$id,\"state\":1}'"
                    else
                        cmd="ubus call switch set.state '{\"id\":$id,\"state\":0}'"
                    fi
                    debug "Call cmd: $cmd"
                    ret=$(eval $cmd)
                fi
            ;;
            ftp)
                msg=$(echo $msg | tr 'a-z' 'A-Z')
                set_ftp $msg
            ;;
            standby)
                msg=$(echo $msg | tr 'a-z' 'A-Z')
                set_display $target $msg
            ;;
            screen_saver)
                msg=$(echo $msg | tr 'a-z' 'A-Z')
                set_display $target $msg
            ;;
            mute)
                msg=$(echo $msg | tr 'a-z' 'A-Z')
                set_audio $target $msg
            ;;
            touch_sound)
                msg=$(echo $msg | tr 'a-z' 'A-Z')
                set_audio $target $msg
            ;;
            slient_mode)
                msg=$(echo $msg | tr 'a-z' 'A-Z')
                set_audio $target $msg
            ;;
            digital_frame)
                msg=$(echo $msg | tr 'a-z' 'A-Z')
                set_frame $target $msg
            ;;
            firmware_lock)
                msg=$(echo $msg | tr 'a-z' 'A-Z')
                set_firmware_lock $target $msg
            ;;
        esac
    fi
}

set_button() {
    local topic=$1
    local msg=$2
    local ret=; local target=

    ret=$(echo $topic | grep $DID)
    if [ "x$ret" != "x" ]; then
        target=$(echo $topic | cut -d "/" -f 4)
        case $target in
            reboot)
                msg=$(echo $msg | tr 'a-z' 'A-Z')
                set_reboot $msg
            ;;
            s1e2ha_upgrade)
                set_s1e2ha_upgrade $msg
            ;;
        esac
    fi
}

set_number() {
    local topic=$1
    local msg=$2
    local ret=; local target=

    ret=$(echo $topic | grep $DID)
    if [ "x$ret" != "x" ]; then
        target=$(echo $topic | cut -d "/" -f 4)
        case $target in
            brightness | standby_time | standby_brightness)
                set_display $target $msg
            ;;
        esac
    fi
}

set_select() {
    local topic=$1
    local msg=$2
    name=$(echo $topic | cut -d "/" -f 3)
    ret=$(echo $name | grep $DID)
    if [ "x$ret" != "x" ]; then
        target=$(echo $topic | cut -d "/" -f 4)
        case $target in
            font_size | home_page | language | standby_screen)
                set_display $target $msg
            ;;
            volume_level)
                set_audio $target $msg
            ;;
        esac
    fi
}

set_theme() {
    local topic=$1
    local msg=$2
    local url=

    name=$(echo $topic | cut -d "/" -f 3)
    ret=$(echo $name | grep $DID)
    if [ "x$ret" != "x" ]; then
        url=$msg
        if [ -x "/bin/curl" ]; then
            /bin/curl -s -k -L -o "/tmp/${url##*/}" "$url"
        elif [ -x "/data/bin/curl" ]; then
            /data/bin/curl -s -k -L -o "/tmp/${url##*/}" "$url"
        fi
        if [ -f "${url##*/}" ]; then
            theme_install.sh -u "/tmp/${url##*/}"
            theme_name=`ls /data/theme/tmp/`
            # 获取 /data/theme 下最新修改的目录（排除 tmp）
            newest_dir=$(ls -dt /data/theme/*/ 2>/dev/null | grep -v "/tmp/" | head -1)
            echo "最新目录为：$newest_dir"
            rm -rf "${newest_dir:?}"/*
            src_dir="/data/theme/tmp/$theme_name"
            chmod -R 777 "$src_dir"
            cp -a "$src_dir"/. "$newest_dir"
            rm -rf /data/theme/tmp
            asetprop sys.dfu_progress 100
        fi

        [ -f "/tmp/${url##*/}" ] && rm -f "/tmp/${url##*/}"
    fi
}

set_scene() {
    local topic=$1
    local msg=$2
    local sceneid=; local sceneid_tmp=

    name=$(echo $topic | cut -d "/" -f 3)
    ret=$(echo $name | grep $DID)
    if [ "x$ret" != "x" ]; then
        target=$(echo $topic | cut -d "/" -f 4)
        scservice=$(ubus -S call scservice get)
        nscenes=$(echo $scservice | jshon -Q -e scenesNum)
        # bug, need call again
        [ "x$nscenes" == "x0" ] && scservice=$(ubus -S call scservice get)
        nscenes=$(echo $scservice | jshon -Q -e scenesNum)
        if [ "x$nscenes" != "x0" ]; then
            for i in `seq 1 $nscenes`; do
                sceneid=$(echo $scservice | jshon -Q -e sceneConfig -e $i -e sceneId)
                sceneid_tmp=$(echo $sceneid | tr -d '"' | tr "[A-Z]" "[a-z]" | sed "s/\./_/g")
                sceneid_tmp=${sceneid:0:11}
                if [ "x$target" == "x$sceneid_tmp" ]; then
                    if [ "x$msg" == "xON" ]; then
                        msg="{\"sceneId\":\"$sceneid\"}"
                        ubus call scservice perform "$msg"
                        return
                    fi
                fi
            done
        fi
    fi
}

# main
check_mqtt
read_mqtt_config
get_product_info
get_config
get_wconfig

while true  # Keep an infinite loop to reconnect when connection lost/broker unavailable
do
    $SUB $MQTT_ARGS -v -t "$HASS_PREFIX/+/0x00${DID}/#" -t "$HASS_PREFIX/status" | while read -r payload
    do
        # Here is the callback to execute whenever you receive a message:
        debug "Rx MQTT: ${payload}"
        topic=$(echo $payload | cut -d " " -f 1)
        msg=$(echo $payload | cut -d " " -f 2)
        path=$(echo $topic | cut -d "/" -f 2)
        method=$(echo $topic | cut -d "/" -f 5)
        debug "The path is $path, the method is $method"
        case $path in
            status)
                msg=$(echo $msg | tr '[A-Z]' '[a-z]')
                echo "$msg" > /tmp/hass.status
            ;;
            switch)
                case $method in
                    set)
                        set_switch "$topic" "$msg"
                        ;;
                    setframe)
                        set_frame_info "$topic" "$msg"
                        ;;
                esac
            ;;
            button)
                case $method in
                    set)
                        set_button "$topic" "$msg"
                        ;;
                esac
            ;;
            number)
                case $method in
                    set)
                        set_number "$topic" "$msg"
                        ;;
                esac
            ;;
            select)
                case $method in
                    set)
                        set_select "$topic" "$msg"
                        ;;
                    settheme)
                        set_theme "$topic" "$msg"
                        ;;
                esac
            ;;
            scene)
                case $method in
                    set)
                        set_scene "$topic" "$msg"
                    ;;
                esac
            ;;
            *)
                debug "Unknow path"
            ;;
        esac
    done
    sleep $MQTT_SLEEP  # Wait 10 seconds until reconnection
    killall -9 $SUB
done
