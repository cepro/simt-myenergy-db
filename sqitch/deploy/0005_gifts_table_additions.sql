-- Deploy supabase:gifts_table_additions to pg

BEGIN;

CREATE TYPE myenergy."gift_status_enum" AS ENUM (
	'pending',
	'processing',
	'cancelled',
	'failed',
	'succeeded');

ALTER TABLE myenergy.gifts
    ADD COLUMN status myenergy."gift_status_enum" DEFAULT 'pending'::myenergy.gift_status_enum NULL,
    ADD COLUMN account_id uuid NULL,
    ADD CONSTRAINT gifts_account_fkey FOREIGN KEY (account_id) REFERENCES myenergy.accounts(id),
    ADD COLUMN scheduled_at timestamptz NULL;

CREATE OR REPLACE FUNCTION myenergy.gifts_enforce_scheduled_at_future()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Only check on INSERT, or when scheduled_at is being updated
  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at) THEN
    IF NEW.scheduled_at <= now() THEN
      RAISE EXCEPTION 'scheduled_at must be in the future (got %)', NEW.scheduled_at;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER gifts_scheduled_at_future
BEFORE INSERT OR UPDATE ON myenergy.gifts
FOR EACH ROW
EXECUTE FUNCTION myenergy.gifts_enforce_scheduled_at_future();

CREATE TABLE myenergy.topups_gifts (
	gift_id uuid NOT NULL,
	topup_id uuid NOT NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT topups_gifts_pkey PRIMARY KEY (gift_id, topup_id),
	CONSTRAINT topups_gifts_gift_fkey FOREIGN KEY (gift_id) REFERENCES  myenergy.gifts(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
	CONSTRAINT topups_gifts_topup_fkey FOREIGN KEY (topup_id) REFERENCES myenergy.topups(id) ON DELETE RESTRICT ON UPDATE RESTRICT
);

GRANT SELECT,INSERT,UPDATE ON TABLE myenergy.topups_gifts TO public_backend;
GRANT SELECT,UPDATE ON TABLE myenergy.gifts TO public_backend;


CREATE OR REPLACE FUNCTION myenergy.topups_gifts_check_gift_unique()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  existing_count integer;
BEGIN
  SELECT COUNT(*) INTO existing_count 
  FROM myenergy.topups_gifts 
  WHERE gift_id = NEW.gift_id;

  IF existing_count > 0 THEN
    RAISE EXCEPTION 'Duplicate gift_id: %. Each gift can only be linked to one topup.', 
                    NEW.gift_id;
  END IF;
  
  RETURN NEW;
END;
$function$
;

create trigger topups_gifts_check_gift_unique_trigger before
insert
    on
    myenergy.topups_gifts for each row execute function myenergy.topups_gifts_check_gift_unique();

CREATE OR REPLACE FUNCTION myenergy.submittable_gifts()
  RETURNS SETOF myenergy.gifts
  LANGUAGE sql
  STABLE SECURITY DEFINER
  SET search_path TO ''
AS $function$
  SELECT g.*
  FROM myenergy.gifts g
  WHERE g.id not in (select tg.gift_id from myenergy.topups_gifts tg where tg.gift_id = g.id)
  AND scheduled_at < now()
$function$
;

CREATE OR REPLACE FUNCTION myenergy.update_gift_on_topup_completed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Only proceed if status has changed to 'completed' and used_at has been set
    IF (OLD.status != 'completed' AND NEW.status = 'completed' AND NEW.used_at IS NOT NULL) THEN
        -- Update the status for any related gifts records
        UPDATE myenergy.gifts g
        SET status = 'succeeded'
        FROM myenergy.topups_gifts tg
        WHERE tg.topup_id = NEW.id
        AND tg.gift_id = g.id
        AND g.status != 'succeeded';
        
        RAISE NOTICE 'Updated gift status to succeeded for topup %', NEW.id;
    END IF;
    
    RETURN NEW;
END;
$function$
;

create trigger topups_update_gift_status after
update
    of status on
    myenergy.topups for each row execute function myenergy.update_gift_on_topup_completed();


COMMIT;
