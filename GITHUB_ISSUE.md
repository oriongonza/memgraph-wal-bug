# GitHub Issue Draft

**Target:** Comment on https://github.com/memgraph/memgraph/issues/3785

---

## Body

Security analysis + fix suggestion for this issue.

**Repro:** https://github.com/oriongonza/memgraph-wal-bug

### Security Assessment

Tested 7 payloads:

| Payload | Content | Exit |
|---------|---------|------|
| null | `\x00` × 5 | 139 |
| ascii | `A` × 5 | 139 |
| long | `A` × 100 | 139 |
| ptr-like | `\x41\x41\x41\x41\x41\x41\x00\x00` | 139 |
| random | 16 random bytes | 139 |
| fmt-str | `%x%x%x%x%x%x` | 139 |
| nul-term | `ABC\0DEF\0GHI` | 139 |

All identical crash. Validation fails before data interpretation → DoS only, not RCE. CVSS 5.3.

### Root Cause

Exception during RocksDB init → virtual method called on partially-constructed object → SIGSEGV.

### Suggested fix

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
