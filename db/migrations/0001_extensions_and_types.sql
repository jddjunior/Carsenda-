-- 0001_extensions_and_types.sql
-- Extensions, schema and domain enums.
-- Supabase-compatible: does not create the auth schema (Supabase provides it).

create extension if not exists postgis;
create extension if not exists pgcrypto;
create extension if not exists citext;

create schema if not exists carsenda;

-- Roles a platform user can hold.
do $$ begin
  create type carsenda.user_role as enum ('shipper','carrier','dispatcher','admin');
exception when duplicate_object then null; end $$;

-- A carrier's operating authority, mirrored from FMCSA.
do $$ begin
  create type carsenda.authority_status as enum ('pending','active','suspended','revoked');
exception when duplicate_object then null; end $$;

do $$ begin
  create type carsenda.carrier_member_role as enum ('owner','dispatcher','driver');
exception when duplicate_object then null; end $$;

-- Vehicle class drives the quote multiplier.
do $$ begin
  create type carsenda.vehicle_class as enum ('sedan','suv','pickup','oversized');
exception when duplicate_object then null; end $$;

do $$ begin
  create type carsenda.transport_type as enum ('open','enclosed');
exception when duplicate_object then null; end $$;

-- Shipment lifecycle. Ordering is meaningful; transitions are enforced in 0002.
do $$ begin
  create type carsenda.shipment_status as enum (
    'quoted','open_for_bids','assigned','picked_up','in_transit','delivered','cancelled'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type carsenda.bid_status as enum ('open','accepted','rejected','withdrawn');
exception when duplicate_object then null; end $$;

do $$ begin
  create type carsenda.report_phase as enum ('pickup','delivery');
exception when duplicate_object then null; end $$;

do $$ begin
  create type carsenda.payment_status as enum ('authorized','captured','refunded','failed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type carsenda.payout_status as enum ('pending','released','paid','failed');
exception when duplicate_object then null; end $$;
