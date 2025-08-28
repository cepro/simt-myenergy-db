-- Revert supabase:gifts_table_additions from pg

BEGIN;

ALTER TABLE myenergy.gifts
    DROP COLUMN status,
    DROP COLUMN account_id,
    DROP COLUMN scheduled_at;

DROP TRIGGER topups_gifts_check_gift_unique_trigger ON myenergy.topups_gifts;
DROP FUNCTION myenergy.topups_gifts_check_gift_unique();

DROP TABLE myenergy.topups_gifts;
DROP FUNCTION myenergy.submittable_gifts();
DROP TYPE myenergy."gift_status_enum";

DROP TRIGGER gifts_scheduled_at_future ON myenergy.gifts;
DROP FUNCTION myenergy.gifts_enforce_scheduled_at_future();

DROP TRIGGER topups_update_gift_status ON myenergy.topups;
DROP FUNCTION myenergy.update_gift_on_topup_completed();

COMMIT;
