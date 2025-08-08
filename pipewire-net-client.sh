#!/usr/bin/env bash

## ===== User Config =====
# IP address of the other PC (the one running the server script)
REMOTE_IP="192.168.2.112"

# TCP port for PulseAudio tunnel connection
PORT="33478"

# Channels to use for tunnel modules (usually 2, 6, or 8)
CHANNELS="6"

# Source and sink names for the tunnel modules
TUNNEL_SOURCE_NAME="frgarstr"
TUNNEL_SINK_NAME="togarstr"

# Default sink (empty string "" to skip setting)
DEFAULT_SINK="media"

# Default source (empty string "" to skip setting)
DEFAULT_SOURCE="micmirror"

# Command(s) to disconnect all existing PipeWire links (leave empty to skip)
DISCONNECT_CMD="" # pw-cli ls | awk '/ PipeWire:Interface:Link/ {print substr($2,1,length($2)-1)}' | xargs -d\\n -n1 pw-cli d "" 2>/dev/null

## pw-link disconnect commands to run before loading your graph
## (put each as a separate line EOF section)
# DISCONNECT_LINKS=$(
# cat <<'EOF'
# pw-link -d PipeWire:output_AUX0 media:playback_FL
# pw-link -d PipeWire:output_AUX1 media:playback_FR
# EOF
# )

# Folder containing your PipeWire configs / qpwgraph files
CONFIG_FOLDER="$HOME/Documents/Coding/Bash/Garuda/Configs"

# Path to your PipeWire graph configuration file
QPWGRAPH_FILE="def.qpwgraph"

# Python script for additional PipeWire setup
PIPEWIRE_SCRIPT="$(dirname "$0")/pipewire-script.py"

## ===== Script =====

PipeWire() {
    # Wait for PipeWire to become active
    while [[ $(systemctl --user status pipewire | awk '/Active: active/' | wc -l) -lt 1 ]]; do
        sleep 1
    done

    InstantWires &
    sleep 5
    conrec=0

    while true; do
        # Wait for remote PC to become reachable
        while ! ping -W 1 -c 1 "$REMOTE_IP" &>/dev/null; do
            sleep 5
        done

        notify-send -a "Audio" -i audio -t 10000 \
            "Trying to connect to pulse server as source and sink"

        # While the remote PC is online
        while ping -W 1 -c 1 "$REMOTE_IP" &>/dev/null; do
            rec=$(pactl list modules | awk '/module-tunnel-source/ || /module-tunnel-sink/ {print $2}' | wc -l)

            if [[ $conrec -lt 2 ]]; then
                conrec=$((conrec+1))
            fi
            if [[ $rec -lt 2 ]]; then
                conrec=0
            fi

            # Load tunnel source if not loaded
            if [[ $(pactl list modules | awk '/module-tunnel-source/ {print $2}' | wc -l) == 0 ]]; then
                pactl load-module module-tunnel-source \
                    channels="$CHANNELS" \
                    source_name="$TUNNEL_SOURCE_NAME" \
                    server="tcp:${REMOTE_IP}:${PORT}"
                sleep 1
            fi

            # Load tunnel sink if not loaded
            if [[ $(pactl list modules | awk '/module-tunnel-sink/ {print $2}' | wc -l) == 0 ]]; then
                pactl load-module module-tunnel-sink \
                    channels="$CHANNELS" \
                    sink_name="$TUNNEL_SINK_NAME" \
                    server="tcp:${REMOTE_IP}:${PORT}"
                sleep 1
            fi

            # If we just connected, configure defaults and wiring
            if [[ $conrec == 1 ]]; then
                notify-send -a "Audio" -i audio -t 10000 \
                    "Connected to pulse server as source and sink"
                pactl set-default-sink "$DEFAULT_SINK"
                pactl set-default-source "$DEFAULT_SOURCE"
                mount -a
                SetupWires &
            fi

            sleep 4
        done
        sleep 1
    done
}

InstantWires() {
    # Optionally disconnect all existing PipeWire links:
    # pw-cli ls | awk '/ PipeWire:Interface:Link/ {print substr($2,1,length($2)-1)}' | \
    #     xargs -d\\n -n1 pw-cli d "" 2>/dev/null

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

    # Start qpwgraph with preset if not running
    if ! pgrep -x qpwgraph >/dev/null; then
        qpwgraph -a -m "$QPWGRAPH_FILE" &
    fi

    # Run additional Python-based PipeWire setup
    python "$PIPEWIRE_SCRIPT" -l
}

SetupWires() {
    sleep 15
    InstantWires
}

PipeWire
