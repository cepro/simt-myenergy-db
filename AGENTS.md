# myenergy-db Agent Instructions

## Testing

Run pg_prove tests against local Timescale:
```bash
./bin/test
```

Check exit code (0=pass, non-zero=fail):
```bash
./bin/test; echo "Exit: $?"
```

Run specific tests:
```bash
./bin/test tests/011_contract_signatures.sql
./bin/test tests/011_contract_signatures.sql tests/012_sync_registered_proprietors_to_customer_accounts.sql
```

Show only summary:
```bash
./bin/test 2>&1 | grep -E "(Result:|Files:)"
```

**Note:** `Wstat: 768` warnings may appear even when all assertions pass - check the `Result:` line at the end.

## Database

- Reset local db: `docker compose -f docker/local/docker-compose.yml down -v --remove-orphans && docker compose -f docker/local/docker-compose.yml up -d`
- Seed data: `./bin/seed`

Local database runs at `localhost:15432` (Timescale via docker/local/docker-compose.yml from cepro/supabase-host).

## Sqitch reverts — ONLY use `--to-change`, never the bare positional form

This is a **hard rule**, not a preference. When reverting a migration, you
**must** use `sqitch revert --target <t> --to-change <change>`, where
`<change>` is the change that should **remain** as HEAD (i.e. the change
*before* the one you want to remove).

Never pass the change to revert as a bare positional argument
(`sqitch revert <change>`). The bare positional form is dangerous: depending
on where the named change sits in the plan it can either silently no-op or
revert **multiple** steps at once, with no obvious warning. `--to-change` is
the only form that pins the post-revert HEAD explicitly and cannot
accidentally walk back further than intended.

To remove the latest change `0027`, target `0026` (the one before it):

```bash
sqitch revert --target timescale-mgf --to-change 0026_docuseal_multi_signature
```

After every revert, confirm the result before doing anything else:

```bash
sqitch status --target timescale-mgf   # HEAD must be the change you targeted
```

This guards against both silent no-ops and accidental mass-reverts.

## Project Notes

- Uses sqitch for migrations
- Timescale (PostgreSQL) local database
- Tests use pgtap framework