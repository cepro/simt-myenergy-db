BEGIN;

-- This is the only data that is not blown away by the sqitch revert step in
-- supa-reset so we manually remove it here.
DELETE FROM auth.users;

COMMIT;