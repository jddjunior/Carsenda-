-- shim_auth.sql
-- LOCAL TEST ONLY. Never applied to Supabase - Supabase already provides the
-- auth schema, auth.uid(), and the anon/authenticated roles. This file exists
-- so the RLS policies can be executed and proven in a plain Postgres container
-- with identical semantics.

create schema if not exists auth;

-- Mirrors Supabase: reads the 'sub' claim from the request JWT claims GUC.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid;
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'role', 'anon');
$$;

do $$ begin
  create role anon nologin;
exception when duplicate_object then null; end $$;

do $$ begin
  create role authenticated nologin;
exception when duplicate_object then null; end $$;

grant usage on schema auth to anon, authenticated;
grant execute on all functions in schema auth to anon, authenticated;
