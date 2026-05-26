#!/bin/bash

# ================= CONFIGURATION =================
NAMESPACE="blobstore"
POD_PREFIX="blobstore-blobnode"

# Path to the log file
OUTPUT_FILE=${OUTPUT_FILE:-"./monitor.log"}
# Interval in seconds
INTERVAL=${INTERVAL:-60}
# =================================================

echo "Starting memory monitor for Pod Prefix: $POD_PREFIX (Namespace: $NAMESPACE)"
echo "Data will be saved to: $OUTPUT_FILE"
echo "------------------------------------------------"

# Start loop
while true; do
    # Get current timestamp (YYYY-MM-DD HH:MM:SS)
    CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

    BLOBNODE_CPU="0.0"
    BLOBNODE_MEMORY_KB="0"
    BLOBNODE_VMSIZE_KB="0"
    CGROUP_USAGE_KB="0"
    CGROUP_MAX_USAGE_KB="0"
    POD_MEMORY_KB="0"
    EXT4_SLAB_KB="0"
    META_DISKS_DATA=""

    POD_ID=$(sudo crictl pods --namespace "$NAMESPACE" --name "$POD_PREFIX" -q 2>/dev/null | head -n 1)
    CONTAINER_ID=""
    if [ -n "$POD_ID" ]; then
        CONTAINER_ID=$(sudo crictl ps --pod "$POD_ID" --state Running -q 2>/dev/null | head -n 1)
    fi

    if [ -n "$CONTAINER_ID" ]; then
        # Blobnode
        ENTRYPOINT_PID=$(sudo crictl inspect --output json "$CONTAINER_ID" 2>/dev/null | jq -r '.info.pid' 2>/dev/null)
        if [[ "$ENTRYPOINT_PID" =~ ^[0-9]+$ ]]; then
            BLOBNODE_PID=$(sudo pgrep -P "$ENTRYPOINT_PID" 2>/dev/null)
            if [[ "$BLOBNODE_PID" =~ ^[0-9]+$ ]]; then
                # CPU
                RAW_CPU=$(sudo ps -p "$BLOBNODE_PID" -o %cpu= 2>/dev/null | tr -d ' ')
                if [ -n "$RAW_CPU" ]; then
                    BLOBNODE_CPU="$RAW_CPU"
                fi
                # Memory
                MEM_STATS=$(sudo cat "/proc/$BLOBNODE_PID/status" 2>/dev/null | awk '/VmRSS/{rss=$2} /VmSize/{size=$2} END{print rss","size}')
                RAW_RSS=$(echo "$MEM_STATS" | cut -d',' -f1)
                RAW_SIZE=$(echo "$MEM_STATS" | cut -d',' -f2)
                if [[ "$RAW_RSS" =~ ^[0-9]+$ ]]; then
                    BLOBNODE_MEMORY_KB="$RAW_RSS"
                fi
                if [[ "$RAW_SIZE" =~ ^[0-9]+$ ]]; then
                    BLOBNODE_VMSIZE_KB="$RAW_SIZE"
                fi
            fi
        fi

        # CGROUP
        CGROUP_DIR=$(sudo find /sys/fs/cgroup/memory/ -name "*${CONTAINER_ID}*" -type d 2>/dev/null | head -n 1)
        if [ -n "$CGROUP_DIR" ]; then
            RAW_CG_USAGE=$(sudo cat "${CGROUP_DIR}/memory.usage_in_bytes" 2>/dev/null)
            RAW_CG_MAX=$(sudo cat "${CGROUP_DIR}/memory.max_usage_in_bytes" 2>/dev/null)

            # Change to KB
            if [[ "$RAW_CG_USAGE" =~ ^[0-9]+$ ]]; then
                CGROUP_USAGE_KB=$((RAW_CG_USAGE / 1024))
            fi
            if [[ "$RAW_CG_MAX" =~ ^[0-9]+$ ]]; then
                CGROUP_MAX_USAGE_KB=$((RAW_CG_MAX / 1024))
            fi
        fi

        # Pod
        POD_MEMORY_RAW=$(sudo crictl stats --id "$CONTAINER_ID" -o json 2>/dev/null | jq -r '.stats[0].memory.workingSetBytes.value' 2>/dev/null)
        if [[ "$POD_MEMORY_RAW" =~ ^[0-9]+$ ]]; then
            POD_MEMORY_KB=$((POD_MEMORY_RAW / 1024))
        fi

        # Mountpoint
        META_DISKS_DATA=$(sudo crictl exec "$CONTAINER_ID" df -k 2>/dev/null | awk '
            /\/var\/lib\/blobstore\/blobnode\/meta/ {
                target_path = $NF;
                match(target_path, /disk[0-9]+$/);
                disk_name = substr(target_path, RSTART, RLENGTH);
                if (disk_name != "") {
                    used_kb = $(NF-3);
                    if (used_kb ~ /^[0-9]+$/) {
                        res[disk_name] = used_kb
                    }
                }
            }
            END {
                n = asorti(res, dest);
                for (i = 1; i <= n; i++) {
                    printf "%s: %s ", dest[i], res[dest[i]]
                }
            }
        ' | sed 's/ $//')
    fi

    # Ext4
    EXT4_SLAB_RAW=$(sudo slabtop -o -s c 2>/dev/null | awk '/ext4_/{gsub(/K/,"",$(NF-1)); sum+=$(NF-1)} END{print sum?sum:0}')
    if [[ "$EXT4_SLAB_RAW" =~ ^[0-9]+$ ]]; then
        EXT4_SLAB_KB="$EXT4_SLAB_RAW"
    fi

    if [ -z "$META_DISKS_DATA" ]; then
        META_DISKS_DATA="disk_err:0"
    fi

    echo "[$CURRENT_TIME] " \
        "BLOBNODE_CPU%: ${BLOBNODE_CPU} " \
        "POD: ${POD_MEMORY_KB} " \
        "BLOBNODE_VmRSS: ${BLOBNODE_MEMORY_KB} " \
        "BLOBNODE_VmSize: ${BLOBNODE_VMSIZE_KB} " \
        "CG_Usage: ${CGROUP_USAGE_KB} " \
        "CG_MaxUsage: ${CGROUP_MAX_USAGE_KB} " \
        "SYS_Ext4_Slab: ${EXT4_SLAB_KB} " \
        "${META_DISKS_DATA}"
    sleep "$INTERVAL"
done
