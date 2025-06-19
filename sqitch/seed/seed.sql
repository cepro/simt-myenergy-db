BEGIN;

--
-- public schema - insert rows 
--  

INSERT INTO "public"."contract_terms" ("id", "summary_text", "short_description", "version", "created_at", "type", "subtype", "docuseal_template_id", "docuseal_template_slug") VALUES
    ('8674594d-2684-4ba2-9d05-3867d948dee3', 'Solar short term v1 (WLCE)', 'Solar short term desc (WLCE)', 1, '2023-09-27 12:32:30.511', 'solar', 'short_term', 34019, 'z6D1KaThV4zphE'),
    ('be3d69cc-ecb3-403b-8c52-edcbc40debf7', 'Solar short term v1 (HMCE) ', 'Solar short term desc (HMCE)', 1, '2023-09-27 12:32:30.511', 'solar', 'short_term', 31019, 'abc1KaThV4zxyz'),
	
    ('c95dd1d5-b1fd-4db2-9570-7dca975a9349', 'Supply v1 summary (WLCE)', 'Supply v1 desc (WLCE)', 1, '2023-08-01 23:22:48.65366', 'supply', null, 33983, 'P5EfvMYA3K6W5p'),
    ('3c1da6e1-f43e-42b6-a3d0-39278ec3fb4d','Supply v2 summary (WLCE)', 'Supply v2 desc (WLCE)', 2,'2023-10-17 11:11:32.472981','supply',NULL,33986,'cZb4PeXPCQmNk7'),
    
    ('062194b8-bf44-4aa7-9c48-c2aaec4e4bb8','Supply summary (HMCE)', 'Supply desc (HMCE)', 1,'2023-10-17 11:11:32.472981','supply',NULL,33990,'ksdf93jfd983f3'),
	
    ('d82d8f92-6546-40d0-9c60-3c81c6e627df', 'Solar 30 year v1 summary (WLCE)', 'Solar 30 v1 desc (WLCE)', 1, '2023-08-01 23:22:48.65366', 'solar', 'thirty_year', 33984, 'oM6pq9T16VNZ6b'),
    ('9944e68d-8d63-43c7-936e-9870fac66826','Solar 30 year v2 summary (WLCE)', 'Solar 30 v2 desc (WLCE)', 2,'2023-10-17 11:12:01.163766','solar','thirty_year',33985, 'gF7fur9jFDytuL');

-- Hazelmead is id 363f..
-- Waterlilies is id 527e..
INSERT INTO "public"."contract_terms_esco" ("terms", "esco") VALUES
	-- WLCE Supply v1
    ('c95dd1d5-b1fd-4db2-9570-7dca975a9349','527eed5d-2f81-4abe-a7f4-6fff8ac72703'),
	-- WLCE Supply v2
    ('3c1da6e1-f43e-42b6-a3d0-39278ec3fb4d','527eed5d-2f81-4abe-a7f4-6fff8ac72703'),

    -- WLCE Solar short term v1
    ('8674594d-2684-4ba2-9d05-3867d948dee3', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'),
	
	-- WLCE Solar 30 year v1
    ('d82d8f92-6546-40d0-9c60-3c81c6e627df','527eed5d-2f81-4abe-a7f4-6fff8ac72703'),
	-- WLCE Solar 30 year v2
    ('9944e68d-8d63-43c7-936e-9870fac66826','527eed5d-2f81-4abe-a7f4-6fff8ac72703'),

    -- HMCE Supply v1
    ('062194b8-bf44-4aa7-9c48-c2aaec4e4bb8','363ff821-3a56-4b43-8227-8e53c45fbcdb'),
    -- HMCE Solar short term v1
    ('be3d69cc-ecb3-403b-8c52-edcbc40debf7', '363ff821-3a56-4b43-8227-8e53c45fbcdb');
	

INSERT INTO "public"."contracts" ("id", "terms") VALUES
	-- for unit tests
	('aad0100a-b424-4886-89f4-90df94eeae36', '8674594d-2684-4ba2-9d05-3867d948dee3'),  -- solar short term
	('a4ea9b41-bde6-4729-ab63-91f9c67cb3b2', '9944e68d-8d63-43c7-936e-9870fac66826'),  -- solar 30 year
	('598f3885-000b-40c4-bfa0-8cecb082ff8f', '3c1da6e1-f43e-42b6-a3d0-39278ec3fb4d');  -- supply


-- customers and corresponding auth.users entries:

INSERT INTO "public"."customers" ("fullname", "email", "created_at", "id", "status", "cepro_user", "has_payment_method", "allow_onboard_transition", "confirmed_details_at") VALUES
	('WLCE Cepro Admin', 'a@wl.ce', '2023-05-10 00:23:45', 'dcd4265e-6a05-4ec6-8f66-45ff0accb448', 'live', true, true, true, '2025-01-10 00:23:45'),
	('WLCE 11 13 Owner', 'own11_13@wl.ce', '2023-05-10 00:23:45', 'ef9007fa-4084-4775-b4f1-1c0710fc0511', 'pending', false, true, true, '2025-01-10 00:23:45'),
	('WLCE 11 Occupier', 'occ11@wl.ce', '2023-05-10 00:23:45', '5e26ef47-2b3c-4265-938f-925119086f9c', 'pending', false, true, true, '2025-01-10 00:23:45'),
	('WLCE 13 Occupier', 'occ13@wl.ce', '2023-05-10 00:23:45', 'e760e788-98a9-4a6a-934c-ad9921c7a90a', 'pending', false, true, true, '2025-01-10 00:23:45'),
	('WLCE 12 OwnerOccupier', 'ownocc12@wl.ce', '2023-05-11 06:23:45', 'a445daf9-66c3-4f46-b74d-2d82526c4a1c', 'pending', false, true, true, '2025-01-10 00:23:45'),
	('HMCE 01 Customer', 'ownocc1@hm.ce', '2023-05-12 12:24:34', 'b4cf2b22-cc04-4c86-a910-c601cfdfc244', 'pending', false, true, true, '2025-01-10 00:23:45'),
	('HMCE SEA Customer', 'ownoccsea@hm.ce', '2023-05-13 18:24:34', 'c317324f-13e4-4b87-bc40-eae52928a415', 'pending', false, true, true, '2025-01-10 00:23:45');

INSERT INTO auth.users (instance_id,id,aud,"role",email,encrypted_password,email_confirmed_at,invited_at,confirmation_token,confirmation_sent_at,recovery_token,recovery_sent_at,email_change_token_new,email_change,email_change_sent_at,last_sign_in_at,raw_app_meta_data,raw_user_meta_data,is_super_admin,created_at,updated_at,phone,phone_confirmed_at,phone_change,phone_change_token,phone_change_sent_at,email_change_token_current,email_change_confirm_status,banned_until,reauthentication_token,reauthentication_sent_at,is_sso_user,deleted_at) VALUES
	 ('00000000-0000-0000-0000-000000000000','dcd4265e-6a05-4ec6-8f66-45ff0accb448','authenticated','authenticated','a@wl.ce','$2a$10$RpraqBFICv/T3vENeJE1UeEYzTZ8GO9opgaJ6janMS1ro6a6X8qN.','2023-07-05 07:46:08.002138+10',NULL,'',NULL,'',NULL,'','',NULL,'2024-04-03 13:09:20.920642+10','{"provider": "email", "providers": ["email"]}','{}',NULL,'2023-07-05 07:46:07.988687+10','2024-04-03 13:09:20.921788+10',NULL,NULL,'','',NULL,'',0,NULL,'',NULL,false,NULL),
	 ('00000000-0000-0000-0000-000000000000','ef9007fa-4084-4775-b4f1-1c0710fc0511','authenticated','authenticated','own11_13@wl.ce','$2a$10$RpraqBFICv/T3vENeJE1UeEYzTZ8GO9opgaJ6janMS1ro6a6X8qN.','2023-07-05 07:46:08.002138+10',NULL,'',NULL,'',NULL,'','',NULL,'2024-04-03 13:09:20.920642+10','{"provider": "email", "providers": ["email"]}','{}',NULL,'2023-07-05 07:46:07.988687+10','2024-04-03 13:09:20.921788+10',NULL,NULL,'','',NULL,'',0,NULL,'',NULL,false,NULL),
	 ('00000000-0000-0000-0000-000000000000','5e26ef47-2b3c-4265-938f-925119086f9c','authenticated','authenticated','occ11@wl.ce','$2a$10$RpraqBFICv/T3vENeJE1UeEYzTZ8GO9opgaJ6janMS1ro6a6X8qN.','2023-07-05 07:46:08.002138+10',NULL,'',NULL,'',NULL,'','',NULL,'2024-04-03 13:09:20.920642+10','{"provider": "email", "providers": ["email"]}','{}',NULL,'2023-07-05 07:46:07.988687+10','2024-04-03 13:09:20.921788+10',NULL,NULL,'','',NULL,'',0,NULL,'',NULL,false,NULL),
	 ('00000000-0000-0000-0000-000000000000','e760e788-98a9-4a6a-934c-ad9921c7a90a','authenticated','authenticated','occ13@wl.ce','$2a$10$RpraqBFICv/T3vENeJE1UeEYzTZ8GO9opgaJ6janMS1ro6a6X8qN.','2023-07-05 07:46:08.002138+10',NULL,'',NULL,'',NULL,'','',NULL,'2024-04-03 13:09:20.920642+10','{"provider": "email", "providers": ["email"]}','{}',NULL,'2023-07-05 07:46:07.988687+10','2024-04-03 13:09:20.921788+10',NULL,NULL,'','',NULL,'',0,NULL,'',NULL,false,NULL),
	 ('00000000-0000-0000-0000-000000000000','a445daf9-66c3-4f46-b74d-2d82526c4a1c','authenticated','authenticated','ownocc12@wl.ce','$2a$10$rzMqedKquLhDHD8c2AQTM.ffO2ijVy9rsZvIJX70r68PiXrldCdTe','2023-09-05 13:58:05.20277+10','2023-09-05 13:53:54.482013+10','','2023-09-05 13:53:54.482013+10','',NULL,'','',NULL,'2024-04-03 12:56:28.145681+10','{"provider": "email", "providers": ["email"]}','{}',NULL,'2023-09-05 13:52:38.5226+10','2024-04-03 12:56:28.146653+10',NULL,NULL,'','',NULL,'',0,NULL,'',NULL,false,NULL),
	 ('00000000-0000-0000-0000-000000000000','a1c6eed4-c8e0-4fc7-89a5-a82d205c8b67','authenticated','authenticated','ownocc1@hm.ce','$2a$10$cZLO5G/mDKm4kUbLBbV4t.aqpKy4Lf3N42LMFvAYslfMBiwgVueP6','2024-04-03 13:11:04.654429+10',NULL,'',NULL,'',NULL,'','',NULL,NULL,'{"provider": "email", "providers": ["email"]}','{}',NULL,'2024-04-03 13:11:04.650956+10','2024-04-03 13:11:04.654734+10',NULL,NULL,'','',NULL,'',0,NULL,'',NULL,false,NULL),
	 ('00000000-0000-0000-0000-000000000000','5898adc6-8e43-4ccf-a6ba-6ed325888093','authenticated','authenticated','ownoccsea@hm.ce','$2a$10$jrUSw9L8qZgdkbstjeWmL.zkp/l5abY1eSutVDUJM52cNZgVrMb5e','2024-04-03 13:11:30.308916+10',NULL,'',NULL,'',NULL,'','',NULL,NULL,'{"provider": "email", "providers": ["email"]}','{}',NULL,'2024-04-03 13:11:30.306769+10','2024-04-03 13:11:30.309095+10',NULL,NULL,'','',NULL,'',0,NULL,'',NULL,false,NULL);

INSERT INTO "public"."regions" ("code", "name") VALUES
    ('south_west', 'South West'),
    ('south_east', 'South East'),
    ('london', 'London');

INSERT INTO "public"."places" ("id", "created_at", "parent", "place") VALUES
	('61121e5a-4dbe-4fd2-bc50-1012469b1980', '2023-02-18 09:36:13.108746', NULL, 'United Kingdom'),
	('5137f416-9f0b-49b1-a539-0ca450e8ca2a', '2023-02-18 09:36:34.313165', '61121e5a-4dbe-4fd2-bc50-1012469b1980', 'Bristol');

--
-- sync flows data into public
--

SELECT public.sync_flows_to_public_escos();
SELECT public.sync_flows_to_public_circuits();
SELECT public.sync_flows_to_public_monthly_usage();

UPDATE public.escos SET region = 'south_west' WHERE code in ('wlce', 'hmce', 'bec', 'bpc', 'lab');

--
-- public schema - create records using the setup functions 
--  

--   WLCE   --

----------     Plots 1-17, 20-23 Setup (placeholders for customers and generation meters)     --------

SELECT public.add_property('01', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2112511137', 'EML2137580797', '15 Water Lilies', true, true);
SELECT public.add_property('02', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2112511139', 'EML2137580757', '14 Water Lilies', true, true);
SELECT public.add_property('03', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2112511125', 'EML2137580758', '13 Water Lilies', true, true);
SELECT public.add_property('04', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2112511126', 'EML2137580798', '12 Water Lilies', true, true);
SELECT public.add_property('05', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2112511140', 'EML2137580799', '11 Water Lilies', false, true);
SELECT public.add_property('06', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2137580645', 'EML2137580769', '10 Water Lilies', false, true);
SELECT public.add_property('07', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2137580648', 'EML2137580771', '9 Water Lilies', false, true);
SELECT public.add_property('08', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2137580646', 'EML2137580772', '8 Water Lilies', true, true);
SELECT public.add_property('09', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2137580647', 'EML2137580770', '7 Water Lilies', true, true);
SELECT public.add_property('10', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580761', '6 Water Lilies', false, false);
SELECT public.add_property('11', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580768', '5 Water Lilies', false, false);
SELECT public.add_property('12', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2137580649', 'EML2137580762', '4 Water Lilies', true, false);
SELECT public.add_property('13', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580766', '3 Water Lilies', false, false);
SELECT public.add_property('14', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2137580668', 'EML2137580765', '2 Water Lilies', true, true);
SELECT public.add_property('15', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580775', '1 Water Lilies', true, true);
SELECT public.add_property('16', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2137580684', 'EML2244826953', '27 Water Lilies', true, true);
SELECT public.add_property('17', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2137580714', 'EML2137580776', '26 Water Lilies', true, true);

SELECT public.add_property('18-19', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2208645223', 'EML2137580723', '24 Water Lilies', true, true);

SELECT public.add_property('18a', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580750', '25 Water Lilies', true, true);
SELECT public.add_property('18b', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580788', 'Flat 1, 24 Water Lilies', true, true);
SELECT public.add_property('18c', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580831', 'Flat 3, 24 Water Lilies', true, true);
SELECT public.add_property('19a', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580816', '25a Water Lilies', true, true);
SELECT public.add_property('19b', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580800', '23 Water Lilies', true, true);
SELECT public.add_property('19c', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580812', 'Flat 2, 24 Water Lilies', true, true);

SELECT public.add_property('20', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580764', '22 Water Lilies', true, true);
SELECT public.add_property('21', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580828', '21 Water Lilies', true, true);
SELECT public.add_property('22', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580767', '20 Water Lilies', true, true);
SELECT public.add_property('23', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, public.generate_random_meter_serial(), 'EML2137580830', '19 Water Lilies', true, true);

SELECT public.add_property('24-25', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, 'EML2208645224', 'EML2137580678', 'Landlord, 17 Water Lilies', true, true);

SELECT public.add_property('24a', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, null, 'EML2137580838', '16a Water Lilies', true, true);
SELECT public.add_property('24b', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, null, 'EML2137580774', '18 Water Lilies', true, true);
SELECT public.add_property('24c', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, null, 'EML2137580810', 'Flat 3, 17 Water Lilies', true, true);
SELECT public.add_property('25a', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, null, 'EML2137580792', '16 Water Lilies', true, true);
SELECT public.add_property('25b', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, null, 'EML2137580786', 'Flat 1, 17 Water Lilies', true, true);
SELECT public.add_property('25c', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, null, 'EML2137580823', 'Flat 2, 17 Water Lilies', true, true);

SELECT public.add_property('Undercroft', '527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid, null, 'EML2226727834', 'The Hub, 28 Water Lilies', true, true);


--   HMCE   --

-- -- plots 01 - 02 - apartments that have supply only
SELECT public.add_property('01', '363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid, null, 'EML2137580751', '1 Hazelmead', true, true);
SELECT public.add_property('02', '363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid, null, 'EML2137580777', '2 Hazelmead', true, true);

-- -- plots 16 - 17 - properties with supply AND solar
SELECT public.add_property('16', '363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid, public.generate_random_meter_serial(), 'EML2137580791', '16 Hazelmead', true, true);
SELECT public.add_property('17', '363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid, public.generate_random_meter_serial(), 'EML2137580784', '17 Hazelmead', true, true);

-- -- stairwells
SELECT public.add_property('SEA-Landlord', '363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid, null, 'EML2244826954', 'SEA-Landlord.C', true, true);


-- now meters are in sync the circuit_meter records
SELECT public.sync_flows_to_public_circuits();


-- solar_installation

INSERT INTO "public"."solar_installation" ("property", "mcs", "declared_net_capacity", "commissioning_date") VALUES
    ((SELECT id FROM properties where plot = 'Plot-11' and esco = '527eed5d-2f81-4abe-a7f4-6fff8ac72703'), 
        'MCS111', 3.45, '2024-12-31'),
    ((SELECT id FROM properties where plot = 'Plot-12' and esco = '527eed5d-2f81-4abe-a7f4-6fff8ac72703'), 
        'MCS222', 4.55, '2024-12-31'),
    ((SELECT id FROM properties where plot = 'Plot-13' and esco = '527eed5d-2f81-4abe-a7f4-6fff8ac72703'), 
        'MCS333', 5.95, '2024-12-31'),
    ((SELECT id FROM properties where plot = 'Plot-01' and esco = '363ff821-3a56-4b43-8227-8e53c45fbcdb'), 
        'MCS010', 5.10, '2024-12-31'),
    ((SELECT id FROM properties where plot = 'Plot-SEA-Landlord' and esco = '363ff821-3a56-4b43-8227-8e53c45fbcdb'), 
        'MCS000', 6.25, '2024-12-31');


--
-- Assign test users to properties and accounts
--

update public.properties 
    set owner = (select id from customers where email = 'own11_13@wl.ce')
    where plot in ('Plot-11', 'Plot-13') 
    and esco = '527eed5d-2f81-4abe-a7f4-6fff8ac72703';
update public.properties 
    set owner = (select id from customers where email = 'ownocc12@wl.ce') 
    where plot = 'Plot-12' and esco = '527eed5d-2f81-4abe-a7f4-6fff8ac72703';

update public.properties 
    set owner = (select id from customers where email = 'ownocc1@hm.ce') 
    where plot = 'Plot-01' and esco = '363ff821-3a56-4b43-8227-8e53c45fbcdb';
update public.properties 
    set owner = (select id from customers where email = 'ownoccsea@hm.ce') 
    where plot = 'Plot-SEA-Landlord' and esco = '363ff821-3a56-4b43-8227-8e53c45fbcdb';


update public.customer_accounts 
	set customer = (select id from customers where email = 'own11_13@wl.ce')
	where customer = (select id from customers where email = 'plot11owner-wlce@change.me');
update public.customer_accounts 
	set customer = (select id from customers where email = 'own11_13@wl.ce')
	where customer = (select id from customers where email = 'plot13owner-wlce@change.me');

update public.customer_accounts 
    set customer = (select id from customers where email = 'occ11@wl.ce')
    where customer = (select id from customers where email = 'plot11occupier-wlce@change.me');
update public.customer_accounts 
    set customer = (select id from customers where email = 'occ13@wl.ce')
    where customer = (select id from customers where email = 'plot13occupier-wlce@change.me');

update public.customer_accounts 
    set customer = (select id from customers where email = 'ownocc12@wl.ce')
    where customer = (select id from customers where email = 'plot12owner-wlce@change.me');

update public.customer_accounts 
    set customer = (select id from customers where email = 'ownocc1@hm.ce')
    where customer = (select id from customers where email = 'plot01owner-hmce@change.me');
update public.customer_accounts 
    set customer = (select id from customers where email = 'ownoccsea@hm.ce')
    where customer = (select id from customers where email = 'plotSEA-Landlordowner-hmce@change.me');

-- clean up replaced customers
DELETE FROM customers where email in (
    'plot11owner-wlce@change.me',
    'plot13owner-wlce@change.me',
    'plot11occupier-wlce@change.me',
    'plot13occupier-wlce@change.me',
    'plot12owner-wlce@change.me',
    'plot01owner-hmce@change.me',
    'plotSEA-Landlordowner-hmce@change.me'
);

-- setup 2 prelive status customers by signing their supply contracts (occ11@wl.ce, occ13@wl.ce)
-- setup 1 live customer by signing both solar contracts (own11_13@wl.ce)
UPDATE contracts set signed_date = '2024-01-01 00:00 +00'
WHERE id in (select current_contract from accounts where id in (
    select account from customer_accounts where customer in (
        select id from customers where email in ('occ11@wl.ce', 'occ13@wl.ce', 'own11_13@wl.ce')
    )
)) and "type" in ('supply', 'solar'); -- both contracts


-- Create customer_invites for one WLCE and one HMCE user to check conditional invite URL generation
INSERT INTO customer_invites (customer) VALUES ('ef9007fa-4084-4775-b4f1-1c0710fc0511');
INSERT INTO customer_invites (customer) VALUES ('b4cf2b22-cc04-4c86-a910-c601cfdfc244');


-- Historical rates (pre 2024) from https://www.gov.uk/search/all?keywords=Energy+Price+Guarantee%3A+regional+rates&order=relevance
-- Recent rates from https://www.ofgem.gov.uk/energy-advice-households/get-energy-price-cap-standing-charges-and-unit-rates-region
-- In prod these are to be inserted each quarter after ofgem publishes the next quarter rates.
-- NOTE: Rates are all for prepayment meter and single rate tariffs.
INSERT INTO public.benchmark_tariffs (period_start,unit_rate,standing_charge,region)
	VALUES
	-- NOTE: Jan 2022 - Sep 2022 unknown so used Oct to Dec 
    ('2022-01-01', 0.32248, 0.604, 'south_west'),
    ('2022-04-01', 0.32248, 0.604, 'south_west'),
    ('2022-07-01', 0.32248, 0.604, 'south_west'),
	-- variable rate from: https://www.gov.uk/government/publications/energy-price-guarantee-regional-rates/energy-price-guarantee-regional-rates
	-- standing charge not published there so used the following period
    ('2022-10-01', 0.31339, 0.604, 'south_west'),
    ('2023-01-01', 0.3209, 0.604, 'south_west'),
    -- variable rate from: https://www.gov.uk/government/publications/energy-price-guarantee-regional-rates/energy-price-guarantee-regional-rates-april-to-june-2023
    -- standing charge not published there so used the following period
    ('2023-04-01', 0.3014, 0.604, 'south_west'),
	-- from: https://www.gov.uk/government/publications/energy-price-guarantee-regional-rates/energy-price-guarantee-prepayment-meters-regional-rates-july-to-september-2023
    ('2023-07-01', 0.2752, 0.604, 'south_west'),
    -- from: https://www.gov.uk/government/publications/energy-price-guarantee-regional-rates/energy-price-guarantee-prepayment-meters-regional-rates-and-standing-charges-october-to-december-2023
    ('2023-10-01', 0.2548, 0.579, 'south_west'),
    -- from wayback machine: http://web.archive.org/web/20240523031628/https://www.ofgem.gov.uk/energy-advice-households/get-energy-price-cap-standing-charges-and-unit-rates-region
    ('2024-01-01', 0.2798, 0.6556, 'south_west'),
    ('2024-04-01', 0.2343, 0.6719, 'south_west'),
    -- from prepayment section at Sep 16 2024: https://www.ofgem.gov.uk/get-energy-price-cap-standing-charges-and-unit-rates-region
    ('2024-07-01', 0.2133, 0.6721, 'south_west'),
    ('2024-10-01', 0.2337, 0.6812, 'south_west');

-- In prod these would be inserted each quarter after the new benchmark_tariffs have been inserted.
--   and updated if the discount_rate here is changed:
INSERT INTO public.microgrid_tariffs (esco,period_start,discount_rate_basis_points,emergency_credit,ecredit_button_threshold,debt_recovery_rate) VALUES
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2022-01-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2022-04-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2022-07-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2022-10-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2023-01-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2023-04-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2023-07-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2023-10-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2024-01-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2024-04-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2024-07-01',25,15.00,10.00,0.25),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2024-10-01',25,15.00,10.00,0.25),
	 
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2022-01-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2022-04-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2022-07-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2022-10-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2023-01-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2023-04-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2023-07-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2023-10-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2024-01-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2024-04-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2024-07-01',25,15.00,10.00,0.25),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2024-10-01',25,15.00,10.00,0.25);

INSERT INTO public.customer_tariffs (customer,period_start,discount_rate_basis_points) VALUES
	 -- Plot11 occupier
	 ((select id from customers where email = 'occ11@wl.ce')::uuid,'2024-04-01',0),
	 ((select id from customers where email = 'occ11@wl.ce')::uuid,'2024-07-01',0),
	 ((select id from customers where email = 'occ11@wl.ce')::uuid,'2024-10-01',0),
	 -- Plot13 occupier
	 ((select id from customers where email = 'occ13@wl.ce')::uuid,'2024-04-01',100),
	 ((select id from customers where email = 'occ13@wl.ce')::uuid,'2024-07-01',100),
	 ((select id from customers where email = 'occ13@wl.ce')::uuid,'2024-10-01',100),
	 -- ownocc12@wl.ce
	 ((select id from customers where email = 'ownocc12@wl.ce')::uuid,'2024-04-01',0),
	 ((select id from customers where email = 'ownocc12@wl.ce')::uuid,'2024-07-01',0),
	 ((select id from customers where email = 'ownocc12@wl.ce')::uuid,'2024-10-01',0),
	 -- ownocc1@hm.ce
	 ((select id from customers where email = 'ownocc1@hm.ce')::uuid,'2024-04-01',100),
	 ((select id from customers where email = 'ownocc1@hm.ce')::uuid,'2024-07-01',0),
	 ((select id from customers where email = 'ownocc1@hm.ce')::uuid,'2024-10-01',0),
	 -- ownoccsea@hm.ce (use 25 so we get 6 decimal place value which test adjustment to 5 decimal places)
     ((select id from customers where email = 'ownoccsea@hm.ce')::uuid,'2024-04-01',25),
	 ((select id from customers where email = 'ownoccsea@hm.ce')::uuid,'2024-07-01',25),
	 ((select id from customers where email = 'ownoccsea@hm.ce')::uuid,'2024-10-01',25);
 
-- monthly_costs_compute will insert rows in monthly_costs table:
select public.monthly_costs_compute('2024-05-01'::date);
select public.monthly_costs_compute('2024-06-01'::date);
select public.monthly_costs_compute('2024-07-01'::date);
select public.monthly_costs_compute('2024-08-01'::date);

-- topups

INSERT INTO "public"."topups" ("id", "meter", "amount_pence", "status", "source", "notes", "token", "reference", "acquired_at", "used_at", "created_at", "updated_at") VALUES
    -- Plot12 WLCE
    ('0330d28c-74a6-4f17-961e-0316d71a8c0d', (SELECT id FROM meters where serial = 'EML2137580762'), '7129', 'completed', 'gift', 'notes abc', '07550128313424780340', 'plot12 topup 1', '2024-12-10 03:44:11+00', '2024-12-22 19:05:11+00', '2024-12-11 10:39:51.56564+00', '2024-12-22 19:39:51.56564+00'),
    ('08384d5d-44b8-4acf-a177-69629fe5c183', (SELECT id FROM meters where serial = 'EML2137580762'), '7986', 'completed', 'gift', 'notes xyz', '70496331128691663932', 'plot12 topup 2', '2024-12-20 07:52:06+00', '2024-12-22 19:05:12+00', '2024-12-22 19:43:40.862228+00', '2024-12-22 19:43:40.862228+00'),
    ('d579749d-8711-4cef-a9b9-62be6887ef40', (SELECT id FROM meters where serial = 'EML2137580762'), '3456', 'completed', 'solar_credit', 'march credit', '098063311286916643857', 'plot12 solar credit', '2025-03-01 01:11:06+00', '2025-03-01 01:11:06+00', '2025-03-01 01:11:06+00', '2025-03-01 01:11:06+00'),
    -- Plot11 WLCE
    ('425db671-6d4d-4d69-a472-77643d3d7249', (SELECT id FROM meters where serial = 'EML2137580768'), '9161', 'completed', 'gift', 'notes def', '55297858608314461894', 'plot11 topup 1', '2024-12-12 04:38:02+00', '2024-12-12 05:00:00+00', '2024-12-18 04:21:18.74163+00', '2024-12-18 04:27:22.395673+00');

INSERT INTO "public"."gifts" ("customer_id", "amount_pence", "reason") VALUES 
    ((select id from customers where email = 'ownocc12@wl.ce'), '7129', 'sign up bonus'),
    ((select id from customers where email = 'ownocc12@wl.ce'), '7986', 'sign up bonus 2'),
    ((select id from customers where email = 'occ11@wl.ce'), '9161', 'sign up bonus');

-- payments

INSERT INTO "public"."payments" ("id", "account", "amount_pence", "status", "payment_intent", "description", "created_at", "updated_at") VALUES 
     -- Plot 11 supply account
     ('194363dc-09ba-4867-bfb6-84f5bbef5d68', 
        (SELECT account from customer_accounts 
            where customer = (select id from customers where email = 'occ11@wl.ce')
            and role = 'occupier'
            and account in (select id from accounts where type = 'supply')),
        '7129', 'succeeded', 'pi_3QYtqEIcs3SlrEZh1DJGobnu', 'top up plot 11 1', '2024-12-22 19:52:34.994497+00', '2024-12-22 19:52:34.994497+00'),
     ('7df1c422-592d-4d3c-aeaa-3ca89adabace',
        (SELECT account from customer_accounts 
            where customer = (select id from customers where email = 'occ11@wl.ce')
            and role = 'occupier'
            and account in (select id from accounts where type = 'supply')),
        '7986', 'processing', 'pi_3QYuLOIcs3SlrEZh1h5r1BtB', 'top up plot 11 2', '2024-12-22 19:51:29.659833+00', '2024-12-22 19:54:12.317468+00'),
     -- Plot 12
     ('e8001ece-2d74-40db-8785-67c3ee2f6857',
        (SELECT account from customer_accounts 
            where customer = (select id from customers where email = 'ownocc12@wl.ce')
                and role = 'occupier'),
        '9161', 'succeeded', 'pi_3QYuUNIcs3SlrEZh1LZm3Wrj', 'top up plot 12 1', '2024-12-22 19:49:56.010935+00', '2024-12-22 19:49:56.010935+00');

-- solar_credits

INSERT INTO public.solar_credit_tariffs (esco, period_start, credit_pence_per_year) VALUES
	 -- WLCE
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2025-02-01',8500),
	 ('527eed5d-2f81-4abe-a7f4-6fff8ac72703'::uuid,'2025-03-01',8500),
	 -- HMCE
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2025-02-01',7800),
	 ('363ff821-3a56-4b43-8227-8e53c45fbcdb'::uuid,'2025-03-01',7900);

INSERT INTO public.monthly_solar_credits (property_id,"month") VALUES
	 ((select id from properties where esco = '527eed5d-2f81-4abe-a7f4-6fff8ac72703' and plot = 'Plot-12'), '2025-01-01'),
	 ((select id from properties where esco = '527eed5d-2f81-4abe-a7f4-6fff8ac72703' and plot = 'Plot-12'), '2025-02-01'),
	 ((select id from properties where esco = '527eed5d-2f81-4abe-a7f4-6fff8ac72703' and plot = 'Plot-12'), '2025-03-01');


INSERT INTO public.solar_credit_allocation 
    (installation_property, allocation_property, ratio) 
VALUES
    -- plot 18-19 owner 0%
    ((select id from public.properties where plot = 'Plot-18-19'), (select id from public.properties where plot = 'Plot-18-19'), 0.0),
    -- units split the credit evenly
    ((select id from public.properties where plot = 'Plot-18-19'), (select id from public.properties where plot = 'Plot-18a'), 0.16666),
    ((select id from public.properties where plot = 'Plot-18-19'), (select id from public.properties where plot = 'Plot-18b'), 0.16666),
    ((select id from public.properties where plot = 'Plot-18-19'), (select id from public.properties where plot = 'Plot-18c'), 0.16666),
    ((select id from public.properties where plot = 'Plot-18-19'), (select id from public.properties where plot = 'Plot-19a'), 0.16666),
    ((select id from public.properties where plot = 'Plot-18-19'), (select id from public.properties where plot = 'Plot-19b'), 0.16666),
    ((select id from public.properties where plot = 'Plot-18-19'), (select id from public.properties where plot = 'Plot-19c'), 0.16666),

    -- plot 24-25 owner 0%
    ((select id from public.properties where plot = 'Plot-24-25'), (select id from public.properties where plot = 'Plot-24-25'), 0.0),
    -- units split the credit evenly
    ((select id from public.properties where plot = 'Plot-24-25'), (select id from public.properties where plot = 'Plot-24a'), 0.16666),
    ((select id from public.properties where plot = 'Plot-24-25'), (select id from public.properties where plot = 'Plot-24b'), 0.16666),
    ((select id from public.properties where plot = 'Plot-24-25'), (select id from public.properties where plot = 'Plot-24c'), 0.16666),
    ((select id from public.properties where plot = 'Plot-24-25'), (select id from public.properties where plot = 'Plot-25a'), 0.16666),
    ((select id from public.properties where plot = 'Plot-24-25'), (select id from public.properties where plot = 'Plot-25b'), 0.16666),
    ((select id from public.properties where plot = 'Plot-24-25'), (select id from public.properties where plot = 'Plot-25c'), 0.16666);

COMMIT;