-- 0004_quote_engine.sql
-- Deterministic pricing. Every function here is IMMUTABLE: no now(), no random,
-- no table reads. The same inputs must always produce the same cents, because a
-- silent pricing regression is a revenue incident, not a bug.
--
-- Pricing is locked by test vectors in db/test/test_quote_vectors.sql.
-- Changing any constant below WILL fail those tests. That is intentional:
-- a price change must be an explicit, reviewed vector update.

-- Road distance approximation. Great-circle distance inflated by a highway
-- circuity factor; deterministic and adequate for quoting. Actual dispatch
-- mileage comes from the routing provider at assignment time.
create or replace function carsenda.lane_distance_mi(
  p_origin geography,
  p_destination geography
) returns numeric
language sql immutable strict as $$
  select round(((st_distance(p_origin, p_destination) / 1609.344) * 1.17)::numeric, 1);
$$;

comment on function carsenda.lane_distance_mi is
  'Great-circle miles x 1.17 highway circuity factor. IMMUTABLE.';

-- Per-mile rate declines with distance: long hauls amortise deadhead.
create or replace function carsenda.rate_per_mile(p_distance_mi numeric)
returns numeric
language sql immutable strict as $$
  select case
    when p_distance_mi <  500 then 1.75
    when p_distance_mi < 1000 then 1.15
    when p_distance_mi < 1500 then 0.92
    when p_distance_mi < 2000 then 0.78
    else                           0.68
  end::numeric;
$$;

create or replace function carsenda.class_multiplier(p_class carsenda.vehicle_class)
returns numeric
language sql immutable strict as $$
  select case p_class
    when 'sedan'     then 1.00
    when 'suv'       then 1.15
    when 'pickup'    then 1.25
    when 'oversized' then 1.60
  end::numeric;
$$;

create or replace function carsenda.transport_multiplier(p_type carsenda.transport_type)
returns numeric
language sql immutable strict as $$
  select case p_type when 'open' then 1.00 when 'enclosed' then 1.40 end::numeric;
$$;

-- Seasonal demand. Q1 is snowbird northbound; summer is relocation season.
create or replace function carsenda.season_multiplier(p_month smallint)
returns numeric
language sql immutable strict as $$
  select case
    when p_month in (1,2,3) then 1.08
    when p_month in (6,7,8) then 1.05
    else 1.00
  end::numeric;
$$;

-- Core quote. Returns integer cents.
create or replace function carsenda.quote_cents(
  p_distance_mi   numeric,
  p_class         carsenda.vehicle_class,
  p_transport     carsenda.transport_type,
  p_operable      boolean,
  p_pickup_month  smallint
) returns bigint
language plpgsql immutable strict as $$
declare
  v_base  numeric;
  v_total numeric;
begin
  if p_distance_mi < 0 then
    raise exception 'distance must be non-negative, got %', p_distance_mi;
  end if;
  if p_pickup_month not between 1 and 12 then
    raise exception 'pickup month must be 1-12, got %', p_pickup_month;
  end if;

  v_base := p_distance_mi * carsenda.rate_per_mile(p_distance_mi);

  -- Minimum haul floor: short moves do not cover dispatch cost below this.
  if v_base < 395 then
    v_base := 395;
  end if;

  v_total := v_base
           * carsenda.class_multiplier(p_class)
           * carsenda.transport_multiplier(p_transport)
           * carsenda.season_multiplier(p_pickup_month);

  -- Inoperable vehicles need a winch. Flat fee, applied after multipliers.
  if not p_operable then
    v_total := v_total + 150;
  end if;

  return round(v_total * 100)::bigint;
end;
$$;

comment on function carsenda.quote_cents is
  'Deterministic quote in cents. Locked by db/test/test_quote_vectors.sql.';

-- Convenience wrapper: quote directly from geography and vehicle attributes.
create or replace function carsenda.quote_lane(
  p_origin      geography,
  p_destination geography,
  p_class       carsenda.vehicle_class,
  p_transport   carsenda.transport_type,
  p_operable    boolean,
  p_pickup_date date
) returns table (distance_mi numeric, quote_cents bigint)
language sql immutable strict as $$
  select d.mi,
         carsenda.quote_cents(d.mi, p_class, p_transport, p_operable,
                              extract(month from p_pickup_date)::smallint)
  from (select carsenda.lane_distance_mi(p_origin, p_destination) as mi) d;
$$;
