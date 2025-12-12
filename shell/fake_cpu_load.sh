#!/bin/bash

# /etc/systemd/system/fake_cpu_load.service
# systemctl daemon-reload
# systemctl enable --now fake_cpu_load.service

DURATION=60
INTERVAL=3600
CORES=2

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

while true; do
    log "Start simulating CPU load for ${DURATION} seconds, using ${CORES} cores..."

    pids=()
    for ((i=0; i<CORES; i++)); do
        timeout "$DURATION" sh -c 'while :; do :; done' &
        pids+=($!)
    done

    wait "${pids[@]}" 2>/dev/null

    log "CPU load simulation complete, hibernating for ${INTERVAL} seconds..."
    sleep "$INTERVAL"
done
