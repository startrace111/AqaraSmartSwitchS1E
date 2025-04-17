#!/bin/sh

DEBUG=0
VERSION="1.0.8"

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
        error "The mosquitto_pub or mosquitto_sub are not exist!"
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

set_state() {
    # process wireless switch is pressed
    local topic=; local msg=
    local payload=$1
    local id=

    # button was pressed by user
    user=$(echo $payload | jshon -Q -e user)
    if [ -n "$user" ]; then
        data=$(echo $payload | jshon -Q -e data)
        if [ -n "$data" ]; then
            id=$(echo $data | jshon -Q -e id)
        fi
        if [ $id != 1 -a $id != 2 -a $id != 3 ]; then
            topic="$HASS_PREFIX/sensor/0x00${DID}/channel_${id}/state"
            state=$(echo $data | jshon -Q -e state)
            if [ "x$state" == "x1" ]; then
                msg="PRESS"
                mqtt_pub "$topic" "$msg"
                sleep .5
                msg="RELEASE"
                mqtt_pub "$topic" "$msg"

            fi
        fi
    fi
}

set_config() {
    local topic=; local msg=
    local payload=$1

    # switch config was pressed by user
    user=$(echo $payload | jshon -Q -e user)
    if [ -n "$user" ]; then
        data=$(echo $payload | jshon -Q -e data)
        if [ -n "$data" ]; then
            restore_state=$(echo $data | jshon -Q -e restoreState)
            topic="$HASS_PREFIX/switch/0x00${DID}/restore_state/state"
            if [ "x$restore_state" == "x1" ]; then
                msg="ON"
            else
                msg="OFF"
            fi
            mqtt_pub "$topic" "$msg"
        fi
    fi
}

user_display() {
    # process user change display settings
    local topic=; local msg=
    local payload=$1
    local enable=

    user=$(echo $payload | jshon -Q -e user)
    if [ -n "$user" ]; then
        data=$(echo $payload | jshon -Q -e data)
        if [ -n "$data" ]; then
            # screen standby
            enable=$(echo $data | jshon -Q -e standby -e enable | tr -d '"')
            topic="$HASS_PREFIX/switch/0x00${DID}/standby/state"
            [ "x$enable" == "x1" ] && msg="ON" || msg="OFF"
            mqtt_pub "$topic" "$msg"

            # screen saver
            enable=$(echo $data | jshon -Q -e standby -e screen | tr -d '"')
            topic="$HASS_PREFIX/switch/0x00${DID}/screen_saver/state"
            [ "x$enable" == "x1" ] && msg="ON" || msg="OFF"
            mqtt_pub "$topic" "$msg"

            # brightness
            msg=$(echo $data | jshon -Q -e brightness | tr -d '"')
            topic="$HASS_PREFIX/number/0x00${DID}/brightness/state"
            mqtt_pub "$topic" "$msg"

            # standby time
            msg=$(echo $data | jshon -Q -e standby -e seconds | tr -d '"')
            topic="$HASS_PREFIX/number/0x00${DID}/standby_time/state"
            mqtt_pub "$topic" "$msg"

            # standby brightness
            msg=$(echo $data | jshon -Q -e standby -e brightness | tr -d '"')
            topic="$HASS_PREFIX/number/0x00${DID}/standby_brightness/state"
            mqtt_pub "$topic" "$msg"

            # home page
            msg=$(echo $data | jshon -Q -e homePage | tr -d '"')
            topic="$HASS_PREFIX/select/0x00${DID}/home_page/state"
            mqtt_pub "$topic" "$msg"

            # standby screen
            value=$(echo $data | jshon -Q -e standby -e screenStyle | tr -d '"')
            topic="$HASS_PREFIX/select/0x00${DID}/standby_screen/state"
            mqtt_pub "$topic" "$value"
        fi
    fi
}

user_audio() {
    # process user change audio settings
    local topic=; local msg=
    local payload=$1
    local value=

    user=$(echo $payload | jshon -Q -e user)
    if [ -n "$user" ]; then
        data=$(echo $payload | jshon -Q -e data)
        if [ -n "$data" ]; then
            # mute
            value=$(echo $data | jshon -Q -e mute | tr -d '"')
            topic="$HASS_PREFIX/switch/0x00${DID}/mute/state"
            [ "x$value" == "x1" ] && msg="ON" || msg="OFF"
            mqtt_pub "$topic" "$msg"

            # touch sound
            value=$(echo $data | jshon -Q -e touchSound | tr -d '"')
            topic="$HASS_PREFIX/switch/0x00${DID}/touch_sound/state"
            [ "x$value" == "x1" ] && msg="ON" || msg="OFF"
            mqtt_pub "$topic" "$msg"

            # slient mode
            value=$(echo $data | jshon -Q -e silentMode | tr -d '"')
            topic="$HASS_PREFIX/switch/0x00${DID}/slient_mode/state"
            [ "x$value" == "x1" ] && msg="ON" || msg="OFF"
            mqtt_pub "$topic" "$msg"

            # font size
            value=$(echo $data | jshon -Q -e fontSize | tr -d '"')
            topic="$HASS_PREFIX/select/0x00${DID}/font_size/state"
            mqtt_pub "$topic" "$value"

            # volume level
            value=$(echo $data | jshon -Q -e volumeLevel | tr -d '"')
            topic="$HASS_PREFIX/select/0x00${DID}/volume_level/state"
            mqtt_pub "$topic" "$value"
        fi
    fi
}

user_theme() {
    # process user change theme
    local topic=; local msg=
    local payload=$1
    local name=

    user=$(echo $payload | jshon -Q -e user)
    if [ -n "$user" ]; then
        data=$(echo $payload | jshon -Q -e data)
        if [ -n "$data" ]; then
            # theme
            value=$(echo $data | jshon -Q -e themeName)
            name="$DEVICE_NAME $name"
            sleep 10
            state=$(cat /data/theme/$value/config.json | jshon -Q -e name | tr -d '"')
            unique_id="0x00${DID}_theme"
            prefix_topic="$HASS_PREFIX/select/0x00${DID}/theme"
            topic="$prefix_topic/config"
            msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"~\":\"$prefix_topic\",\"icon\":\"$icon\",\"options\":[\"$state\"],\"avty_t\":\"~/status\",\"stat_t\":\"~/state\",\"cmd_t\":\"~/set\"}"
            mqtt_pub $topic "$msg" 1 "-r"
            sleep .1
            topic="$HASS_PREFIX/select/0x00${DID}/theme/state"
            mqtt_pub "$topic" "$state"
        fi
    fi
}

scservice_perform() {
    local topic=; local sceneid=
    local payload=$1

    # TODO, user perform scene
    # return

    user=$(echo $payload | jshon -Q -e user)
    if [ -n "$user" ]; then
        data=$(echo $payload | jshon -Q -e data)
        if [ -n "$data" ]; then
            sceneid=$(echo $data | jshon -Q -e sceneId | tr -d '"' | tr "[A-Z]" "[a-z]" | sed "s/\./_/g")
            sceneid=${sceneid:0:11}
            unique_id="0x00${DID}_${sceneid}"
            topic="$HASS_PREFIX/binary_sensor/0x00${DID}/$sceneid/set"
            mqtt_pub "$topic" "ON"
            sleep .1
            mqtt_pub "$topic" "OFF"
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
    ubus -v monitor | awk '{$1=$2=$3=$4=""; print $0}' | while read -r payload
    do
        debug "Rx ubus: ${payload}"
        if [ $(echo $payload | jshon -l) -gt 0 ]; then
            method=$(echo $payload | jshon -Q -e method | tr -d '"')
            debug "method is $method"
            if [ -n "$method" ]; then
                case $method in
                    set.state)
                        set_state "$payload"
                    ;;
                    config)
                        set_config "$payload"
                    ;;
                    theme)
                        user_theme "$payload"
                    ;;
                    set.display)
                        user_display "$payload"
                    ;;
                    set.audio)
                        user_audio "$payload"
                    ;;
                    perform)
                        scservice_perform "$payload"
                    ;;
                esac
            fi
        fi
    done
    sleep 1  # Wait 1 seconds until reconnection
done
