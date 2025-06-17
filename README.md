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

## NOTIFY/LISTEN

Example send an encrypted message:
```sql
select public.notify_encrypted('topup_create', '{"amountPence":"100", "reference": "topup from gift", "source": "gift", "notes": "introduction period", "accountId": "d7dbaf27-e813-42e0-a9c1-f008577276b9"}', 'secretsecret');
```