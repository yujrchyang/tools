#!/bin/bash

# Default loop count
TOTAL_LOOPS=10

for ((i=1; i<=TOTAL_LOOPS; i++)); do
    # 1. Get current real-time timestamp (Format: YYYYMMDDHHMM)
    CURRENT_TIME=$(date "+%Y%m%d%H%M")

    # 2. Dynamically generate execution ID based on the loop index (e.g., r1, r2, ... r10)
    RUN_ID="r${i}"

    echo "========================================"
    echo "Starting test iteration ${i}/${TOTAL_LOOPS}..."
    echo "Timestamp: ${CURRENT_TIME} | Run ID: ${RUN_ID}"
    echo "========================================"

    # 3. Execute the core benchmark command
    /usr/bin/bench \
        -b blobnode \
        -c /root/blobstore/bench.json \
        -r /root/blobstore/db \
        -e -1 \
        -m pgd \
        -pr "bn-db-cast-8K-${RUN_ID}" \
        -s 8K \
        -t 18 \
        -d -1 \
        -n 587199960 \
        > "${CURRENT_TIME}-bn-db-cast-8K-${RUN_ID}.log" 2>&1

    echo "Iteration ${i} benchmark process has finished."
    echo "Log saved to: ${CURRENT_TIME}-bn-db-cast-8K-${RUN_ID}.log"
    echo ""

    # If the benchmark finishes instantly, uncomment the line below
    # to prevent timestamp collision within the same minute:
    # sleep 60
done

echo "All ${TOTAL_LOOPS} test iterations have been successfully completed!"
