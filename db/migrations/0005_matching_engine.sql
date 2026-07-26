-- 0005_matching_engine.sql
-- Carrier matching. The eligibility filter is a liability control, not a
-- ranking preference: a carrier without active authority or with lapsed
-- insurance is never returned, regardless of score.

create or replace function carsenda.match_carriers(
  p_shipment_id uuid,
  p_limit       integer default 10
) returns table (
  carrier_id          uuid,
  legal_name          text,
  route_id            uuid,
  origin_deviation_mi numeric,
  dest_deviation_mi   numeric,
  fit_score           numeric
)
language sql stable as $$
  with s as (
    select * from carsenda.shipments where id = p_shipment_id
  ),
  eligible as (
    select
      c.id  as carrier_id,
      c.legal_name,
      r.id  as route_id,
      st_distance(r.origin,      s.origin)      as origin_dev_m,
      st_distance(r.destination, s.destination) as dest_dev_m,
      r.corridor_m,
      c.rating,
      c.acceptance_rate
    from s
    join carsenda.carrier_routes r
      on r.equipment = s.transport_type
     and s.pickup_window_start between r.available_from and r.available_to
     -- Corridor intersection: both endpoints within the carrier's tolerance.
     and st_dwithin(r.origin,      s.origin,      r.corridor_m)
     and st_dwithin(r.destination, s.destination, r.corridor_m)
    join carsenda.carriers c
      on c.id = r.carrier_id
     -- Hard eligibility gates.
     and c.authority_status = 'active'
     and c.insurance_expires_on > s.pickup_window_end
    -- Capacity: carrier must have room on this route.
    where r.capacity > (
      select count(*)
      from carsenda.shipments a
      where a.assigned_carrier_id = c.id
        and a.status in ('assigned','picked_up','in_transit')
    )
  )
  select
    e.carrier_id,
    e.legal_name,
    e.route_id,
    round((e.origin_dev_m / 1609.344)::numeric, 1) as origin_deviation_mi,
    round((e.dest_dev_m   / 1609.344)::numeric, 1) as dest_deviation_mi,
    round((
        0.45 * (1 - least(e.origin_dev_m / e.corridor_m, 1))
      + 0.25 * (1 - least(e.dest_dev_m   / e.corridor_m, 1))
      + 0.20 * (coalesce(e.rating, 0) / 5.0)
      + 0.10 *  coalesce(e.acceptance_rate, 0)
    )::numeric, 4) as fit_score
  from eligible e
  order by fit_score desc, e.carrier_id
  limit greatest(p_limit, 1);
$$;

comment on function carsenda.match_carriers is
  'Ranked eligible carriers. Weights: 0.45 origin fit, 0.25 destination fit, '
  '0.20 rating, 0.10 acceptance rate. Eligibility gates are absolute.';

-- Append an event to the outbox. Used by application code and triggers.
create or replace function carsenda.emit_event(
  p_aggregate    text,
  p_aggregate_id uuid,
  p_event_type   text,
  p_payload      jsonb,
  p_version      smallint default 1
) returns bigint
language sql volatile as $$
  insert into carsenda.events (aggregate, aggregate_id, event_type, version, payload)
  values (p_aggregate, p_aggregate_id, p_event_type, p_version, p_payload)
  returning id;
$$;

-- Shipment status changes are emitted automatically so no code path can
-- mutate lifecycle state without producing an event.
create or replace function carsenda.tg_shipment_status_event()
returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    perform carsenda.emit_event(
      'shipment', new.id, 'shipment.status_changed',
      jsonb_build_object('from', old.status, 'to', new.status,
                         'carrier_id', new.assigned_carrier_id)
    );
  elsif tg_op = 'INSERT' then
    perform carsenda.emit_event(
      'shipment', new.id, 'shipment.created',
      jsonb_build_object('status', new.status, 'shipper_id', new.shipper_id)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_shipment_status_event on carsenda.shipments;
create trigger trg_shipment_status_event
  after insert or update on carsenda.shipments
  for each row execute function carsenda.tg_shipment_status_event();
