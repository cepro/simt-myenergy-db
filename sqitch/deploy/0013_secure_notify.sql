-- Deploy supabase:0013_secure_notify to pg

BEGIN;

CREATE TABLE myenergy.postgres_notifications_outbox (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    channel text NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);

ALTER TABLE ONLY myenergy.postgres_notifications_outbox
    ADD CONSTRAINT postgres_notifications_outbox_pkey PRIMARY KEY (id);

COMMENT ON TABLE myenergy.postgres_notifications_outbox IS
    'Messages to be sent encrypted as Postgres NOTIFY/LISTEN messages. An external job with the encryption key will send these and remove them once sent. Then they will go into myenergy.postgres_notifications.';

CREATE OR REPLACE FUNCTION myenergy.notify(
    p_channel text,
    p_payload jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO "myenergy"."postgres_notifications_outbox" (channel, payload) 
        VALUES (p_channel, p_payload);
END;
$$;


CREATE OR REPLACE FUNCTION myenergy.notify_topup_scheduled()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM myenergy.notify(
        'topup_scheduled', 
        row_to_json(NEW)::jsonb
    );
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION myenergy.notify_topup_completed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF OLD.status != NEW.status AND NEW.status = 'completed' THEN
        PERFORM myenergy.notify(
            'topup_completed', 
            row_to_json(NEW)::jsonb
        );
    END IF;
	RETURN NEW;
END;
$$;

CREATE TRIGGER notify_topup_scheduled_trigger
    AFTER INSERT ON myenergy.topups
    FOR EACH ROW
    EXECUTE FUNCTION myenergy.notify_topup_scheduled();


CREATE TRIGGER notify_topup_completed_trigger
    AFTER UPDATE OF status ON myenergy.topups
    FOR EACH ROW
    EXECUTE FUNCTION myenergy.notify_topup_completed();


COMMIT;
