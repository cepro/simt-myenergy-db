# myenergy-db

[![Supabase CI](https://github.com/cepro/myenergy-db/actions/workflows/supabase-ci.yml/badge.svg)](https://github.com/cepro/myenergy-db/actions/workflows/supabase-ci.yml)

Config, SQL, functions for the supabase database.

## Scripts

- db-up - start supabase local instance
- db-down - stop supabase local instance
- db-reset - run supa-reset
- supa-up - start supabase local
- supa-down - stop supabase local
- supa-reset - run 'supabase db reset' to reset the db
- supa-seed - seed data into supabase for local development
- supa-diff-local - diff local supabase database for schema changes scripts
- template-supa-migrations - substitute variables into supabase sqitch migration scripts

## Migrations

A set of migration scripts is maintained for supabase.

[Sqitch](https://sqitch.org) is used to manage migrations include applying
deployments and rollbacks.

```sh
> cp sqitch_secrets.conf.example sqitch_secrets.conf
> SQITCH_USER_CONFIG=sqitch_secrets.conf sqitch deploy --target timescale-<org>
```

## Testing

Tests use [pg_prove](https://pgtap.org/) and are run against a local Supabase instance.

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