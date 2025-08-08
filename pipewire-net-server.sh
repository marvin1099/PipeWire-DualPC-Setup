#!/usr/bin/env bash
# ==============================
# PipeWire Network Audio Server
# ==============================

## ===== User Config =====
# IP address of the other PC (Gaming PC in your setup)
REMOTE_IP="192.168.2.111"

# TCP port for PipeWire/PulseAudio connection
PORT="33478"

# Default sink (empty string "" to skip setting)
DEFAULT_SINK="media"

# Default source (empty string "" to skip setting)
DEFAULT_SOURCE="micmirror"

# Mount command (can be swapped out or left empty)
MOUNT_CMD="mount -a"

# Command(s) to disconnect all existing PipeWire links (leave empty to skip)
DISCONNECT_CMD="" # pw-cli ls | awk '/ PipeWire:Interface:Link/ {print substr($2,1,length($2)-1)}' | xargs -d\\n -n1 pw-cli d "" 2>/dev/null

# pw-link disconnect commands to run before loading your graph
# (put each as a separate line EOF section)
DISCONNECT_LINKS=$(
  cat <<'EOF'
pw-link -d PipeWire:output_AUX0 media:playback_FL
pw-link -d PipeWire:output_AUX1 media:playback_FR
EOF
)

# Folder containing your PipeWire configs / qpwgraph files
CONFIG_FOLDER="$HOME/Documents/Coding/Bash/Garuda/Configs"

# qpwgraph project file
QPWGRAPH_FILE="def.qpwgraph"

# Path to pipewire-script.py (leave empty to disable)
PIPEWIRE_SCRIPT="$(dirname "$0")/pipewire-script.py"

## ===== Script Logic =====
conrec=0

PipeWire() {
    # Wait for PipeWire to become active
    until systemctl --user is-active --quiet pipewire; do
        sleep 1
    done
    sleep 5

    aw=1
    while true; do
        # Wait for remote PC to respond
        while [[ $aw == 1 ]]; do
            ping -W 1 -c 1 "$REMOTE_IP" > /dev/null
            aw=$?
            sleep 5
        done

        # Once remote PC is reachable
        while [[ $aw == 0 ]]; do
            ping -W 1 -c 1 "$REMOTE_IP" > /dev/null
            aw=$?
            sleep 1

            if [[ $(pactl list modules | awk '/module-native-protocol-tcp/ {print $2}' | wc -l) -eq 0 ]]; then
                notify-send -a "Audio" -i audio -t 10000 "Re/starting PulseAudio server"
                pactl load-module module-native-protocol-tcp latency=1028 port="$PORT" \
                    sink_properties="device.intended-roles=none" \
                    source_properties="device.intended-roles=none"
                sleep 1
                [[ -n "$DEFAULT_SINK" ]] && pactl set-default-sink "$DEFAULT_SINK"
                [[ -n "$DEFAULT_SOURCE" ]] && pactl set-default-source "$DEFAULT_SOURCE"
                SetupWires &
            fi

            Receivers
            sleep 4
        done
    done
}

Receivers() {
    rec=$(pw-cli ls | awk '/Node\/3/ || /node.name/ && /PipeWire/ {if($1=="id"){a = substr($2,1,length($2)-1)}else{print a}}' | wc -l) #'

    if (( conrec < 2 )); then
        conrec=$((conrec+1))
    fi

    if (( rec < 2 )); then
        conrec=0
    elif (( conrec == 1 )); then
        notify-send -a "Audio" -i audio -t 10000 "Connection established, reconnecting cables"
        sleep 1
        [[ -n "$DEFAULT_SINK" ]] && pactl set-default-sink "$DEFAULT_SINK"
        [[ -n "$DEFAULT_SOURCE" ]] && pactl set-default-source "$DEFAULT_SOURCE"
        [[ -n "$MOUNT_CMD" ]] && $MOUNT_CMD
        SetupWires &
    fi
}

SetupWires() {
    sleep 15

    # Disconnect existing links if command is set
    if [[ -n "$DISCONNECT_CMD" ]]; then
        eval "$DISCONNECT_CMD"
    fi

    # Run per-link disconnect commands
    if [[ -n "$DISCONNECT_LINKS" ]]; then
        while IFS= read -r cmd; do
            eval "$cmd"
        done <<< "$DISCONNECT_LINKS"
    fi

    cd "$CONFIG_FOLDER" || return

    if ! pgrep -x qpwgraph > /dev/null; then
        qpwgraph -a -m "$QPWGRAPH_FILE" &
    fi

    if [[ -n "$PIPEWIRE_SCRIPT" && -f "$PIPEWIRE_SCRIPT" ]]; then
        python "$PIPEWIRE_SCRIPT" -l
    fi
}

PipeWire
