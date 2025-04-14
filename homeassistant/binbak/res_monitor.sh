#!/bin/sh

DEBUG=1
VERSION="1.0.8"
LATEST_VERSION_URL="https://gh-proxy.com/raw.githubusercontent.com/startrace111/AqaraSmartSwitchS1E/master/homeassistant/release.json"

# homeassistant discovery prefix
HASS_PREFIX="homeassistant"
HASS_STATUS="online"
HASS_DOMAINS="binary_sensor button number scene sensor select switch "
BINARY_SENSORS_TYPE="cloud_connectivity connectivity s1e2ha_update update "
BINARY_SENSORS_ICON="mdi:gauge mdi:gauge mdi:package-up mdi:package-up"
BUTTONS_TYPE="reboot s1e2ha_upgrade "
BUTTONS_NAME="Reboot S1E2HA_Upgrade "
NUMBERS_TYPE="brightness standby_time standby_brightness "
NUMBERS_MIN="0 0 0 "
NUMBERS_MAX="100 3599 100 "
SENSORS_TYPE="energy power current cpu_load uptime ipaddress temperature ssid strength data_usage memory_usage s1e2ha_version "
SENSORS_ICON="mdi:lightning-bolt mdi:lightning-bolt mdi:current-ac mdi:gauge mdi:clock mdi:ip-network-outline mdi:thermometer mdi:wifi mdi:wifi mdi:gauge mdi:gauge mdi:new-box "
SENSORS_UNIT="kWh W mA % s '' °C '' dBm % % '' "
SELECTS_TYPE="theme font_size volume_level home_page standby_screen language"
SELECTS_ICON="mdi:theme-light-dark mdi:format-size mdi:volume-medium mdi:home-circle mdi:book-variant mdi:translate "
SELECTS_OPTIONS="[] [\"default\",\"medium\",\"large\"] [\"low\",\"middle\",\"high\"] [\"0\",\"1\",\"2\",\"3\",\"4\",\"5\"] [\"clock\",\"clock2\",\"weather\",\"anaclock\",\"anaclock2\",\"anaclock3\"] [\"Simplified_Chinese\",\"English\",\"Traditional_Chinese\"]"
SWITCHS_TYPE="restore_state standby screen_saver mute touch_sound slient_mode ftp digital_frame firmware_lock "
SWITCHS_NAME="Restore_State StandBy Screen_Saver Mute Touch_Sound Slient_Mode FTP_Server Digital_Frame Firmware_Lock "
SWITCHS_ICON="mdi:toggle-switch-variant mdi:toggle-switch-variant mdi:toggle-switch-variant mdi:toggle-switch-variant mdi:toggle-switch-variant mdi:toggle-switch-variant mdi:toggle-switch-variant mdi:image-frame mdi:lock "
# heartbeat every mintue
OFF_DELAY_CONNECTIVITY=120
# /lumi/func/sync/check, linkages, check every thirty mintues
OFF_DELAY_CLOUD=2100
ENTITIES_FILE="/tmp/entities.lst"

# S1E info
PRODUCT_INFO=""
DEVICE_NAME=""
DID=""
MODEL=""
SW_VERSION=""
IDENTIFIERS=""
CONFIG=""
WCONFIG=""
SYS_INFO=""
MAC=""
LOCATION=""

# mqtt configuration
PUB=""
SUB=""
MQTT_CONF="/data/etc/mqtt.conf"
MQTT_IP=127.0.0.1
MQTT_USER=""
MQTT_PASSWORD=""
MQTT_PORT=1883
MQTT_ARGS=""
MQTT_SLEEP=3

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
    MAC=$(echo $PRODUCT_INFO | jshon -e wifiAddr | tr -d '"')
    LOCATION=$(echo $PRODUCT_INFO | jshon -e location | tr -d '"')
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

check_ha_driver() {
    # remove ha_drivern monitor in ap_monitor.sh, monitor here
    cp -f /bin/app_monitor.sh /tmp/app_monitor.sh
    sed ':a;N;$!ba;s/ha_driven     handler_ha_driven_leaved    \\\n//g' -i /tmp/app_monitor.sh
    killall -9 app_monitor.sh; /tmp/app_monitor.sh &

#    if [ ! -f /tmp/aulog.txt ]; then
#        asetprop persist.app.debug_log true
#        pkill -f ha_driven

#        sleep 2
#    fi

#    if [ ! -f /tmp/aulog.txt ]; then
#        error "There is aulog.txt! Exit!"
#        exit 1
#    fi
}

mqtt_pub() {
    local topic=$1
    local msg=$2
    local use_device=$3
    local args=$4
    local device="\"dev\":{\"name\":\"S1E $DID\",\"ids\":\"$IDENTIFIERS\",\"mf\":\"Aqara\",\"sw\":\"$SW_VERSION\",\"mdl\":\"$MODEL\",\"hw\":\"SSD212\",\"sa\":\"$LOCATION\",\"cns\":[[\"mac\", \"$MAC\"]]}"

    if [ -z $use_device ]; then
        use_device=0
    fi

    msg=`[ $use_device -eq 0 ] && echo $msg || echo $msg | sed -r "s#^(.*)[}]#\1,$device}#"`

    debug "Topic: $topic"
    debug "Message: $msg"
    cmd="$PUB $MQTT_ARGS $args -t $topic -m '$msg'"
    eval "$cmd"
}

setup_sensors() {
    local type=$1
    local icon=$2
    local unit=$3
    local unique_id=
    local name=
    local topic=; local msg=

    case $type in
        ipaddress)
            name="$DEVICE_NAME IP Address"
        ;;
        cpu_load)
            name="$DEVICE_NAME CPU Load"
        ;;
        data_usage)
            name="$DEVICE_NAME Data Usage"
        ;;
        memory_usage)
            name="$DEVICE_NAME Memory Usage"
        ;;
        temperature)
            name="$DEVICE_NAME CPU Temperature"
        ;;
        strength)
            name="$DEVICE_NAME WiFi Signal"
        ;;
        s1e2ha_version)
            name="$DEVICE_NAME S1E2HA Version"
        ;;
        *)
            name=`echo ${type:0:1} | tr '[a-z]' '[A-Z]'`${type:1}
            name="$DEVICE_NAME $name"
        ;;
    esac
    unique_id="0x00${DID}_$type"
    prefix_topic="$HASS_PREFIX/sensor/0x00${DID}/$type"
    topic="$prefix_topic/config"
    template="{{value_json.$type}}"
    case $type in
        power | energy | current)
            state_topic="$HASS_PREFIX/sensor/0x00${DID}/$type/state"
            msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"icon\":\"$icon\",\"dev_cla\":\"$type\",\"unit_of_meas\":\"$unit\",\"ent_cat\":\"diagnostic\",\"~\":\"$prefix_topic\",\"stat_t\":\"$state_topic\",\"val_tpl\":\"$template\",\"avty_t\":\"~/status\"}"
        ;;
        *)
            state_topic="$HASS_PREFIX/sensor/0x00${DID}/state"
            if [ "x$unit" == "x''" ]; then
                msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"icon\":\"$icon\",\"ent_cat\":\"diagnostic\",\"~\":\"$prefix_topic\",\"stat_t\":\"$state_topic\",\"val_tpl\":\"$template\",\"avty_t\":\"~/status\"}"
            else
                msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"icon\":\"$icon\",\"unit_of_meas\":\"$unit\",\"ent_cat\":\"diagnostic\",\"~\":\"$prefix_topic\",\"stat_t\":\"$state_topic\",\"val_tpl\":\"$template\",\"avty_t\":\"~/status\"}"
            fi
        ;;
    esac

    # remove old
#    mqtt_pub $topic ""
#    sleep .1
    mqtt_pub $topic "$msg" 1 "-r"
    sed -e ':a' -e 'N' -e '$!ba' -e "s#sensor/0x00${DID}/$type\n##g" -i $ENTITIES_FILE
    echo "sensor/0x00${DID}/$type" >> $ENTITIES_FILE

    topic="$prefix_topic/status"
    msg="online"
    mqtt_pub $topic "$msg"

#    if [ "x$type" != "xpower" ] && [ "x$type" != "xenergy" ] && [ "x$type" != "xpower" ]; then
#        topic=$state_topic
#        mqtt_pub $state_topic "unknown"
#    fi
}

config_sensors() {
    local nsensors=
    local type=; local icon=; local unit=

    nsensors=$(echo $SENSORS_TYPE | awk '{print NF}')
    for i in `seq 1 $nsensors`; do
        type=$(echo $SENSORS_TYPE | awk -v x=$i '{print $x}')
        icon=$(echo $SENSORS_ICON | awk -v x=$i '{print $x}')
        unit=$(echo $SENSORS_UNIT | awk -v x=$i '{print $x}')
        setup_sensors "$type" "$icon" "$unit"
        sleep .1
    done
}

setup_binary_sensors() {
    local type=$1
    local icon=$2
    local unique_id=
    local name=
    local topic=; local msg=

    case $type in
        connectivity)
            name="$DEVICE_NAME"
        ;;
        cloud_connectivity)
            name="$DEVICE_NAME Cloud"
        ;;
        s1e2ha_update)
            name="$DEVICE_NAME S1E2HA Update"
        ;;
        *)
            name=`echo ${type:0:1} | tr '[a-z]' '[A-Z]'`${type:1}
            name="$DEVICE_NAME $name"
        ;;
    esac
    unique_id="0x00${DID}_$type"
    prefix_topic="$HASS_PREFIX/binary_sensor/0x00${DID}/$type"
    topic="$prefix_topic/config"
    case $type in
        connectivity)
            state_topic="$HASS_PREFIX/binary_sensor/0x00${DID}/$type/state"
            msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"dev_cla\":\"$type\",\"ent_cat\":\"diagnostic\",\"~\":\"$prefix_topic\",\"stat_t\":\"$state_topic\",\"avty_t\":\"~/status\",\"off_delay\":$OFF_DELAY_CONNECTIVITY}"
        ;;
        cloud_connectivity)
            state_topic="$HASS_PREFIX/binary_sensor/0x00${DID}/$type/state"
            msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"dev_cla\":\"connectivity\",\"ent_cat\":\"diagnostic\",\"~\":\"$prefix_topic\",\"stat_t\":\"$state_topic\",\"avty_t\":\"~/status\",\"off_delay\":$OFF_DELAY_CLOUD}"
        ;;
        *update)
            state_topic="$HASS_PREFIX/binary_sensor/0x00${DID}/$type/state"
            msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"dev_cla\":\"update\",\"icon\":\"$icon\",\"ent_cat\":\"diagnostic\",\"~\":\"$prefix_topic\",\"stat_t\":\"$state_topic\",\"avty_t\":\"~/status\"}"
        ;;
        *)
            state_topic="$HASS_PREFIX/binary_sensor/0x00${DID}/state"
            msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"dev_cla\":\"$type\",\"icon\":\"$icon\",\"ent_cat\":\"diagnostic\",\"~\":\"$prefix_topic\",\"stat_t\":\"$state_topic\",\"avty_t\":\"~/status\"}"
        ;;
    esac

    # remove old
#    mqtt_pub $topic ""
#    sleep .1
    mqtt_pub $topic "$msg" 1 "-r"

    sed -e ':a' -e 'N' -e '$!ba' -e "s#binary_sensor/0x00${DID}/$type\n##g" -i $ENTITIES_FILE
    echo "binary_sensor/0x00${DID}/$type" >> $ENTITIES_FILE

    topic="$prefix_topic/status"
    msg="online"
    mqtt_pub $topic "$msg"

    topic=$state_topic
    mqtt_pub $state_topic "unknown"
}

config_binary_sensors() {
    local nsensors=
    local type=; local icon=;

    nsensors=$(echo $BINARY_SENSORS_TYPE | awk '{print NF}')
    for i in `seq 1 $nsensors`; do
        type=$(echo $BINARY_SENSORS_TYPE | awk -v x=$i '{print $x}')
        icon=$(echo $BINARY_SENSORS_ICON | awk -v x=$i '{print $x}')
        setup_binary_sensors "$type" "$icon"
        sleep .1
    done
}

setup_switchs() {
    local topic=; local msg=
    local name=$1
    local unique_id=$2
    local icon=$3
    local type=

    type=$(echo $unique_id | cut -d "_" -f 2-3)
    prefix_topic="$HASS_PREFIX/switch/0x00${DID}/$type"
    topic="$HASS_PREFIX/switch/0x00${DID}/$type/config"
    case $type in
        digital_frame)
            msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$prefix_topic\",\"avty_t\":\"~/status\",\"stat_t\":\"~/state\",\"cmd_t\":\"~/set\",\"send_cmd_t\":\"~/setframe\",\"json_attr_t\":\"~\",\"json_attr_tpl\":\"{{value_json.digital_frame|tojson}}\"}"
        ;;
        *)
            msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$prefix_topic\",\"avty_t\":\"~/status\",\"stat_t\":\"~/state\",\"cmd_t\":\"~/set\"}"
        ;;
    esac

    # remove old
#    mqtt_pub $topic ""
#    sleep .1
    mqtt_pub $topic "$msg" 1 "-r"

    sed -e ':a' -e 'N' -e '$!ba' -e "s#switch/0x00${DID}/$type\n##g" -i $ENTITIES_FILE
    echo "switch/0x00${DID}/$type" >> $ENTITIES_FILE
}

config_switchs() {
    local topic=; local msg=
    local nswitchs=; local state=
    local name=; local unique_id=; local icon=

    nswitchs=$(echo $CONFIG | jshon -e num)
    state=$(ubus -S call switch state)
    for i in `seq 1 $nswitchs`; do
        id=$(echo $CONFIG | jshon -e switchs -e $((i - 1)) -e "id")
        if [ "x$id" == "x33" ]; then
            debug "need to remove channel_${id}"
        fi
        id=$(echo $state | jshon -e switchs -e $((i - 1)) -e "id")
        unique_id="0x00${DID}_channel_${id}"
        name=$(echo $CONFIG | jshon -e switchs -e $((i - 1)) -e "name" | tr -d '"')
        icon="mdi:toggle-switch-variant"
        setup_switchs "$name" "$unique_id" "$icon"
        sleep .1
    done

    # other switchs
    nswitchs=$(echo $SWITCHS_TYPE | awk '{print NF}')
    for i in `seq 1 $nswitchs`; do
        name=$(echo $SWITCHS_NAME | awk -v x=$i '{print $x}')
        name=$(echo $name | sed 's/_/ /g')
        name="$DEVICE_NAME $name"
        type=$(echo $SWITCHS_TYPE | awk -v x=$i '{print $x}')
        unique_id="0x00${DID}_${type}"
        icon=$(echo $SWITCHS_ICON | awk -v x=$i '{print $x}')
        setup_switchs "$name" "$unique_id" "$icon"

        sleep .1
        topic="$HASS_PREFIX/switch/0x00${DID}/${type}/status"
        msg="online"
        mqtt_pub $topic "$msg"
        sleep .1
    done
}

config_wswitchs() {
    local nsensors=
    local topic=; local msg=

    nsensors=$(echo $WCONFIG | jshon -e num)
    for i in `seq 1 $nsensors`; do
        id=$(echo $WCONFIG | jshon -e switchs -e $((i - 1)) -e "id")
        unique_id="0x00${DID}_channel_${id}"
        name=$(echo $WCONFIG | jshon -e switchs -e $((i - 1)) -e "name" | tr -d '"')
        icon="mdi:button-pointer"
        prefix_topic="$HASS_PREFIX/sensor/0x00${DID}/channel_${id}"
        topic="$prefix_topic/config"
        msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$prefix_topic\",\"avty_t\":\"~/status\",\"stat_t\":\"~/state\"}"

        # remove old
#        mqtt_pub $topic ""
#        sleep .1
        mqtt_pub "$topic" "$msg" 1 "-r"
        sleep .1
        sed -e ':a' -e 'N' -e '$!ba' -e "s#sensor/0x00${DID}/channel_${id}\n##g" -i $ENTITIES_FILE
        echo "sensor/0x00${DID}/channel_${id}" >> $ENTITIES_FILE
    done

}

setup_buttons() {
    local topic=; local msg=
    local type=$1
    local name=$2

    # other button
    unique_id="0x00${DID}_${type}"
    icon="mdi:button-pointer"
    prefix_topic="$HASS_PREFIX/button/0x00${DID}/$type"
    topic="$prefix_topic/config"
    if [ "x$type" == "xreboot" ]; then
        msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"icon\":\"$icon\",\"dev_cla\":\"restart\",\"~\":\"$prefix_topic\",\"avty_t\":\"~/status\",\"cmd_t\":\"~/set\"}"
    else
        msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"icon\":\"$icon\",\"~\":\"$prefix_topic\",\"avty_t\":\"~/status\",\"cmd_t\":\"~/set\"}"
    fi
    # remove old
#    mqtt_pub $topic ""
    mqtt_pub $topic "$msg" 1 "-r"
    sleep .1
    sed -e ':a' -e 'N' -e '$!ba' -e "s#button/0x00${DID}/$type\n##g" -i $ENTITIES_FILE
    echo "button/0x00${DID}/$type" >> $ENTITIES_FILE

    topic="$prefix_topic/status"
    msg="online"
    mqtt_pub $topic "$msg"
}

config_buttons() {
    local nbuttons=; local name=

    nbuttons=$(echo $BUTTONS_TYPE | awk '{print NF}')
    for i in `seq 1 $nbuttons`; do
        name=$(echo $BUTTONS_NAME | awk -v x=$i '{print $x}')
        name=$(echo $name | sed 's/_/ /g')
        name="$DEVICE_NAME $name"
        type=$(echo $BUTTONS_TYPE | awk -v x=$i '{print $x}')
        setup_buttons "$type" "$name"
    done
}

setup_numbers() {
    local type=$1
    local min=$2
    local max=$3
    local unique_id=
    local name=
    local topic=; local msg=

    case $type in
        standby_time)
            name="$DEVICE_NAME Standby Time"
        ;;
        standby_brightness)
            name="$DEVICE_NAME Standby Brightness"
        ;;
        *)
            name=`echo ${type:0:1} | tr '[a-z]' '[A-Z]'`${type:1}
            name="$DEVICE_NAME $name"
        ;;
    esac
    unique_id="0x00${DID}_$type"
    prefix_topic="$HASS_PREFIX/number/0x00${DID}/$type"
    topic="$prefix_topic/config"
    msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"~\":\"$prefix_topic\",\"min\":\"$min\",\"max\":\"$max\",\"avty_t\":\"~/status\",\"stat_t\":\"~/state\",\"cmd_t\":\"~/set\"}"
    mqtt_pub $topic "$msg" 1 "-r"

    sed -e ':a' -e 'N' -e '$!ba' -e "s#number/0x00${DID}/$type\n##g" -i $ENTITIES_FILE
    echo "number/0x00${DID}/$type" >> $ENTITIES_FILE

    topic="$prefix_topic/status"
    msg="online"
    mqtt_pub $topic "$msg"
}

config_numbers() {
    local nnumbers=
    local type=; local min=; local max=;

    nnumbers=$(echo $NUMBERS_TYPE | awk '{print NF}')
    for i in `seq 1 $nnumbers`; do
        type=$(echo $NUMBERS_TYPE | awk -v x=$i '{print $x}')
        min=$(echo $NUMBERS_MIN | awk -v x=$i '{print $x}')
        max=$(echo $NUMBERS_MAX | awk -v x=$i '{print $x}')
        setup_numbers "$type" "$min" "$max"
        sleep .1
    done
}

setup_selects() {
    local type=$1
    local icon=$2
    local options=$3
    local unique_id=
    local name=
    local topic=; local msg=

    case $type in
        font_size)
            name="$DEVICE_NAME Font Size"
        ;;
        volume_level)
            name="$DEVICE_NAME Volume Level"
        ;;
        home_page)
            name="$DEVICE_NAME Home Page"
        ;;
        standby_screen)
            name="$DEVICE_NAME Standby Screen"
        ;;
        language)
            name="$DEVICE_NAME Language"
        ;;
        *)
            name=`echo ${type:0:1} | tr '[a-z]' '[A-Z]'`${type:1}
            name="$DEVICE_NAME $name"
        ;;
    esac
    unique_id="0x00${DID}_$type"
    prefix_topic="$HASS_PREFIX/select/0x00${DID}/$type"
    topic="$prefix_topic/config"
    if [ "x$type" == "xtheme" ]; then
        msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"~\":\"$prefix_topic\",\"icon\":\"$icon\",\"options\":$options,\"avty_t\":\"~/status\",\"stat_t\":\"~/state\",\"cmd_t\":\"~/set\",\"send_cmd_t\":\"~/settheme\",\"json_attr_t\":\"~\",\"json_attr_tpl\":\"{{value_json.theme|tojson}}\"}"
    else
        msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"~\":\"$prefix_topic\",\"icon\":\"$icon\",\"options\":$options,\"avty_t\":\"~/status\",\"stat_t\":\"~/state\",\"cmd_t\":\"~/set\"}"
    fi
    mqtt_pub $topic "$msg" 1 "-r"

    sed -e ':a' -e 'N' -e '$!ba' -e "s#select/0x00${DID}/$type\n##g" -i $ENTITIES_FILE
    echo "select/0x00${DID}/$type" >> $ENTITIES_FILE

    topic="$prefix_topic/status"
    msg="online"
    mqtt_pub $topic "$msg"

    # special case, set the attribute of theme
    if [ "x$type" == "xtheme" ]; then
        sleep .1
        topic="$HASS_PREFIX/select/0x00${DID}/theme"
        msg="{\"theme\":{\"settheme\":\"$topic/settheme\"}}"
        mqtt_pub $topic "$msg"
    fi
}

config_selects() {
    local nselects=
    local type=; local icon=;

    nselects=$(echo $SELECTS_TYPE | awk '{print NF}')
    for i in `seq 1 $nselects`; do
        cloud=$(agetprop persist.sys.cloud)
        type=$(echo $SELECTS_TYPE | awk -v x=$i '{print $x}')
        icon=$(echo $SELECTS_ICON | awk -v x=$i '{print $x}')
        options=$(echo $SELECTS_OPTIONS | awk -v x=$i '{print $x}')
        setup_selects "$type" "$icon" "$options"
        sleep .1
    done
}

setup_scenses() {
    local sceneid=$1
    local name=$2
    local unique_id=
    local topic=; local msg=

    unique_id="0x00${DID}_$sceneid"
    prefix_topic="$HASS_PREFIX/scene/0x00${DID}/$sceneid"
    topic="$prefix_topic/config"
    msg="{\"name\":\"$name\",\"uniq_id\":\"$unique_id\",\"~\":\"$prefix_topic\",\"avty_t\":\"~/status\",\"cmd_t\":\"~/set\",\"payload_on\":\"ON\"}"
    mqtt_pub $topic "$msg" 0 "-r"

    sed -e ':a' -e 'N' -e '$!ba' -e "s#scene/0x00${DID}/$sceneid\n##g" -i $ENTITIES_FILE
    echo "scene/0x00${DID}/$sceneid" >> $ENTITIES_FILE

    topic="$prefix_topic/status"
    msg="online"
    mqtt_pub $topic "$msg"
}

config_scenes() {
    local nscenes=; local scservice=
    local sceneid=; local name=;
    local topic=

    scservice=$(ubus -S call scservice get)
    nscenes=$(echo $scservice | jshon -Q -e scenesNum)
    # bug, need call again
    [ "x$nscenes" == "x0" ] && scservice=$(ubus -S call scservice get)
    nscenes=$(echo $scservice | jshon -Q -e scenesNum)
    if [ "x$nscenes" != "x0" ]; then
        for entity in `cat $ENTITIES_FILE  | grep scene`; do
            topic="$HASS_PREFIX/$entity/config"
            mqtt_pub $topic ""
        done
        for i in `seq 1 $nscenes`; do
            sceneid=$(echo $scservice | jshon -Q -e sceneConfig -e $i -e sceneId | tr -d '"' | tr "[A-Z]" "[a-z]" | sed "s/\./_/g")
            sceneid=${sceneid:0:11}
            name=$(echo $scservice | jshon -Q -e sceneConfig -e $i -e description | tr -d '"')
            setup_scenses "$sceneid" "$name"
            sleep .1
        done
    fi

}

set_status() {
    local nswitchs=
    local topic=; local msg=

    nswitchs=$(echo $CONFIG | jshon -e num)
    for i in `seq 1 $nswitchs`; do
        id=$(echo $CONFIG | jshon -e switchs -e $((i - 1)) -e "id")
        unique_id="0x00${DID}_channel_${id}"
        topic="$HASS_PREFIX/switch/0x00${DID}/channel_${id}/status"
        enable=$(echo $CONFIG | jshon -e switchs -e $((i - 1)) -e "enable")
        msg=`[ $enable == 1 ] && echo "online" || echo "offline"`
        mqtt_pub $topic "$msg"
    done
}

set_wstatus() {
    local nsensors=
    local topic=; local msg=

    nsensors=$(echo $WCONFIG | jshon -e num)
    for i in `seq 1 $nsensors`; do
        id=$(echo $WCONFIG | jshon -e switchs -e $((i - 1)) -e "id")
        unique_id="0x00${DID}_channel_${id}"
        topic="$HASS_PREFIX/sensor/0x00${DID}/channel_${id}/status"
        enable=$(echo $WCONFIG | jshon -e switchs -e $((i - 1)) -e "enable")
        msg=`[ $enable == 1 ] && echo "online" || echo "offline"`
        mqtt_pub $topic "$msg"
    done
}

pub_discovery() {

    if [ ! -f $ENTITIES_FILE ]; then
        touch $ENTITIES_FILE
    fi

    # binary_sensors
    [ -n "$(echo $HASS_DOMAINS | grep 'binary_sensor')" ] && config_binary_sensors

    # numbers
    [ -n "$(echo $HASS_DOMAINS | grep ' number')" ] && config_numbers

    # scenes
    [ -n "$(echo $HASS_DOMAINS | grep ' scene')" ] && config_scenes

    # selects
    [ -n "$(echo $HASS_DOMAINS | grep ' select')" ] && config_selects

    # sensors
    [ -n "$(echo $HASS_DOMAINS | grep ' sensor')" ] && config_sensors

    # switchs
    [ -n "$(echo $HASS_DOMAINS | grep ' switch')" ] && config_switchs

    # wireless switch
    [ -n "$(echo $HASS_DOMAINS | grep ' switch')" ] && config_wswitchs

    # buttons
    [ -n "$(echo $HASS_DOMAINS | grep ' button')" ] && config_buttons

    HASS_STATUS="online"
}

set_connectivity() {
    local type=$1
    local onoff=$2
    local topic=; local msg=;

    if [ "x$type" == "xordinary" ]; then
        type=""
    else
        type="${type}_"
    fi

    prefix_topic="$HASS_PREFIX/binary_sensor/0x00${DID}/${type}connectivity"
    topic="$prefix_topic/state"
    if [ "x$onoff" == "x1" ]; then
        msg="ON"
    else
        msg="OFF"
    fi
    mqtt_pub $topic "$msg"
}

set_state() {
    local topic=; local msg=
    local device_type=$1
    local type=$2
    local msg=$3

    topic="$HASS_PREFIX/${device_type}/0x00${DID}/${type}/state"
    mqtt_pub "$topic" "$msg"
}

get_state() {
    local nswitchs=
    local topic=; local msg=
    local payload=$1

    nswitchs=$(echo $payload | jshon -e state -e num)
    for i in `seq 1 $nswitchs`; do
        id=$(echo $payload | jshon -e state -e switchs -e $((i - 1)) -e "id")
        unique_id="0x00${DID}_channel_${id}"
        topic="$HASS_PREFIX/switch/0x00${DID}/channel_${id}/state"
        state=$(echo $payload | jshon -e state -e switchs -e $((i - 1)) -e "state")
        msg=`[ $state == 1 ] && echo "ON" || echo "OFF"`
        mqtt_pub $topic "$msg"
    done
}

set_states() {
    local nentitys=; local state=; local value=
    local payload=
    local topic=; local msg=

    # 3 switchs state
    payload=$(ubus -S call switch state)
    get_state "{ \"state\": $payload }"

    # other switchs state
    nentitys=$(echo $SWITCHS_TYPE | awk '{print NF}')
    for i in `seq 1 $nentitys`; do
        type=$(echo $SWITCHS_TYPE | awk -v x=$i '{print $x}')
        case $type in
            restore_state)
                value=$(ubus -S call switch get.config | jshon -Q -e restoreState)
                [ "x$value" != "x" ] && state="ON" || state="OFF"
            ;;
            ftp)
                value=$(pgrep tcpsvd)
                [ "x$value" != "x" ] && state="ON" || state="OFF"
            ;;
            standby)
                value=$(ubus -S call setting get.display | jshon -Q -e standby -e enable)
                [ "x$value" == "x1" ] && state="ON" || state="OFF"
            ;;
            screen_saver)
                value=$(ubus -S call setting get.display | jshon -Q -e standby -e screen)
                [ "x$value" == "x1" ] && state="ON" || state="OFF"
            ;;
            mute)
                value=$(ubus -S call setting get.audio | jshon -Q -e mute)
                [ "x$value" == "x1" ] && state="ON" || state="OFF"
            ;;
            touch_sound)
                value=$(ubus -S call setting get.audio | jshon -Q -e touchSound)
                [ "x$value" == "x1" ] && state="ON" || state="OFF"
            ;;
            slient_mode)
                value=$(ubus -S call setting get.audio | jshon -Q -e silentMode)
                [ "x$value" == "x1" ] && state="ON" || state="OFF"
            ;;
            digital_frame)
                topic="$HASS_PREFIX/switch/0x00${DID}/digital_frame"
                if [ -f $DPF_CONFIG ]; then
                    state="OFF"
                    enable=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e enable)
                    [ -z "$enable" ] && enable=0
                    [ "x$enable" == "x1" ] && state="ON"
                    url=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e url | tr -d '"')
                    photos=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e photos | tr -d '"')
                    [ -z "$photos" ] && photos="[]"
                    interval=$(cat $DPF_CONFIG | jshon -Q -e digital_frame -e interval)
                    [ -z "$interval" ] && interval=$DPF_DEFAULT_INTERVAL
                    msg="{\"digital_frame\":{\"setframe\":\"$topic/setframe\",\"enable\":$enable,\"url\":\"$url\",\"photos\":\"$photos\",\"interval\":$interval}}"
                    mqtt_pub $topic "$msg"
                else
                    msg="{\"digital_frame\":{\"setframe\":\"$topic/setframe\"}}"
                    mqtt_pub $topic "$msg"
                    state="OFF"
                fi
            ;;
            firmware_lock)
                if [ -f $FW_LOCK_FILE ]; then
                    value=$(cat $FW_LOCK_FILE | grep lock)
                    [ -n "$value" ] && state="ON" || state="OFF"
                else
                    state="OFF"
                fi
            ;;
        esac
        [ -n "$state" ] && set_state "switch" $type $state
    done

    # numbers
    nentitys=$(echo $NUMBERS_TYPE | awk '{print NF}')
    for i in `seq 1 $nentitys`; do
        type=$(echo $NUMBERS_TYPE | awk -v x=$i '{print $x}')
        case $type in
            brightness)
                state=$(ubus -S call setting get.display | jshon -Q -e brightness)
            ;;
            standby_time)
                state=$(ubus -S call setting get.display | jshon -Q -e standby -e seconds)
            ;;
            standby_brightness)
                state=$(ubus -S call setting get.display | jshon -Q -e standby -e brightness)
            ;;
        esac
        [ -n "$state" ] && set_state "number" $type $state
    done

    # selects
    nentitys=$(echo $SELECTS_TYPE | awk '{print NF}')
    for i in `seq 1 $nentitys`; do
        type=$(echo $SELECTS_TYPE | awk -v x=$i '{print $x}')
        case $type in
            theme)
                name=$(uci get setting.theme.name)
                if [ "x$cloud" == "xmiot" ]; then
                    state=$(cat /usr/share/aqgui/theme/$name/config.json | jshon -Q -e name | tr -d '"')
                else
                    state=$(cat /data/theme/$name/config.json | jshon -Q -e name | tr -d '"')
                fi
                icon=$(echo $SELECTS_ICON | awk -v x=$i '{print $x}')
                [ -n "$state" ] && setup_selects "$type" "$icon" "[\"$state\"]"
            ;;
            font_size)
                state=$(ubus -S call setting get.display | jshon -Q -e fontSize | tr -d '"')
            ;;
            volume_level)
                state=$(ubus -S call setting get.audio | jshon -Q -e volumeLevel | tr -d '"')
            ;;
            home_page)
                state=$(ubus -S call setting get.display | jshon -Q -e homePage | tr -d '"')
            ;;
            standby_screen)
                state=$(ubus -S call setting get.display | jshon -Q -e standby -e screenStyle | tr -d '"')
            ;;
            language)
                state=$(ubus -S call setting get.display | jshon -Q -e language | tr -d '"')
                case $state in
                    zh)
                        state="Simplified_Chinese"
                    ;;
                    en)
                        state="English"
                    ;;
                    zh-TW)
                        state="Traditional_Chinese"
                    ;;
                esac
            ;;
        esac
        [ -n "$state" ] && set_state "select" $type $state
    done
}

set_sensor_state() {
    local topic=; local msg=
    local did=$1
    local res_name=$2
    local value=$3
    local type=

    case $res_name in
        0.12.85)
            type="power"
        ;;
        0.13.85)
            type="energy"
            value=$(awk -v x=$value 'BEGIN {y=1000;print x/y}')
        ;;
        0.14.85)
            type="current"
        ;;
        13.21.85 | 13.22.85 | 13.23.85 | 13.24.85 | 13.25.85 | 13.26.85 | 13.27.85)
            debug wireless switch $res_name $value
        ;;
    esac
    if [ -n "$type" ]; then
        topic="$HASS_PREFIX/sensor/0x00${did}/$type/state"
        msg="{\"$type\": $value}"
        mqtt_pub $topic "$msg"
    fi
}

set_binary_sensor_state() {
    local topic=; local msg=
    local did=$1
    local res_name=$2
    local value=$3
    local type=

}

set_scene_state() {
    local res_name=$1
    local value=$2

    case $res_name in
        8.0.2167)
            config_scenes
        ;;
    esac
}

set_switch_state() {
    local topic=; local msg=; local id=
    local did=$1
    local res_name=$2
    local value=$3

    case $res_name in
        4.*.85)
            id=$(echo $res_name | cut -d "." -f 2)
            [ "x$value" == "x1" ] && msg="ON" || msg="OFF"
        ;;
    esac
    if [ -n "$id" ]; then
        topic="$HASS_PREFIX/switch/0x00${DID}/channel_${id}/state"
        mqtt_pub $topic "$msg"
    fi
}

report_states() {
    params=$1
    name=$(echo $params | jshon -Q -e name | tr -d '"')

    case $name in
        /lumi/res/report/attr)
            value=$(echo $params | jshon -Q -e value)
            did=$(echo $value | jshon -Q -e did | tr -d '"' | tr -d 'lumi1.')
            res_list=$(echo $value | jshon -Q -e res_list)
            num=$(echo $res_list | jshon -l)
            for i in `seq 1 $num`; do
                res_name=$(echo $res_list | jshon -Q -e $((i - 1)) -e "res_name" | tr -d '"')
                value=$(echo $res_list | jshon -Q -e $((i - 1)) -e "value" | tr -d '"')
                debug $did $res_name $value
                set_sensor_state $did $res_name $value
                set_binary_sensor_state $did $res_name $value
                set_scene_state $res_name $value
                set_switch_state $did $res_name $value
            done
        ;;
    esac
}

check_update() {
    local topic=; local msg=; local ret=

    # Update
    ret=$(ubus -S call system software.query | jshon -Q -e status)
    if [ "x$ret" == "x0" ]; then
        topic="$HASS_PREFIX/binary_sensor/0x00${DID}/update/state"
        ret=$(ubus -S call system software | jshon -Q -e newVersion | tr -d '"')
        [ -z "$ret" ] && msg="OFF" || msg="ON"
        mqtt_pub $topic "$msg"
    fi

    # S1E2HA update
    topic="$HASS_PREFIX/binary_sensor/0x00${DID}/s1e2ha_update/state"
    /data/bin/curl -s -k -L -o /tmp/release.json $LATEST_VERSION_URL
    ret=$?
    if [ "x$ret" == "x0" ]; then
        latest_version=$(cat /tmp/release.json | jshon -Q -e models -e $MODEL -e default -e version | tr -d "." | tr -d '"')
        version=$(echo $VERSION | tr -d "." | tr -d '"')
        [ $((latest_version - version)) -gt 0 ] && msg="ON" || msg="OFF"
    else
        msg="unknown"
    fi
    mqtt_pub $topic "$msg"

    [ -f /tmp/release.json ] && rm -f /tmp/release.json
}

check_connectivity() {
    local topic=; local entity=; local line=; local status=0
    local subscribe=0
    local type=$1

    topic="$HASS_PREFIX/binary_sensor/0x00${DID}/connectivity/config"
    line=$($SUB $MQTT_ARGS -t $topic -v --retained-only -W 3)

    [ -n "$line" ] && subscribe=1 || subscribe=0

    if [ "x$subscribe" == "x0" ]; then
        # user remove configs
        #dtime=$(date)
        #echo "$dtime user remove configs" >> /tmp/logerr.txt
        pub_discovery
        set_states
        check_update
    fi

    [ -f /tmp/hass.status ] && status=$(cat /tmp/hass.status) || status="online"
    if [ "x$HASS_STATUS" == "xoffline" ] && [ "x$status" == "xonline" ]; then
        set_states
        HASS_STATUS="online"
    else
        HASS_STATUS="$status"
    fi

    if [ "x$type" == "xordinary" ]; then
        for entity in `cat $ENTITIES_FILE`; do
            prefix_topic="$HASS_PREFIX/$entity"
            topic="$prefix_topic/status"
            msg="online"
            mqtt_pub $topic "$msg"
        done
        status=1
    elif [ "x$type" == "xcloud" ]; then
        check_update
        status=$(ubus -S call aiot status | jshon -Q -e connected)
        [ "x$status" == "x1" ] && status=1 || status=0
    fi

    # periodically update to on, otherwise off after off_delay
    set_connectivity $type $status
}

auto_action() {
    params=$1
    name=$(echo $params | jshon -Q -e name | tr -d '"')

    case $name in
        /lumi/ifttt/sync/check)
            check_connectivity cloud
        ;;
    esac
}

# Collect system information
collect_info() {
    local nproc=; local cpu_load=
    local memory=; local swap=
    local disk_size=; local data_usage= local temperature=
    local uptime=; local ip=; local ssid=;

    #Hostname
    host=$(hostname)

    #Number of processors
    nproc=$(grep -c ^processor /proc/cpuinfo)
    # CPU load
    cpu_load=$(cat /proc/loadavg | awk '{print $1}')
    #Memory usage
    memory=$(free -b | awk 'NR == 2  {print $0}' | awk  -F: '{print $2}' | awk '{printf "%2.1f", 100*$2/$1}' | sed s/,/./g)
    #Swap usage
    swap=0
    #Disk size
    #disk_size=$(df -Ph | awk 'NR>2{sum+=$2}END{print sum}')
    disk_size=$(dmesg | grep nand: | grep MiB | awk '{print $4}')
    if [ -z $disk_size ]; then
        disk_size=128
    fi
    #Disk usage
    data_usage=$(df -Ph | grep /data | awk '{ print $5;}' | sed s/%//g)
    #Uptime (seconds)
    uptime=$(cat /proc/uptime | cut -d ' ' -f 1 | cut -d '.' -f 1)
    #Temperature
    temperature=$(cat /sys/devices/system/cpu/cpufreq/temp_out | cut -d "=" -f 2)
    #temperature=$(awk -v x=$value 'BEGIN {y=10;print x/y}')
    #IP address
    if [ -n "$(which ip)" ]; then
        ip=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
    elif [ -n "$(which ifconfig)" ]; then
        ip=$(ifconfig | sed -nr 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
    else
        ip=unknown
    fi
    # ssid
    ssid=$(agetprop persist.app.wifi_ssid | tr -d '"')
    # wifi strength
    strength=$(cat /proc/net/wireless | grep wlan0 | awk 'END { print $4 }' | sed 's/\.$//')

    SYS_INFO="{\"hostname\": \"$host\", \
\"nproc\": \"$nproc\", \
\"cpu_load\": \"$cpu_load\", \
\"disk_size\": \"$disk_size\", \
\"data_usage\": \"$data_usage\", \
\"memory_usage\": \"$memory\" , \
\"swap\": \"$swap\" , \
\"uptime\": \"$uptime\", \
\"temperature\": \"$temperature\", \
\"s1e2ha_version\": \"$VERSION\", \
\"ipaddress\":\"$ip\", \
\"ssid\":\"$ssid\", \
\"strength\":\"$strength\"
}"
}

do_heartbeat() {
    local topic=;local msg=

    collect_info
    topic="$HASS_PREFIX/sensor/0x00${DID}/state"
    msg=$SYS_INFO
    mqtt_pub $topic "$msg"
}

# Called when SIGINT or EXIT signals are detected to change the status of the sensors in Home Assistant to unavailable
change_status() {
    local topic=;local msg=

    info Signal caught: set status to "offline" and exit

    prefix_topic="$HASS_PREFIX/binary_sensor/0x00${DID}/connectivity"
    topic="$prefix_topic/state"
    msg="OFF"
    mqtt_pub $topic "$msg"

    exit
}

# main
check_mqtt
read_mqtt_config

get_product_info

get_config
get_wconfig

pub_discovery

do_heartbeat
check_ha_driver

set_connectivity ordinary 1
set_connectivity cloud 1

set_status
set_wstatus
set_states

check_update

trap change_status INT TERM KILL
pkill -f ha_driven
sleep 3
while true  # Keep an infinite loop to reconnect when connection lost/broker unavailable
do
    pkill -f ha_driven
    ha_driven -O 1 -L 7 -p /tmp/automatic.pid | awk '/method|sendHeartbeat/{print $7 $8}' | while read -r payload
    do
        debug "Rx ha_driven: ${payload}"
        payload=$(echo $payload | sed -r "s#(.*)}\((.*)\)#\1}#" | sed -r "s/data://" )
        if [ $(echo $payload | jshon -l) -gt 0 ]; then
            if [ -n "$(echo $payload | jshon -Q -e ip)" ] && [ -n "$(echo $payload | jshon -Q -e port)" ]; then
                check_connectivity ordinary
                do_heartbeat
            else
                method=$(echo $payload | jshon -Q -e method | tr -d '"')
                params=$(echo $payload | jshon -Q -e params)
                info "The method is $method"
                case $method in
                    auto.report)
                        report_states "$params"
                    ;;
                    auto.control)
                        debug "The method is auto.control $payload at $(date)"
                        data=$(echo $params | jshon -Q -e value -e data)
                        key=$(echo $data | jshon -Q -k)
                        if [ "x$key" == "x20.4.85" ]; then
                            set_connectivity cloud 1
                        fi
                    ;;
                    auto.ifttt)
                        debug "The method is auto.ifttt $payload at $(date)"
                    ;;
                    auto.action)
                        debug "The method is auto.action $payload at $(date)"
                        auto_action "$params"
                    ;;
                    lanbox.control)
                        check_connectivity ordinary
                        do_heartbeat
                    ;;
                    *)
                        info "The method is unknow $method."
                    ;;
                esac
            fi
        fi
    done
    dtime=$(date)
    echo "$dtime ha_driven exit" >> /tmp/logerr.txt
    sleep $MQTT_SLEEP  # Wait 10 seconds until reconnection
    check_connectivity ordinary
done
