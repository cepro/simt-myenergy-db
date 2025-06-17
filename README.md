# simt-supabase

[![Supabase CI](https://github.com/cepro/simt-supabase/actions/workflows/supabase-ci.yml/badge.svg)](https://github.com/cepro/simt-supabase/actions/workflows/supabase-ci.yml)

Config, SQL, functions for the supabase database.

## Scripts

- db-up - start both supabase and timescaledb local instances
- db-down - stop both supabase and timescaledb
- db-reset - run ts-reset then supa-reset
- supa-up - start supabase local
- supa-down - stop supabase local
- supa-reset - run 'supabase db reset' to reset the db
- supa-seed - seed data into supabase for local development
- ts-up - start timescaledb local
- ts-down - stop timescaledb local
- ts-reset - run 'sqitch revert' and 'sqitch deploy' to reset the db
- flows-diff-local - diff local flows database for schema changes
- supa-diff-local - diff local supabase database for schema changes
- template-flows-migrations - substitute variables into flows sqitch migration
  scripts
- template-supa-migrations - substitute variables into supabase sqitch migration
  scripts

## Migrations

A set of migration scripts is maintained for timescaledb and supabase
separately.

[Sqitch](https://sqitch.org) is used to manage migrations include applying
deployments and rollbacks.

### Generate Migration from Diff

see bin/flows-diff-local which will generate a SQL diff between the currently
running local database and a database at the state of the migration files.

## NOTIFY/LISTEN

Example send an encrypted message:
```sql
select public.notify_encrypted('topup_create', '{"amountPence":"100", "reference": "topup from gift", "source": "gift", "notes": "introduction period", "accountId": "d7dbaf27-e813-42e0-a9c1-f008577276b9"}', 'secretsecret');
```