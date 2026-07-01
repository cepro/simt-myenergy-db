# myenergy-db

[![Build Test CI](https://github.com/cepro/myenergy-db/actions/workflows/build-test.yml/badge.svg)](https://github.com/cepro/myenergy-db/actions/workflows/build-test.yml)

Config, SQL, and functions for the MyEnergy database (Timescale / PostgreSQL).

## Scripts

All scripts live in `bin/`.

### Database lifecycle

- `db-up` - start the local Timescale container (creates the container and
  volume on first run)
- `db-down` - stop and remove the local DB container
- `volume-clean` - remove leftover Supabase Docker volumes for this project

### Data & schema

- `seed` - load seed data from `sqitch/seed/seed.sql`
- `reset-contract-signatures` - reset contract signatures
  (`sqitch/seed/reset-contract-signatures.sql`)
- `dump-local-timescale-data` - dump `myenergy` schema *data* from the local DB
  into `dumps/`
- `dump-local-timescale-schema` - dump `myenergy` schema *DDL* from the local
  DB into `dumps/`
- `restore-local-timescale-data` - restore a dump file into the local DB
- `dump-remote-supabase-db-data` - dump `public` schema *data* from the remote
  Supabase DB into `dumps/`
- `dump-remote-supabase-db-schema` - dump `myenergy` schema *DDL* from the
  remote Timescale DB into `dumps/`
- `dump-remote-supabase-auth-data` - dump `auth.users` (and related tables)
  from the remote Supabase DB into `dumps/`

### Utilities

- `jwt-create` - mint a Supabase JWT from a secret file
- `test` - run the pgTAP test suite (see [Testing](#testing))

### Internal helpers

- `psql-wrapper` - run a SQL file against the local DB via docker `psql`
  (used by `seed`, `reset-contract-signatures`)
- `pg_prove` - run `pg_prove` inside docker (used by `test`)
- `library.sh` - shared shell variables/helpers

## Migrations

A set of migration scripts is maintained for the database.

[Sqitch](https://sqitch.org) is used to manage migrations include applying
deployments and rollbacks.

```sh
> cp sqitch_secrets.conf.example sqitch_secrets.conf
> SQITCH_USER_CONFIG=sqitch_secrets.conf sqitch deploy --target timescale-<org>
```

## Testing

Tests use [pg_prove](https://pgtap.org/) and are run against a local Timescale instance.

```sh
# Run all tests
./bin/test

# Check exit code (0 = pass, non-zero = fail)
./bin/test; echo "Exit: $?"

# Run specific test file(s)
./bin/test tests/011_contract_signatures.sql
./bin/test tests/011_contract_signatures.sql tests/012_sync_registered_proprietors_to_customer_accounts.sql

# Show only pass/fail summary
./bin/test 2>&1 | grep -E "(Result:|Files=|^tests/)"
```

Note: pg_prove may report `Wstat: 768 (exited 3)` even when all pgtap assertions pass - this can happen if there are non-fatal SQL errors in cleanup statements. The test file may still pass overall.

## NOTIFY/LISTEN

Example send an encrypted message:
```sql
select myenergy.notify_encrypted('topup_create', '{"amountPence":"100", "reference": "topup from gift", "source": "gift", "notes": "introduction period", "accountId": "d7dbaf27-e813-42e0-a9c1-f008577276b9"}', 'secretsecret');
```
