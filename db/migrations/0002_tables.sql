-- 0002_tables.sql
-- Core transactional tables. Money is always bigint cents, never float.
-- Geography is 4326 so PostGIS distance returns metres.

create table if not exists carsenda.profiles (
  id          uuid primary key,                       -- mirrors auth.users.id
  role        carsenda.user_role not null default 'shipper',
  full_name   text,
  email       citext unique,
  phone       text,
  created_at  timestamptz not null default now()
);

create table if not exists carsenda.carriers (
  id                    uuid primary key default gen_random_uuid(),
  legal_name            text not null,
  dot_number            text unique,
  mc_number             text unique,
  authority_status      carsenda.authority_status not null default 'pending',
  insurance_expires_on  date,
  cargo_insurance_cents bigint check (cargo_insurance_cents >= 0),
  rating                numeric(3,2) check (rating between 0 and 5),
  acceptance_rate       numeric(5,4) check (acceptance_rate between 0 and 1),
  home_base             geography(Point,4326),
  created_at            timestamptz not null default now()
);

-- A carrier is dispatchable only with active authority AND unexpired insurance.
-- Enforced in the matching engine and asserted by tests.
create table if not exists carsenda.carrier_members (
  carrier_id  uuid not null references carsenda.carriers(id) on delete cascade,
  user_id     uuid not null references carsenda.profiles(id) on delete cascade,
  member_role carsenda.carrier_member_role not null default 'driver',
  primary key (carrier_id, user_id)
);

-- Declared haul corridors. corridor_m is the deviation the carrier will accept.
create table if not exists carsenda.carrier_routes (
  id             uuid primary key default gen_random_uuid(),
  carrier_id     uuid not null references carsenda.carriers(id) on delete cascade,
  origin         geography(Point,4326) not null,
  destination    geography(Point,4326) not null,
  corridor_m     integer not null default 120000 check (corridor_m between 1000 and 500000),
  available_from date not null,
  available_to   date not null,
  equipment      carsenda.transport_type not null default 'open',
  capacity       smallint not null default 7 check (capacity between 1 and 12),
  constraint carrier_routes_window_valid check (available_to >= available_from)
);

create table if not exists carsenda.vehicles (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references carsenda.profiles(id) on delete cascade,
  year          smallint check (year between 1900 and 2100),
  make          text not null,
  model         text not null,
  vehicle_class carsenda.vehicle_class not null,
  operable      boolean not null default true,
  vin           text,
  created_at    timestamptz not null default now()
);

create table if not exists carsenda.shipments (
  id                  uuid primary key default gen_random_uuid(),
  shipper_id          uuid not null references carsenda.profiles(id) on delete restrict,
  vehicle_id          uuid not null references carsenda.vehicles(id) on delete restrict,
  origin              geography(Point,4326) not null,
  destination         geography(Point,4326) not null,
  origin_label        text not null,
  destination_label   text not null,
  pickup_window_start date not null,
  pickup_window_end   date not null,
  transport_type      carsenda.transport_type not null default 'open',
  status              carsenda.shipment_status not null default 'quoted',
  quoted_cents        bigint check (quoted_cents > 0),
  distance_mi         numeric(7,1) check (distance_mi >= 0),
  assigned_carrier_id uuid references carsenda.carriers(id) on delete restrict,
  accepted_bid_id     uuid,
  created_at          timestamptz not null default now(),
  constraint shipments_window_valid check (pickup_window_end >= pickup_window_start),
  -- An assigned-or-later shipment must name a carrier. Prevents orphaned dispatch.
  constraint shipments_assignment_coherent check (
    (status in ('quoted','open_for_bids','cancelled') and assigned_carrier_id is null)
    or (status in ('assigned','picked_up','in_transit','delivered') and assigned_carrier_id is not null)
  )
);

create table if not exists carsenda.bids (
  id           uuid primary key default gen_random_uuid(),
  shipment_id  uuid not null references carsenda.shipments(id) on delete cascade,
  carrier_id   uuid not null references carsenda.carriers(id) on delete cascade,
  amount_cents bigint not null check (amount_cents > 0),
  status       carsenda.bid_status not null default 'open',
  created_at   timestamptz not null default now(),
  unique (shipment_id, carrier_id)          -- one live bid per carrier per shipment
);

alter table carsenda.shipments
  drop constraint if exists shipments_accepted_bid_fk;
alter table carsenda.shipments
  add constraint shipments_accepted_bid_fk
  foreign key (accepted_bid_id) references carsenda.bids(id) on delete set null;

create table if not exists carsenda.condition_reports (
  id                uuid primary key default gen_random_uuid(),
  shipment_id       uuid not null references carsenda.shipments(id) on delete cascade,
  phase             carsenda.report_phase not null,
  recorded_by       uuid not null references carsenda.profiles(id) on delete restrict,
  odometer          integer check (odometer >= 0),
  damages           jsonb not null default '[]'::jsonb,
  photo_paths       text[] not null default '{}',
  signed_by_shipper boolean not null default false,
  recorded_at       timestamptz not null default now(),
  unique (shipment_id, phase),               -- exactly one report per phase
  constraint condition_reports_damages_is_array check (jsonb_typeof(damages) = 'array'),
  -- A bill of lading without photographic evidence is not a defensible record.
  constraint condition_reports_photos_present check (array_length(photo_paths,1) >= 1)
);

create table if not exists carsenda.payments (
  id            uuid primary key default gen_random_uuid(),
  shipment_id   uuid not null references carsenda.shipments(id) on delete restrict,
  amount_cents  bigint not null check (amount_cents > 0),
  status        carsenda.payment_status not null default 'authorized',
  stripe_ref    text unique,                 -- Stripe holds card data; PCI scope stays SAQ-A
  authorized_at timestamptz not null default now(),
  captured_at   timestamptz,
  constraint payments_capture_coherent check (
    (status = 'captured' and captured_at is not null) or (status <> 'captured')
  )
);

create table if not exists carsenda.payouts (
  id           uuid primary key default gen_random_uuid(),
  shipment_id  uuid not null references carsenda.shipments(id) on delete restrict,
  carrier_id   uuid not null references carsenda.carriers(id) on delete restrict,
  amount_cents bigint not null check (amount_cents > 0),
  status       carsenda.payout_status not null default 'pending',
  stripe_ref   text unique,
  released_at  timestamptz,
  unique (shipment_id, carrier_id)
);

create table if not exists carsenda.reviews (
  id          uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references carsenda.shipments(id) on delete cascade,
  author_id   uuid not null references carsenda.profiles(id) on delete cascade,
  subject_carrier_id uuid references carsenda.carriers(id) on delete cascade,
  rating      smallint not null check (rating between 1 and 5),
  body        text,
  created_at  timestamptz not null default now(),
  unique (shipment_id, author_id)
);

-- Append-only event outbox. Versioned envelope per the event catalogue.
create table if not exists carsenda.events (
  id           bigserial primary key,
  aggregate    text not null,
  aggregate_id uuid not null,
  event_type   text not null,
  version      smallint not null default 1,
  payload      jsonb not null,
  occurred_at  timestamptz not null default now()
);
