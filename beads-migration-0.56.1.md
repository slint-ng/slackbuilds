# Beads 0.56.1 Migration Steps

`0.56.1` migration is mostly about moving/operating on the Dolt backend and updating workflow tooling.

1. Back up current data:
```bash
cp -a .beads ".beads.backup.$(date +%Y%m%d-%H%M%S)"
```

2. Run prechecks:
```bash
bd --version
bd doctor --migration=pre --json
bd doctor --json
```

3. Ensure Dolt server is reachable (new requirement for normal operations):
```bash
bd dolt test
```
If this fails, start/configure your Dolt SQL server, then re-test.

4. Migrate data if you are still on legacy SQLite:
```bash
bd migrate --to-dolt --dry-run --json
bd migrate --to-dolt --yes
```
In `0.56.1`, `bd init` can also auto-detect old storage and guide migration.

5. If repo identity changed (new remote/clone history), refresh repo ID:
```bash
bd migrate --update-repo-id --yes
```

6. Update hooks (important in 0.56.1):
```bash
bd hooks install --force
```

7. Validate completion:
```bash
bd doctor --migration=post --json
bd doctor --json
```

8. Switch sync habits:
- `bd sync` is deprecated/no-op.
- Use:
```bash
bd dolt pull
bd dolt push
```

For this repo's current state specifically, there is no pending schema migration; blockers are operational (`Dolt server unreachable`) plus outdated hooks.

## Sources
- https://github.com/steveyegge/beads/releases/tag/v0.56.1
- https://github.com/steveyegge/beads/pull/90
- https://github.com/steveyegge/beads/pull/97
