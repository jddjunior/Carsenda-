-- test_quote_vectors.sql
-- Locked pricing vectors. Every expected value below is derived by hand from
-- the documented formula, NOT read back from the function. If the engine and
-- these vectors disagree, one of them is wrong and the build stops.
--
-- Formula: base = distance x rate_per_mile(distance), floored at 395
--          total = base x class x transport x season, + 150 if inoperable
--          cents = round(total x 100)

\set ON_ERROR_STOP on

do $$
declare
  v_got bigint;
  v_d   numeric;
begin
  -- V1  3300mi sedan/open/operable/Sep
  --     rate 0.68 -> base 2244.00 -> x1.00 x1.00 x1.00 = 2244.00
  v_got := carsenda.quote_cents(3300.0,'sedan','open',true,9::smallint);
  assert v_got = 224400, format('V1 expected 224400 got %s', v_got);

  -- V2  1550mi pickup/enclosed/INOPERABLE/Sep
  --     rate 0.78 -> base 1209.00 -> x1.25 = 1511.25 -> x1.40 = 2115.75
  --     x1.00 season, +150 winch = 2265.75
  v_got := carsenda.quote_cents(1550.0,'pickup','enclosed',false,9::smallint);
  assert v_got = 226575, format('V2 expected 226575 got %s', v_got);

  -- V3  100mi sedan/open/operable/May -> below minimum haul, floors at 395
  v_got := carsenda.quote_cents(100.0,'sedan','open',true,5::smallint);
  assert v_got = 39500, format('V3 expected 39500 got %s', v_got);

  -- V4  1000mi suv/open/operable/Feb
  --     rate 0.92 -> base 920.00 -> x1.15 = 1058.00 -> x1.08 season = 1142.64
  v_got := carsenda.quote_cents(1000.0,'suv','open',true,2::smallint);
  assert v_got = 114264, format('V4 expected 114264 got %s', v_got);

  -- V5  500mi oversized/enclosed/INOPERABLE/Jul
  --     rate 1.15 -> base 575.00 -> x1.60 = 920.00 -> x1.40 = 1288.00
  --     x1.05 season = 1352.40, +150 = 1502.40
  v_got := carsenda.quote_cents(500.0,'oversized','enclosed',false,7::smallint);
  assert v_got = 150240, format('V5 expected 150240 got %s', v_got);

  -- V6  Distance band boundary at 500mi. 499.9 uses 1.75, 500.0 uses 1.15.
  --     499.9 x 1.75 = 874.825 -> 87482.5 -> rounds half away from zero -> 87483
  v_got := carsenda.quote_cents(499.9,'sedan','open',true,5::smallint);
  assert v_got = 87483, format('V6a expected 87483 got %s', v_got);
  v_got := carsenda.quote_cents(500.0,'sedan','open',true,5::smallint);
  assert v_got = 57500, format('V6b expected 57500 got %s', v_got);

  -- V7  Crossing the band boundary must REDUCE the price. Guards against a
  --     regression where a longer haul costs more than a shorter one.
  assert carsenda.quote_cents(500.0,'sedan','open',true,5::smallint)
       < carsenda.quote_cents(499.9,'sedan','open',true,5::smallint),
    'V7 band boundary is not monotonic';

  -- V8  Determinism: repeated calls are byte-identical.
  assert carsenda.quote_cents(1234.5,'suv','enclosed',false,3::smallint)
       = carsenda.quote_cents(1234.5,'suv','enclosed',false,3::smallint),
    'V8 quote is not deterministic';

  -- V9  Input validation.
  begin
    v_got := carsenda.quote_cents(-1,'sedan','open',true,5::smallint);
    assert false, 'V9 negative distance should have raised';
  exception when others then null; end;

  begin
    v_got := carsenda.quote_cents(100,'sedan','open',true,13::smallint);
    assert false, 'V9 month 13 should have raised';
  exception when others then null; end;

  -- V10 Distance helper: Miami -> Seattle great-circle x1.17 circuity.
  --     True great-circle is ~2734mi; x1.17 puts the road estimate near 3199.
  v_d := carsenda.lane_distance_mi(
           st_point(-80.1918,25.7617)::geography,
           st_point(-122.3321,47.6062)::geography);
  assert v_d between 3100 and 3300, format('V10 distance out of range: %s', v_d);

  -- V11 Functions must be IMMUTABLE, otherwise the engine is not replayable.
  assert (select p.provolatile from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
          where n.nspname='carsenda' and p.proname='quote_cents') = 'i',
    'V11 quote_cents is not IMMUTABLE';

  raise notice 'quote vectors: 11/11 PASS';
end $$;
