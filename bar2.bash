#!/bin/bash
# $1 argument may hold the output screen ID (see config file for more info)
declare -r kbID="1:1:AT_Translated_Set_2_keyboard"
declare -r power="upower -i /org/freedesktop/UPower/devices/battery_BAT0"
declare -r tempProbe="/sys/devices/virtual/thermal/thermal_zone7/temp"
# the following command may help you choosing the right one
# find /sys/devices/virtual/thermal -name temp -print -exec cat "{}" \;

declare -r separator='"separator_block_width": 20'
declare -A inputBindings
appTitle='""'
echo '{"version": 1, "click_events": true}'

# listen for clicks on swaybar
cat | while read -r click; do
    case $(echo "${click#,}" | jq -r '.name') in
	      input)
            swaymsg input "$kbID" xkb_switch_layout next > /dev/zero
	          ;;
	      net)
	          alacritty --hold --config-file /etc/alacritty/alacritty.toml -e \
	            nmcli device wifi #; nmcli -c yes connection | awk '$NF!="--" {print $0}'
	          ;;
    esac
done &

echo '[' # no closing tag, as output array has an infinite number of sub-arrays
swaymsg -t subscribe -m '["window","tick","input","workspace"]' | while read -r event; do
    case $(echo "$event" | jq -r '.input?.identifier // .current?.type+.change // .first') in
        workspaceempty)
            ;; # dont do anything if deleting empty non-focused workspace
        workspace*)
            wsNum=$(echo "$event" | jq -r --arg outID $1 '.current | select(.output==$outID).num')
            ;&
        close | move)
	    echo "$wsNum" >> /tmp/wsnum.log
            currentWs=$(swaymsg -t get_tree | jq --argjson ws "${wsNum:=0.1}" '.nodes.[].nodes.[] | select(.num==$ws)')
            if [ -n "$currentWs" ] && [ $(echo "$currentWs" | jq '.floating_nodes | length') -eq 0 ]; then
                swaymsg mode "default" > /dev/zero # there is definitely no window from scratchpad
                if [ $(echo "$currentWs" | jq '.nodes | length') -eq 0 ]; then
                    appTitle='""' shortTitle= # delete title on empty workspace, container event won't get fired
                fi
            fi
            ;;
        focus)
            swaymsg mode $(echo "$event" | jq '.container | if select(.visible).scratchpad_state=="fresh" then "scratchpad" else "default" end') > /dev/zero
            appID=$(echo "$event" | jq -r '.container | .app_id // .window_properties?.instance')
            ;&
        title)
            appTitle=$(echo "$event" | jq ".container | select(.focused).name // $appTitle" | awk '{gsub(/[—–|—]/, "-"); print}')
            case "${wsNum:+$appID}" in
                "")
                    appTitle='""' shortTitle= # no title on inactive workspace
                    ;;
                jetbrains-phpstorm)
                    appTitle=$(echo "$appTitle" | sed -E 's/"(.+\[)?([a-zA-Z0-9/\. ~]+)(\].+)?"/"\2 - PhpStorm"/')
                    ;&
                vscodium | Alacritty)
                    inputBindings[$appID]=0 #always set english layout
                    ;;&
                org.telegram.desktop)
                    inputBindings[$appID]=1 #always set slovak layout
                    ;;&
                *)
                    if [[ -v inputBindings[$appID] ]]; then  #set keyboard layout if stored for current pid
                        swaymsg input "$kbID" xkb_switch_layout "${inputBindings[$appID]}" > /dev/zero
                    fi
                    shortTitle=$(echo "$appTitle" | awk -F "-" '{gsub(/"/, ""); print $NF}')
#                    echo "$event" | jq '.container' >> /tmp/swaylog.js
                    ;;
            esac
            ;;
        true)
            # retrieve keyboard layout on startup - first tick
            event=$(swaymsg -rt get_inputs | jq --arg id "$kbID" '{"input": (.[] | select(.identifier==$id))}')
            wsNum=0 appID=0
            ;&
        $kbID)
            inputBindings[$appID]=$(echo "$event" | jq -r '.input.xkb_active_layout_index')
            input=$(echo "$event" | jq -r '.input.xkb_active_layout_name[0:2]')
            ;;
    esac
    
    mem=$(free --mega | awk 'NR==2 && $7<1000 {print $7}')
    temp=$(awk -v tempt=${tempt:=70} '$1>tempt*1000 {print int($1/1000)}' $tempProbe)
    tempt=${temp:+50}
    net=$(nmcli -t connection | awk -F':' '$4 {print $3}' | sed 's/vpn//; s/802-11-wireless//; t; d' | xargs)
    bat=$($power | awk '/percentage/ { $r=substr($2,1,length($2)-1); if(int($r)<80) print $r; }')
    if [ -z "$bat" ] || [ "$bat" -ge 40 ] || (( $($power | awk '/state/ {print $2=="charging"}') )); then
	bat_lvl="#FFFFFF";
    elif [ $bat -ge 20 ] && (( $($power | awk '/state/ {print $2!="charging"}') )); then
        bat_lvl="#FF0000"
    else 
        echo "Would like to hibernate at $(date +'%H:%M')" >> /tmp/swaylog.js
    fi
    cat << EOUpdate
[{
    "name": "temp", $separator,
    "full_text": "${temp:+🌡$temp℃}",
    "color": "#CB6A6A"
},{
    "name": "memory", $separator,
    "full_text": "${mem:+$mem MB}",
    "color": "#CB6A6A"
},{
    "name": "window", $separator,
    "full_text": $appTitle,
    "short_text": "$shortTitle"
},{
    "name": "input", $separator,
    "full_text": "<span foreground=\"#CB6A6A\" text-transform=\"uppercase\">$input</span>",
    "markup": "pango"
},{
    "name": "battery", $separator,
    "full_text": "${bat:+$bat%}",
    "color": "$bat_lvl"
},{
    "name": "time", $separator,
    "full_text": "$(date +'%A %H:%M %B %d')",
},{
      "name": "net", $separator,
      "full_text": "$net",
  }],
EOUpdate
#https://fontawesome.com/v4/cheatsheet/
done
