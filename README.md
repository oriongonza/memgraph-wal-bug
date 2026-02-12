# Memgraph SIGSEGV on Corrupted MANIFEST

Memgraph 3.7.2 crashes with SIGSEGV when RocksDB MANIFEST files are corrupted.

## Repro

```bash
./reproduce.sh
```

## Trigger

Container crash during write → truncated MANIFEST → permanent SIGSEGV on restart.

## Security

Tested 7 payloads. All crash identically. **DoS only, not RCE.** CVSS 5.3.

## Fix hint

Use `rocksdb::DB::Open()` status API, check `IsCorruption()`, exit cleanly.

## Upstream

https://github.com/memgraph/memgraph/issues/3785
