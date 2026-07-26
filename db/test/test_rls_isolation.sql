-- test_rls_isolation.sql
-- Executes as the 'authenticated' role with a real JWT claim set, exactly as
-- PostgREST/Supabase does. These assertions prove isolation rather than assume it.

\set ON_ERROR_STOP on

-- ============================ SHIPPER ALPHA ============================
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

do $$
declare v_n integer;
begin
  select count(*) into v_n from carsenda.shipments;
  assert v_n = 1, format('R1 alpha should see exactly 1 shipment, saw %s', v_n);

  assert not exists (select 1 from carsenda.shipments
                     where id = 'dddddddd-0000-0000-0000-000000000002'),
    'R2 alpha can read another shippers shipment';

  -- Alpha sees every bid placed on their own shipment, including competitors'.
  select count(*) into v_n from carsenda.bids;
  assert v_n = 2, format('R3 alpha should see 2 bids on own shipment, saw %s', v_n);

  select count(*) into v_n from carsenda.vehicles;
  assert v_n = 1, format('R4 alpha should see 1 vehicle, saw %s', v_n);

  raise notice 'rls shipper alpha: 4/4 PASS';
end $$;
reset role;

-- ============================ SHIPPER BRAVO ============================
set role authenticated;
set request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

do $$
declare v_n integer;
begin
  select count(*) into v_n from carsenda.shipments;
  assert v_n = 1, format('R5 bravo should see exactly 1 shipment, saw %s', v_n);

  assert not exists (select 1 from carsenda.shipments
                     where id = 'dddddddd-0000-0000-0000-000000000001'),
    'R6 bravo can read alphas shipment';

  -- Bravo has no shipment open for bids, so no bids are visible.
  select count(*) into v_n from carsenda.bids;
  assert v_n = 0, format('R7 bravo should see 0 bids, saw %s', v_n);

  raise notice 'rls shipper bravo: 3/3 PASS';
end $$;
reset role;

-- ======================= CARRIER 1 MEMBER (driver) =====================
set role authenticated;
set request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

do $$
declare v_n integer;
begin
  -- Marketplace browse: only shipments open for bids.
  select count(*) into v_n from carsenda.shipments;
  assert v_n = 1, format('R8 carrier1 should see 1 open shipment, saw %s', v_n);

  assert not exists (select 1 from carsenda.shipments
                     where id = 'dddddddd-0000-0000-0000-000000000002'),
    'R9 carrier1 can read a shipment that is not open for bids';

  -- Bid confidentiality: a carrier must never see a competitor's bid amount.
  select count(*) into v_n from carsenda.bids;
  assert v_n = 1, format('R10 carrier1 should see only its own bid, saw %s', v_n);

  assert not exists (select 1 from carsenda.bids
                     where carrier_id = 'aaaaaaaa-0000-0000-0000-000000000002'),
    'R11 carrier1 can read a competitor bid';

  -- Carrier routes are private to the carrier. Carrier1 owns exactly 2
  -- (one open, one enclosed); the other 4 in the fixture belong to others.
  select count(*) into v_n from carsenda.carrier_routes;
  assert v_n = 2, format('R12 carrier1 should see only its own 2 routes, saw %s', v_n);

  select count(*) into v_n from carsenda.carrier_routes
   where carrier_id <> 'aaaaaaaa-0000-0000-0000-000000000001';
  assert v_n = 0, format('R12b carrier1 leaked %s foreign routes', v_n);

  -- No shipment is assigned to carrier1, so no vehicle is visible.
  select count(*) into v_n from carsenda.vehicles;
  assert v_n = 0, format('R13 carrier1 should see 0 vehicles, saw %s', v_n);

  -- Payments belong to shippers; carriers must never read them.
  select count(*) into v_n from carsenda.payments;
  assert v_n = 0, format('R14 carrier1 should see 0 payments, saw %s', v_n);

  raise notice 'rls carrier1: 8/8 PASS';
end $$;
reset role;

-- ====================== CARRIER 2 MEMBER (isolation) ===================
set role authenticated;
set request.jwt.claims = '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';

do $$
declare v_n integer;
begin
  select count(*) into v_n from carsenda.bids;
  assert v_n = 1, format('R15 carrier2 should see only its own bid, saw %s', v_n);

  assert not exists (select 1 from carsenda.bids
                     where carrier_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
    'R16 carrier2 can read carrier1 bid';

  raise notice 'rls carrier2: 2/2 PASS';
end $$;
reset role;

-- ============================== UNKNOWN USER ===========================
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000ff","role":"authenticated"}';

do $$
declare v_n integer;
begin
  select count(*) into v_n from carsenda.shipments;
  assert v_n = 0, format('R17 unknown user should see 0 shipments, saw %s', v_n);
  select count(*) into v_n from carsenda.bids;
  assert v_n = 0, format('R18 unknown user should see 0 bids, saw %s', v_n);
  select count(*) into v_n from carsenda.vehicles;
  assert v_n = 0, format('R19 unknown user should see 0 vehicles, saw %s', v_n);

  raise notice 'rls unknown user: 3/3 PASS';
end $$;
reset role;

-- ================================= ADMIN ===============================
set role authenticated;
set request.jwt.claims = '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}';

do $$
declare v_n integer;
begin
  select count(*) into v_n from carsenda.shipments;
  assert v_n = 2, format('R20 admin should see all 2 shipments, saw %s', v_n);
  select count(*) into v_n from carsenda.bids;
  assert v_n = 2, format('R21 admin should see all 2 bids, saw %s', v_n);

  raise notice 'rls admin: 2/2 PASS';
end $$;
reset role;

-- ==================== WRITE ISOLATION (not just reads) =================
set role authenticated;
set request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

do $$
declare v_n integer;
begin
  -- A carrier must not be able to place a bid on behalf of another carrier.
  begin
    insert into carsenda.bids (shipment_id, carrier_id, amount_cents)
    values ('dddddddd-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000002', 1000);
    assert false, 'R22 carrier1 wrote a bid as carrier2';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlerrm like '%row-level security%' then null; else raise; end if;
  end;

  -- A carrier must not be able to rewrite a competitor's bid amount.
  update carsenda.bids set amount_cents = 1
   where carrier_id = 'aaaaaaaa-0000-0000-0000-000000000002';
  get diagnostics v_n = row_count;
  assert v_n = 0, format('R23 carrier1 updated %s competitor bid rows', v_n);

  raise notice 'rls write isolation: 2/2 PASS';
end $$;
reset role;

-- Confirm the competitor bid is untouched after the write attempts.
do $$
declare v_amt bigint;
begin
  select amount_cents into v_amt from carsenda.bids
   where id = 'eeeeeeee-0000-0000-0000-000000000002';
  assert v_amt = 235000, format('R24 competitor bid was mutated to %s', v_amt);
  raise notice 'rls post-write integrity: 1/1 PASS';
end $$;
