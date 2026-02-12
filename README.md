# Memgraph SIGSEGV on Corrupted RocksDB MANIFEST

Minimal reproduction for Memgraph crashing with SIGSEGV (exit code 139) when RocksDB MANIFEST files are corrupted.

## Quick Start

```bash
./reproduce.sh
```

Expected output:
```
✓ BUG REPRODUCED: Container crashed with SIGSEGV (exit code 139)
```

## Environment

- Memgraph: 3.7.2
- Storage mode: `ON_DISK_TRANSACTIONAL`
- OS: Linux

## Root Cause

Truncated/corrupted MANIFEST files in `rocksdb_durability/` cause RocksDB initialization to fail. The exception is not caught properly, resulting in SIGSEGV instead of graceful termination.

```
RocksDB couldn't be initialized inside /var/lib/memgraph/rocksdb_durability
-- Corruption: no log_file_number, next_file_number, last_sequence entry
in MANIFEST in file /var/lib/memgraph/rocksdb_durability/MANIFEST-000005
```

## Real-World Trigger

Container hard-crash (OOM kill, SIGKILL, power loss) during RocksDB write can create truncated MANIFEST files. On restart, Memgraph crashes permanently until manual intervention.

## Security Analysis

**Classification: Denial-of-Service (not exploitable for RCE)**

### Methodology

Tested 7 different MANIFEST payloads to determine if crash behavior varies:

| Payload | Size | Content | Exit Code | Behavior |
|---------|------|---------|-----------|----------|
| baseline_null | 5 | `\x00` × 5 | 139 | Same crash |
| ascii_short | 5 | `AAAAA` | 139 | Same crash |
| ascii_long | 100 | `A` × 100 | 139 | Same crash |
| pointer_pattern | 8 | `\x41` × 6 + `\x00` × 2 | 139 | Same crash |
| random_garbage | 16 | random bytes | 139 | Same crash |
| format_string | 12 | `%x%x%x%x%x%x` | 139 | Same crash |
| nul_terminated | 11 | `ABC\0DEF\0GHI` | 139 | Same crash |

### Findings

All payloads produce identical crash behavior:
- Same exit code (139 / SIGSEGV)
- Same error message
- Same crash location

The crash occurs during **validation**, before attacker-controlled bytes are interpreted as data structures. No buffer is allocated from file content, no pointers are dereferenced.

### CVSS Assessment

- **Score**: 5.3 (Medium)
- **Vector**: `AV:L/AC:L/PR:L/UI:N/S:U/C:N/I:N/A:H`
- **Impact**: Availability only (permanent DoS until manual cleanup)
- **Exploitability**: None beyond DoS

## Suggested Fix

The crash stems from exception handling during RocksDB initialization. Suggested approach:

```cpp
// Current behavior (pseudocode):
void initRocksDB() {
    auto db = rocksdb::DB::Open(options, path);  // throws on corruption
    // Exception propagates, hits partially-constructed object, SIGSEGV
}

// Suggested fix:
void initRocksDB() {
    rocksdb::Status status = rocksdb::DB::Open(options, path, &db);
    if (!status.ok()) {
        if (status.IsCorruption()) {
            LOG_ERROR("RocksDB corruption detected: {}", status.ToString());
            LOG_ERROR("Manual recovery required. See documentation.");
            exit(1);  // Clean exit, not SIGSEGV
        }
        throw std::runtime_error(status.ToString());
    }
}
```

Key points:
1. Use status-returning API instead of exception-throwing
2. Detect corruption explicitly
3. Exit cleanly with actionable error message
4. Consider adding `--storage-recover-on-corruption` flag for automatic recovery attempts

## Workaround

Pre-flight check script to detect corrupted MANIFEST files before starting Memgraph:

```bash
#!/bin/bash
MIN_SIZE=50
for f in /var/lib/memgraph/rocksdb_*/MANIFEST-*; do
    [ -f "$f" ] || continue
    size=$(stat -c%s "$f")
    if [ "$size" -lt "$MIN_SIZE" ]; then
        echo "ERROR: Corrupted MANIFEST: $f ($size bytes)"
        exit 1
    fi
done
```

## Related

- Upstream issue: https://github.com/memgraph/memgraph/issues/3785
