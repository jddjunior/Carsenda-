-- test_matching.sql
-- Proves the eligibility gates are absolute and the ranking is ordered.

\set ON_ERROR_STOP on

do $$
declare
  v_ship uuid := 'dddddddd-0000-0000-0000-000000000001';
  v_c1   uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_c2   uuid := 'aaaaaaaa-0000-0000-0000-000000000002';
  v_c3   uuid := 'aaaaaaaa-0000-0000-0000-000000000003';  -- lapsed insurance
  v_c4   uuid := 'aaaaaaaa-0000-0000-0000-000000000004';  -- suspended authority
  v_n    integer;
  v_top  uuid;
  v_s1   numeric;
  v_s2   numeric;
begin
  select count(*) into v_n from carsenda.match_carriers(v_ship, 50);
  assert v_n = 2, format('M1 expected exactly 2 eligible carriers, got %s', v_n);

  -- M2 Lapsed insurance is excluded even though its rating is the highest
  --    in the fixture set. Eligibility must beat score.
  assert not exists (select 1 from carsenda.match_carriers(v_ship,50) where carrier_id = v_c3),
    'M2 carrier with insurance expiring before pickup window end was returned';

  -- M3 Suspended authority excluded despite perfect rating and acceptance.
  assert not exists (select 1 from carsenda.match_carriers(v_ship,50) where carrier_id = v_c4),
    'M3 carrier with suspended authority was returned';

  -- M4 Equipment mismatch: carrier 1 also has an enclosed route on this exact
  --    lane. The shipment is open, so carrier 1 must appear exactly once.
  select count(*) into v_n from carsenda.match_carriers(v_ship,50) where carrier_id = v_c1;
  assert v_n = 1, format('M4 carrier 1 should match once via its open route, got %s', v_n);

  -- M5 Off-corridor route (Denver -> Chicago) must not match a Miami -> Seattle lane.
  select count(*) into v_n from carsenda.match_carriers(v_ship,50)
    where route_id = 'bbbbbbbb-0000-0000-0000-000000000006';
  assert v_n = 0, 'M5 off-corridor route matched';

  -- M6 Ranking: exact-endpoint, higher-rated carrier ranks first.
  select carrier_id into v_top from carsenda.match_carriers(v_ship,50) limit 1;
  assert v_top = v_c1, format('M6 expected carrier 1 top-ranked, got %s', v_top);

  select fit_score into v_s1 from carsenda.match_carriers(v_ship,50) where carrier_id = v_c1;
  select fit_score into v_s2 from carsenda.match_carriers(v_ship,50) where carrier_id = v_c2;
  assert v_s1 > v_s2, format('M7 expected %s > %s', v_s1, v_s2);

  -- M8 Perfect endpoint match with rating 4.80 and acceptance 0.92:
  --    0.45(1) + 0.25(1) + 0.20(4.80/5) + 0.10(0.92) = 0.9840
  assert v_s1 = 0.9840, format('M8 expected fit_score 0.9840 for carrier 1, got %s', v_s1);

  -- M9 Zero deviation reported for the exact-match carrier.
  select origin_deviation_mi into v_s1 from carsenda.match_carriers(v_ship,50)
    where carrier_id = v_c1;
  assert v_s1 = 0.0, format('M9 expected 0.0 origin deviation, got %s', v_s1);

  -- M10 Limit is respected.
  select count(*) into v_n from carsenda.match_carriers(v_ship, 1);
  assert v_n = 1, format('M10 limit not respected, got %s', v_n);

  raise notice 'matching: 10/10 PASS';
end $$;

-- M11 Capacity gate: fill carrier 1 to its route capacity and confirm it drops out.
do $$
declare
  v_n integer;
  i   integer;
  v_vehicle uuid;
begin
  insert into carsenda.vehicles (owner_id, make, model, vehicle_class)
  values ('11111111-1111-1111-1111-111111111111','Test','Filler','sedan')
  returning id into v_vehicle;

  for i in 1..7 loop
    insert into carsenda.shipments
      (shipper_id, vehicle_id, origin, destination, origin_label, destination_label,
       pickup_window_start, pickup_window_end, transport_type, status, assigned_carrier_id)
    values ('11111111-1111-1111-1111-111111111111', v_vehicle,
            st_point(-80.1918,25.7617)::geography, st_point(-122.3321,47.6062)::geography,
            'Miami, FL','Seattle, WA','2026-09-10','2026-09-15','open',
            'assigned','aaaaaaaa-0000-0000-0000-000000000001');
  end loop;

  select count(*) into v_n from carsenda.match_carriers('dddddddd-0000-0000-0000-000000000001',50)
    where carrier_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  assert v_n = 0, format('M11 carrier at capacity still matched (%s rows)', v_n);

  raise notice 'matching capacity gate: 1/1 PASS';
  raise exception 'rollback_capacity_fixture';   -- undo, keep fixtures clean
exception when others then
  if sqlerrm <> 'rollback_capacity_fixture' then raise; end if;
end $$;
