#!/bin/bash
set -e

echo "=== Minimal Memgraph WAL Recovery Bug Reproduction ==="
echo "Steps: Start → Stop → Corrupt rocksdb_durability MANIFEST → Restart"
echo ""

# Clean up
docker compose down -v 2>/dev/null || true

# Start and stop Memgraph (no test data needed)
docker compose up -d
sleep 1
docker compose stop

# Corrupt only the rocksdb_durability MANIFEST file
docker run --rm -v memgraph-wal-bug_mg_data:/data alpine sh -c '
    for f in /data/rocksdb_durability/MANIFEST-*; do 
        head -c 5 "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done
'

# Restart and check for crash
docker compose up -d
sleep 3

echo ""
if docker compose ps -a | grep -q "Exited (139)"; then
    echo "✓ BUG REPRODUCED: Container crashed with SIGSEGV (exit code 139)"
    exit 0
else
    echo "✗ Bug NOT reproduced. Container status:"
    docker compose ps -a
    exit 1
fi
