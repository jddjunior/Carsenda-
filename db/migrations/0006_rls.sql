-- 0006_rls.sql
-- Tenancy and authorisation are enforced at the row, not in application code.
-- Every table below is FORCE-enabled so even the table owner is subject to policy.

-- Helper functions are SECURITY DEFINER to read membership without recursing
-- into the policies that depend on them. They are read-only by construction.

create or replace function carsenda.current_uid()
returns uuid language sql stable as $$
  select auth.uid();
$$;

create or replace function carsenda.is_admin()
returns boolean
language sql stable security definer set search_path = carsenda, public as $$
  select exists (
    select 1 from carsenda.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

-- Carrier organisations the current user belongs to.
create or replace function carsenda.my_carrier_ids()
returns setof uuid
language sql stable security definer set search_path = carsenda, public as $$
  select cm.carrier_id from carsenda.carrier_members cm
  where cm.user_id = auth.uid();
$$;

-- Does the current user belong to the carrier assigned to this shipment?
create or replace function carsenda.can_access_shipment(p_shipment_id uuid)
returns boolean
language sql stable security definer set search_path = carsenda, public as $$
  select exists (
    select 1 from carsenda.shipments s
    where s.id = p_shipment_id
      and (
        s.shipper_id = auth.uid()
        or s.assigned_carrier_id in (select carsenda.my_carrier_ids())
      )
  );
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'profiles','carriers','carrier_members','carrier_routes','vehicles',
    'shipments','bids','condition_reports','payments','payouts','reviews','events'
  ] loop
    execute format('alter table carsenda.%I enable row level security', t);
    execute format('alter table carsenda.%I force row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- profiles
drop policy if exists profiles_select_self on carsenda.profiles;
create policy profiles_select_self on carsenda.profiles
  for select using (id = auth.uid() or carsenda.is_admin());

drop policy if exists profiles_update_self on carsenda.profiles;
create policy profiles_update_self on carsenda.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- ---------------------------------------------------------------- carriers
-- Carrier identity is marketplace-public to authenticated users: a shipper must
-- be able to evaluate who is bidding on their vehicle.
drop policy if exists carriers_select_authenticated on carsenda.carriers;
create policy carriers_select_authenticated on carsenda.carriers
  for select using (auth.uid() is not null);

drop policy if exists carriers_update_members on carsenda.carriers;
create policy carriers_update_members on carsenda.carriers
  for update using (id in (select carsenda.my_carrier_ids()) or carsenda.is_admin())
  with check  (id in (select carsenda.my_carrier_ids()) or carsenda.is_admin());

-- ------------------------------------------------------- carrier_members
drop policy if exists carrier_members_select_own on carsenda.carrier_members;
create policy carrier_members_select_own on carsenda.carrier_members
  for select using (
    user_id = auth.uid()
    or carrier_id in (select carsenda.my_carrier_ids())
    or carsenda.is_admin()
  );

-- -------------------------------------------------------- carrier_routes
drop policy if exists carrier_routes_select on carsenda.carrier_routes;
create policy carrier_routes_select on carsenda.carrier_routes
  for select using (
    carrier_id in (select carsenda.my_carrier_ids()) or carsenda.is_admin()
  );

drop policy if exists carrier_routes_write on carsenda.carrier_routes;
create policy carrier_routes_write on carsenda.carrier_routes
  for all using (carrier_id in (select carsenda.my_carrier_ids()) or carsenda.is_admin())
  with check (carrier_id in (select carsenda.my_carrier_ids()) or carsenda.is_admin());

-- ---------------------------------------------------------------- vehicles
drop policy if exists vehicles_owner_all on carsenda.vehicles;
create policy vehicles_owner_all on carsenda.vehicles
  for all using (owner_id = auth.uid() or carsenda.is_admin())
  with check (owner_id = auth.uid() or carsenda.is_admin());

-- A carrier must see the vehicle attached to a shipment it can access.
drop policy if exists vehicles_select_via_shipment on carsenda.vehicles;
create policy vehicles_select_via_shipment on carsenda.vehicles
  for select using (
    exists (
      select 1 from carsenda.shipments s
      where s.vehicle_id = vehicles.id
        and s.assigned_carrier_id in (select carsenda.my_carrier_ids())
    )
  );

-- --------------------------------------------------------------- shipments
drop policy if exists shipments_shipper_all on carsenda.shipments;
create policy shipments_shipper_all on carsenda.shipments
  for all using (shipper_id = auth.uid() or carsenda.is_admin())
  with check (shipper_id = auth.uid() or carsenda.is_admin());

-- Marketplace browse: any carrier member may see shipments open for bidding.
drop policy if exists shipments_carrier_browse on carsenda.shipments;
create policy shipments_carrier_browse on carsenda.shipments
  for select using (
    status = 'open_for_bids'
    and exists (select 1 from carsenda.my_carrier_ids())
  );

-- Assigned carrier retains access through delivery.
drop policy if exists shipments_carrier_assigned on carsenda.shipments;
create policy shipments_carrier_assigned on carsenda.shipments
  for select using (assigned_carrier_id in (select carsenda.my_carrier_ids()));

drop policy if exists shipments_carrier_progress on carsenda.shipments;
create policy shipments_carrier_progress on carsenda.shipments
  for update using (assigned_carrier_id in (select carsenda.my_carrier_ids()))
  with check  (assigned_carrier_id in (select carsenda.my_carrier_ids()));

-- -------------------------------------------------------------------- bids
drop policy if exists bids_carrier_all on carsenda.bids;
create policy bids_carrier_all on carsenda.bids
  for all using (carrier_id in (select carsenda.my_carrier_ids()) or carsenda.is_admin())
  with check (carrier_id in (select carsenda.my_carrier_ids()) or carsenda.is_admin());

-- Shipper sees bids placed on their own shipments, but not other carriers'
-- bids on other shipments.
drop policy if exists bids_shipper_select on carsenda.bids;
create policy bids_shipper_select on carsenda.bids
  for select using (
    exists (
      select 1 from carsenda.shipments s
      where s.id = bids.shipment_id and s.shipper_id = auth.uid()
    )
  );

-- ------------------------------------------------------- condition_reports
drop policy if exists condition_reports_access on carsenda.condition_reports;
create policy condition_reports_access on carsenda.condition_reports
  for all using (carsenda.can_access_shipment(shipment_id) or carsenda.is_admin())
  with check (carsenda.can_access_shipment(shipment_id) or carsenda.is_admin());

-- ---------------------------------------------------------------- payments
-- Payment records belong to the shipper. Carriers see payouts, never payments.
drop policy if exists payments_shipper_select on carsenda.payments;
create policy payments_shipper_select on carsenda.payments
  for select using (
    exists (
      select 1 from carsenda.shipments s
      where s.id = payments.shipment_id and s.shipper_id = auth.uid()
    ) or carsenda.is_admin()
  );

-- ----------------------------------------------------------------- payouts
drop policy if exists payouts_carrier_select on carsenda.payouts;
create policy payouts_carrier_select on carsenda.payouts
  for select using (
    carrier_id in (select carsenda.my_carrier_ids()) or carsenda.is_admin()
  );

-- ----------------------------------------------------------------- reviews
drop policy if exists reviews_select_all on carsenda.reviews;
create policy reviews_select_all on carsenda.reviews
  for select using (auth.uid() is not null);

drop policy if exists reviews_author_write on carsenda.reviews;
create policy reviews_author_write on carsenda.reviews
  for all using (author_id = auth.uid() or carsenda.is_admin())
  with check (author_id = auth.uid() or carsenda.is_admin());

-- ------------------------------------------------------------------ events
-- Events are readable only for aggregates the caller can already access.
drop policy if exists events_scoped_select on carsenda.events;
create policy events_scoped_select on carsenda.events
  for select using (
    carsenda.is_admin()
    or (aggregate = 'shipment' and carsenda.can_access_shipment(aggregate_id))
  );

-- Grants. Policies do the authorising; grants open the surface.
grant usage on schema carsenda to authenticated;
grant select, insert, update, delete on all tables in schema carsenda to authenticated;
grant usage, select on all sequences in schema carsenda to authenticated;
grant execute on all functions in schema carsenda to authenticated;
