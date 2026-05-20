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

## Project Notes

- Uses sqitch for migrations
- Timescale (PostgreSQL) local database
- Tests use pgtap framework