-- Deploy supabase:0031_event_log_type_topup_applied to pg
-- Add the missing meter event type 48.
--
-- Type 48 is not defined in the Emlite protocol enum
-- (emop-frame-protocol/formats/emop_event_log_response.ksy has a gap at
-- 45-60) and had no row in flows.meter_event_log_type, so it was showing up
-- unnamed and was easy to overlook.
--
-- Empirically it is the meter's "credit token accepted / topup applied"
-- event. Across the whole MGF database 1161 of 1295 type-48 rows occur within
-- +/-10 minutes of a myenergy.topups.used_at, and the match holds for every
-- topup source (payment, gift, solar_credit, adjustment). Worked examples on
-- HMCE Plot-21 (23 Jul 2026) and HMCE Plot-43 (23 Jul, 29 Aug 2026) all line
-- up within a few seconds.
--
-- The name below is inferred from that correlation, not from the spec. If the
-- team prefers platform terminology, TOPUP_APPLIED is an acceptable
-- alternative (the underlying behaviour is a credit application regardless of
-- source).

BEGIN;

INSERT INTO flows.meter_event_log_type (id, name) VALUES
    (48, 'CREDIT_TOKEN_APPLIED')
ON CONFLICT DO NOTHING;

COMMIT;