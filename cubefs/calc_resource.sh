#!/bin/bash
#
# Blobstore Resource Calculation Script
# 根据容量和 QPS 需求计算 Blobstore 集群所需的服务器台数
#

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: resource.sh [options]

Required:
  --pb <PB>                  Required capacity in PB (default: 1)
  --qps <QPS>                Required QPS (default: 1000)
  --io <KiB>                 Client IO size in KiB (default: 1024, 1MiB)
  --rw <r:w>                 Read:Write ratio (default: 1:9)
  --dc <TB>                  Capacity per disk in TB (default: 16)
  --dn <N>                   Disks per server node (default: 32)
  --ec <K+M>                 EC scheme, e.g. 12+9 (default: 8+3)
  -h, --help                 Show this help

Environment Variables:
  IOPS_PER_DISK              IOPS per disk (default: 100)
  IOPS_COEFFICIENT           IOPS coefficient / IO block size (default: 512, 512K)
  BLOBNODE_IO_ALIGN          Blobnode IO align in bytes (default: 4096)
  DATASET_SIZE               Devices per dataset (default: 60)
  MIN_READ_SHARD_X           Extra read shard multiplier (default: 1)

Example:
  resource.sh --pb 10 --dc 16 --dn 36 --ec 12+9
EOF
    exit 0
}

# ========== Ceiling Functions ==========
# ceil_div a b = (a + b - 1) / b (整数向上取整除法)
ceil_div() {
    echo $(( ($1 + $2 - 1) / $2 ))
}

# bc_ceil expr — 对 bc 浮点表达式结果向上取整
bc_ceil() {
    bc -l <<EOF
define ceil(x) { auto k,s; s=scale; scale=0; k=x/1; if(k<x) k+=1; scale=s; return k; }
ceil($1)
EOF
}

# bc_floor expr — 对 bc 浮点表达式结果向下取整（截断小数）
bc_floor() {
    echo "$1" | bc -l | cut -d. -f1
}

# ========== Defaults ==========
IOPS_PER_DISK=${IOPS_PER_DISK:-100}
IOPS_COEFFICIENT=${IOPS_COEFFICIENT:-512}
BLOBNODE_IO_ALIGN=${BLOBNODE_IO_ALIGN:-4096}
DATASET_SIZE=${DATASET_SIZE:-60}
MIN_READ_SHARD_X=${MIN_READ_SHARD_X:-1}
CLUSTER_THRESHOLD=${CLUSTER_THRESHOLD:-0.85}

CLIENT_PB=1
CLIENT_QPS=1000
CLIENT_IO_SIZE=1024
CLIENT_WRITE=9
CLIENT_READ=1
CAPA_PER_DISK=16
DISKS_PER_NODE=32
EC_K=8
EC_M=3

# ========== Parse CLI ==========
if ! ARGS=$(getopt -o h --long help,pb:,qps:,io:,rw:,dc:,dn:,ec: -n "$0" -- "$@"); then
    usage
fi
eval set -- "$ARGS"

while true; do
    case "$1" in
        --pb) CLIENT_PB="$2"; shift 2 ;;
        --qps) CLIENT_QPS="$2"; shift 2 ;;
        --io) CLIENT_IO_SIZE="$2"; shift 2 ;;
        --rw)
            RW_RAW="$2"
            CLIENT_READ="${RW_RAW%%:*}"
            CLIENT_WRITE="${RW_RAW##*:}"
            shift 2 ;;
        --dc) CAPA_PER_DISK="$2"; shift 2 ;;
        --dn) DISKS_PER_NODE="$2"; shift 2 ;;
        --ec)
            EC_RAW="$2"
            EC_K="${EC_RAW%%+*}"
            EC_M="${EC_RAW##*+}"
            shift 2 ;;
        -h|--help) usage ;;
        --) shift; break ;;
        *) usage ;;
    esac
done

# ========== Calculations ==========
EC_TOTAL=$((EC_K + EC_M))

# EC_Shard_Size = CLIENT_IO_Size * 1024 / (K + M), 向上取整到 BLOBNODE_IO_ALIGN 的整数倍
EC_SHARD_SIZE=$(( (CLIENT_IO_SIZE * 1024) / EC_K ))
EC_SHARD_SIZE=$(( $(ceil_div "$EC_SHARD_SIZE" "$BLOBNODE_IO_ALIGN") * BLOBNODE_IO_ALIGN ))

# Disk_Per_PiB = ceil(1024 * (EC_K + EC_M) / (Capa_Per_Disk * 0.909 * 0.85 * EC_K))
DISK_PER_PIB=$(bc_ceil "1024 * $EC_TOTAL / ($CAPA_PER_DISK * 0.909 * $CLUSTER_THRESHOLD * $EC_K)")

# TPS_Per_PiB = Disk_Per_PiB * (IOPS_Per_Disk / (EC_Shard_Size / (IOPS_COEFFICIENT * 1024) + 1)) / (EC_K + EC_M)
TPS_PER_PIB=$(bc_floor "$DISK_PER_PIB * ($IOPS_PER_DISK / ($EC_SHARD_SIZE / ($IOPS_COEFFICIENT * 1024) + 1)) / $EC_TOTAL")

# Gibps_Per_PiB = TPS_Per_PiB * Demand_IO_Size * 8 / 1024^3
GBPS_PER_PIB=$(echo "scale=2; $TPS_PER_PIB * $CLIENT_IO_SIZE * 1024 * 8 / (1024 ^ 3)" | bc -l)

# Num_Of_Servers = Demand_PB * Disk_Per_PiB / Disks_Per_Node
NUM_SERVERS_CAP=$(ceil_div $(( CLIENT_PB * DISK_PER_PIB )) "$DISKS_PER_NODE")
[[ $NUM_SERVERS_CAP -lt $EC_TOTAL ]] && NUM_SERVERS_CAP=$EC_TOTAL

# === By QPS ===
RATIO_SUM_QPS=$((CLIENT_READ + CLIENT_WRITE))
DEMAND_QPS_WRITE=$(echo "scale=2; $CLIENT_QPS * $CLIENT_WRITE / $RATIO_SUM_QPS" | bc -l)
DEMAND_QPS_READ=$(echo "scale=2; $CLIENT_QPS * $CLIENT_READ / $RATIO_SUM_QPS" | bc -l)

# Demand_IOPS_Per_Disk = Demand_QPS_Write * (K+M) / Disk_Per_PiB + Demand_QPS_Read * K / Disk_Per_PiB
DEMAND_IOPS_PER_DISK=$(echo "scale=2; $DEMAND_QPS_WRITE * $EC_TOTAL / $DISK_PER_PIB + $DEMAND_QPS_READ * ($EC_K + $MIN_READ_SHARD_X) / $DISK_PER_PIB" | bc -l)

# Demand_IOPS_Magnification_Factor = Demand_IOPS_Per_Disk / IOPS_Per_Disk
DEMAND_IOPS_MAG=$(echo "scale=2; $DEMAND_IOPS_PER_DISK / $IOPS_PER_DISK" | bc -l)

# Num_Of_Servers = Demand_IOPS_Mag * Disk_Per_PiB * Demand_PB / Disks_Per_Node
NUM_SERVERS_QPS=$(bc_ceil "$DEMAND_IOPS_MAG * $DISK_PER_PIB * $CLIENT_PB / $DISKS_PER_NODE")
[[ $NUM_SERVERS_QPS -lt $EC_TOTAL ]] && NUM_SERVERS_QPS=$EC_TOTAL

# === Final ===
if [ "$NUM_SERVERS_CAP" -gt "$NUM_SERVERS_QPS" ]; then
    FINAL_SERVERS=$NUM_SERVERS_CAP
    FINAL_BY="capacity"
else
    FINAL_SERVERS=$NUM_SERVERS_QPS
    FINAL_BY="QPS"
fi
FINAL_DATASETS=$(ceil_div "$FINAL_SERVERS" "$DATASET_SIZE")
FINAL_SERVERS_ROUNDED=$((FINAL_DATASETS * DATASET_SIZE))

# ========== Output ==========
echo ""
echo "========== Blobstore Resource Calculation =========="
echo ""
echo "Input:"
echo "  EC K/M:                     ${EC_K}+${EC_M}"
echo "  Demand Capacity:            ${CLIENT_PB} PB"
echo "  Demand QPS:                 ${CLIENT_QPS}"
echo "  IO Size:                    ${CLIENT_IO_SIZE} KiB ($(( CLIENT_IO_SIZE / 1024 )) MiB)"
echo "  Read/Write Ratio:           ${CLIENT_READ}:${CLIENT_WRITE}"
echo "  Capacity per Disk:          ${CAPA_PER_DISK} TB"
echo "  Disks per Node:             ${DISKS_PER_NODE}"
echo "  IOPS per Disk:              ${IOPS_PER_DISK}"
echo "  IOPS Coefficient:           ${IOPS_COEFFICIENT} KiB ($(( IOPS_COEFFICIENT / 1024 )) MiB)"
echo "  Blobnode IO Align:          ${BLOBNODE_IO_ALIGN} bytes"
echo "  Dataset Size:               ${DATASET_SIZE} devices"
echo "  EC Shard Size:              $(( EC_SHARD_SIZE / 1024 )) KiB"
echo ""
echo "Intermediate:"
echo "  Disks per PiB:              ${DISK_PER_PIB}"
echo "  TPS per PiB:                ${TPS_PER_PIB}"
echo "  Bandwidth per PiB:          ${GBPS_PER_PIB} Gbps"
echo "  Demand QPS Write:           ${DEMAND_QPS_WRITE}"
echo "  Demand QPS Read:            ${DEMAND_QPS_READ}"
echo "  Demand IOPS per Disk:       ${DEMAND_IOPS_PER_DISK}"
echo "  IOPS Magnification Factor:  ${DEMAND_IOPS_MAG}"
echo ""
echo "Result - By Capacity:"
echo "  Servers:                    ${NUM_SERVERS_CAP}"
echo ""
echo "Result - By QPS:"
echo "  Servers:                    ${NUM_SERVERS_QPS}"
echo ""
echo "Final Recommendation:"
echo "  Servers (raw):              ${FINAL_SERVERS} (driven by ${FINAL_BY})"
echo "  Servers (dataset rounded):  ${FINAL_SERVERS_ROUNDED} (${FINAL_DATASETS} datasets)"
echo ""
