-- 0003_indexes.sql
-- Index strategy is driven by the matching query, which runs on every quote
-- and is the hottest path in the system.

-- Geospatial: GIST on geography powers ST_DWithin corridor intersection.
create index if not exists idx_carrier_routes_origin_gist
  on carsenda.carrier_routes using gist (origin);
create index if not exists idx_carrier_routes_dest_gist
  on carsenda.carrier_routes using gist (destination);
create index if not exists idx_shipments_origin_gist
  on carsenda.shipments using gist (origin);
create index if not exists idx_shipments_dest_gist
  on carsenda.shipments using gist (destination);

-- Matching pre-filters on equipment and availability window before the
-- geospatial test, so this composite short-circuits most of the table.
create index if not exists idx_carrier_routes_equipment_window
  on carsenda.carrier_routes (equipment, available_from, available_to);

create index if not exists idx_carrier_routes_carrier
  on carsenda.carrier_routes (carrier_id);

-- Dispatchability filter: only active authority is ever matched.
create index if not exists idx_carriers_dispatchable
  on carsenda.carriers (authority_status, insurance_expires_on)
  where authority_status = 'active';

create index if not exists idx_shipments_shipper on carsenda.shipments (shipper_id);
create index if not exists idx_shipments_carrier on carsenda.shipments (assigned_carrier_id);
-- Carrier marketplace browse: open shipments only.
create index if not exists idx_shipments_open
  on carsenda.shipments (status, pickup_window_start)
  where status = 'open_for_bids';

create index if not exists idx_bids_shipment on carsenda.bids (shipment_id);
create index if not exists idx_bids_carrier   on carsenda.bids (carrier_id);
create index if not exists idx_vehicles_owner on carsenda.vehicles (owner_id);
create index if not exists idx_carrier_members_user on carsenda.carrier_members (user_id);
create index if not exists idx_condition_reports_shipment on carsenda.condition_reports (shipment_id);
create index if not exists idx_payments_shipment on carsenda.payments (shipment_id);
create index if not exists idx_payouts_carrier on carsenda.payouts (carrier_id);

-- Event replay by aggregate.
create index if not exists idx_events_aggregate
  on carsenda.events (aggregate, aggregate_id, id);
