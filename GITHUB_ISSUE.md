# GitHub Issue Draft

**Target:** Comment on https://github.com/memgraph/memgraph/issues/3785

---

## Body

Security analysis + fix suggestion for this issue.

**Repro:** https://github.com/oriongonza/memgraph-wal-bug

### Security Assessment

Tested 7 payloads (nulls, ASCII, pointers, format strings, random). All crash identically - same location, same error. Crash happens during validation before data interpretation.

**Verdict:** DoS only, not exploitable for RCE. CVSS 5.3 (Medium).

### Root Cause

Exception during RocksDB init → virtual method called on partially-constructed object → SIGSEGV.

### Fix

Use status API instead of exceptions:

```cpp
rocksdb::Status s = rocksdb::DB::Open(opts, path, &db);
if (s.IsCorruption()) {
    LOG_ERROR("Corruption in {}: {}", path, s.ToString());
    exit(1);  // clean exit, not SIGSEGV
}
```

### Workaround

```bash
for f in /var/lib/memgraph/rocksdb_*/MANIFEST-*; do
    [ -f "$f" ] && [ $(stat -c%s "$f") -lt 50 ] && exit 1
done
```
