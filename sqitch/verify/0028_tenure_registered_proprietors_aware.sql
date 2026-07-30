-- Verify supabase:0028_tenure_registered_proprietors_aware on pg

BEGIN;

-- tenure_for_property(uuid) exists and is STABLE.
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n
      FROM pg_proc p
      JOIN pg_namespace ns ON ns.oid = p.pronamespace
     WHERE p.proname = 'tenure_for_property' AND ns.nspname = 'myenergy'
       AND p.provolatile = 's'; -- STABLE
    IF n < 1 THEN
        RAISE EXCEPTION 'myenergy.tenure_for_property(uuid) STABLE not found';
    END IF;
END $$;

-- update_property_tenure() now references registered_proprietors.
DO $$
DECLARE def text;
BEGIN
    SELECT pg_get_functiondef('myenergy.update_property_tenure()'::regprocedure) INTO def;
    IF def NOT LIKE '%registered_proprietors%' THEN
        RAISE EXCEPTION 'update_property_tenure() does not reference registered_proprietors';
    END IF;
END $$;

-- Trigger fires on registered_proprietors INSERT/UPDATE/DELETE.
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n
      FROM pg_trigger
     WHERE tgname = 'update_property_tenure_registered_proprietors'
       AND NOT tgisinternal;
    IF n < 1 THEN
        RAISE EXCEPTION 'trigger update_property_tenure_registered_proprietors missing';
    END IF;
END $$;

-- Invariant: stored tenure matches tenure_for_property for every property.
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n
      FROM myenergy.properties p
     WHERE p.tenure IS DISTINCT FROM myenergy.tenure_for_property(p.id);
    IF n > 0 THEN
        RAISE EXCEPTION '% properties have tenure that does not match tenure_for_property', n;
    END IF;
END $$;

COMMIT;
