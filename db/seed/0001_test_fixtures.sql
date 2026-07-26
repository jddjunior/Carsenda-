-- 0001_test_fixtures.sql
-- Deterministic fixtures. Fixed UUIDs so assertions are stable across runs.
-- Coordinates are real city centroids (lon, lat).

truncate carsenda.events, carsenda.reviews, carsenda.payouts, carsenda.payments,
         carsenda.condition_reports, carsenda.bids, carsenda.shipments,
         carsenda.vehicles, carsenda.carrier_routes, carsenda.carrier_members,
         carsenda.carriers, carsenda.profiles restart identity cascade;

-- Users -----------------------------------------------------------------
insert into carsenda.profiles (id, role, full_name, email) values
  ('11111111-1111-1111-1111-111111111111','shipper','Shipper Alpha','alpha@example.com'),
  ('22222222-2222-2222-2222-222222222222','shipper','Shipper Bravo','bravo@example.com'),
  ('33333333-3333-3333-3333-333333333333','carrier','Carrier One Driver','c1@example.com'),
  ('44444444-4444-4444-4444-444444444444','carrier','Carrier Two Driver','c2@example.com'),
  ('55555555-5555-5555-5555-555555555555','carrier','Lapsed Carrier Driver','c3@example.com'),
  ('99999999-9999-9999-9999-999999999999','admin','Platform Admin','admin@example.com');

-- Carriers --------------------------------------------------------------
-- c1: fully eligible, high rating. c2: eligible, lower rating.
-- c3: ACTIVE authority but insurance expires before the pickup window ends.
-- c4: insurance valid but authority suspended.
insert into carsenda.carriers
  (id, legal_name, dot_number, mc_number, authority_status, insurance_expires_on,
   cargo_insurance_cents, rating, acceptance_rate, home_base) values
  ('aaaaaaaa-0000-0000-0000-000000000001','Sunbelt Auto Transport','1000001','MC100001',
   'active','2027-12-31', 25000000, 4.80, 0.9200, st_point(-80.1918, 25.7617)::geography),
  ('aaaaaaaa-0000-0000-0000-000000000002','Gulf Coast Carriers','1000002','MC100002',
   'active','2027-12-31', 15000000, 4.10, 0.7500, st_point(-80.2000, 25.8000)::geography),
  ('aaaaaaaa-0000-0000-0000-000000000003','Lapsed Insurance Hauling','1000003','MC100003',
   'active','2026-08-01', 10000000, 4.90, 0.9900, st_point(-80.1918, 25.7617)::geography),
  ('aaaaaaaa-0000-0000-0000-000000000004','Suspended Authority Lines','1000004','MC100004',
   'suspended','2027-12-31', 10000000, 5.00, 1.0000, st_point(-80.1918, 25.7617)::geography);

insert into carsenda.carrier_members (carrier_id, user_id, member_role) values
  ('aaaaaaaa-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','owner'),
  ('aaaaaaaa-0000-0000-0000-000000000002','44444444-4444-4444-4444-444444444444','owner'),
  ('aaaaaaaa-0000-0000-0000-000000000003','55555555-5555-5555-5555-555555555555','owner');

-- Routes: Miami -> Seattle corridor, open equipment, Sep 2026 window.
insert into carsenda.carrier_routes
  (id, carrier_id, origin, destination, corridor_m, available_from, available_to, equipment, capacity) values
  ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001',
   st_point(-80.1918, 25.7617)::geography, st_point(-122.3321, 47.6062)::geography,
   150000,'2026-09-01','2026-09-30','open',7),
  ('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000002',
   st_point(-80.3000, 25.9000)::geography, st_point(-122.4000, 47.5000)::geography,
   150000,'2026-09-01','2026-09-30','open',7),
  ('bbbbbbbb-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000003',
   st_point(-80.1918, 25.7617)::geography, st_point(-122.3321, 47.6062)::geography,
   150000,'2026-09-01','2026-09-30','open',7),
  ('bbbbbbbb-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000004',
   st_point(-80.1918, 25.7617)::geography, st_point(-122.3321, 47.6062)::geography,
   150000,'2026-09-01','2026-09-30','open',7),
  -- Enclosed-only route on the same lane: must NOT match an open shipment.
  ('bbbbbbbb-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000001',
   st_point(-80.1918, 25.7617)::geography, st_point(-122.3321, 47.6062)::geography,
   150000,'2026-09-01','2026-09-30','enclosed',7),
  -- Far-off-corridor route (Denver -> Chicago): must NOT match.
  ('bbbbbbbb-0000-0000-0000-000000000006','aaaaaaaa-0000-0000-0000-000000000002',
   st_point(-104.9903, 39.7392)::geography, st_point(-87.6298, 41.8781)::geography,
   150000,'2026-09-01','2026-09-30','open',7);

-- Vehicles --------------------------------------------------------------
insert into carsenda.vehicles (id, owner_id, year, make, model, vehicle_class, operable) values
  ('cccccccc-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
   2022,'Honda','Accord','sedan',true),
  ('cccccccc-0000-0000-0000-000000000002','22222222-2222-2222-2222-222222222222',
   2019,'Ford','F-250','pickup',false);

-- Shipments -------------------------------------------------------------
-- Alpha: Miami -> Seattle, open, Sept pickup, open for bids.
insert into carsenda.shipments
  (id, shipper_id, vehicle_id, origin, destination, origin_label, destination_label,
   pickup_window_start, pickup_window_end, transport_type, status, distance_mi, quoted_cents) values
  ('dddddddd-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
   'cccccccc-0000-0000-0000-000000000001',
   st_point(-80.1918, 25.7617)::geography, st_point(-122.3321, 47.6062)::geography,
   'Miami, FL','Seattle, WA','2026-09-10','2026-09-15','open',
   'open_for_bids', 3300.0, 250000),
  -- Bravo's private shipment. Used to prove cross-shipper isolation.
  ('dddddddd-0000-0000-0000-000000000002','22222222-2222-2222-2222-222222222222',
   'cccccccc-0000-0000-0000-000000000002',
   st_point(-95.3698, 29.7604)::geography, st_point(-118.2437, 34.0522)::geography,
   'Houston, TX','Los Angeles, CA','2026-09-12','2026-09-18','enclosed',
   'quoted', 1550.0, 300000);

-- Bids ------------------------------------------------------------------
insert into carsenda.bids (id, shipment_id, carrier_id, amount_cents, status) values
  ('eeeeeeee-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001',
   'aaaaaaaa-0000-0000-0000-000000000001', 240000,'open'),
  ('eeeeeeee-0000-0000-0000-000000000002','dddddddd-0000-0000-0000-000000000001',
   'aaaaaaaa-0000-0000-0000-000000000002', 235000,'open');

reset role;
