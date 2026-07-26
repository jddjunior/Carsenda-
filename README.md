# Carsenda - backend

Database core for the Carsenda vehicle transport marketplace: schema, row level
security, the deterministic quote engine, the geospatial carrier matching engine,
and an executable test suite that proves all three.

Built against the Stage 1 gate in the Carsenda architecture build agent:
domain model, event catalogue, quote and matching engines with test vectors,
ERD, RLS policies, geospatial index strategy, and a frozen API contract.

## Status

| Component | State |
|---|---|
| Schema and constraints | Applied and tested |
| Row level security | Applied and tested, 25 isolation assertions |
| Quote engine | Deterministic, locked by 11 hand-computed vectors |
| Matching engine | Tested, 11 eligibility and ranking assertions |
| Event outbox | Trigger-emitted on shipment lifecycle |
| API contract | OpenAPI 3.1, frozen, all refs resolve |
| Hosted deployment | Not deployed - see Deploying below |

Last verified run: **47 assertions passed, exit 0**, against PostgreSQL 16.14
with PostGIS 3.4.2.

## Layout

```
db/migrations/   0001 types - 0002 tables - 0003 indexes
                 0004 quote engine - 0005 matching engine - 0006 RLS
db/seed/         deterministic fixtures with fixed UUIDs
db/test/         quote vectors - matching - RLS isolation - runner
contracts/       openapi.yaml
docs/            DOMAIN.md - EVENTS.md
```

## Running the tests

Requires PostgreSQL 16 with PostGIS 3 and a role that can create databases.

```bash
bash db/test/run_tests.sh
```

The runner drops and recreates a scratch database, applies every migration in
order, seeds fixtures, and runs the suite. Any failed assertion aborts with a
non-zero exit code.

## Design decisions

**Money is `bigint` cents.** No floating point anywhere in pricing.

**The quote engine is `IMMUTABLE`.** No `now()`, no `random()`, no table reads.
The same inputs always produce the same cents, so pricing is replayable and a
regression is provable rather than anecdotal. `test_quote_vectors.sql` asserts
`provolatile = 'i'` so the property cannot be silently dropped.

**Test vectors are hand-computed from the formula**, not captured from the
function's output. A captured vector would pass against a broken engine.

**Eligibility beats score in matching.** A carrier without active operating
authority, or whose insurance expires before the pickup window closes, is never
returned no matter how highly it rates. The fixture deliberately gives the
lapsed-insurance carrier the *highest* rating in the set so the test fails loudly
if that ordering is ever inverted.

**Authorisation lives in the database.** Every table is `FORCE ROW LEVEL
SECURITY`. Application code cannot forget a `WHERE` clause because the row filter
is not in application code. Tests execute as the `authenticated` role with a real
JWT claim set, the same path PostgREST uses.

**Bid confidentiality is a policy, not a convention.** A carrier can read its own
bid and never a competitor's. Both the read path and the write path are asserted,
including an attempt to update another carrier's bid, which must affect 0 rows.

## Local auth shim

`db/test/shim_auth.sql` creates the `auth` schema, `auth.uid()`, and the
`anon`/`authenticated` roles so the policies can be executed in a plain Postgres
container. **It is test-only and must not be applied to Supabase**, which
provides all of these natively. The runner applies it; the migrations do not
reference it.

## Deploying

The migrations are Supabase-compatible and apply in filename order. No hosted
project has been provisioned - every existing Supabase project on this account is
paused, and creating a new one is a billing decision.

To deploy:

1. Create or resume a Supabase project with the PostGIS extension available.
2. Apply `db/migrations/*.sql` in order.
3. Do **not** apply the auth shim or the test fixtures.
4. Confirm `carsenda.match_carriers` and `carsenda.quote_cents` exist and that
   RLS is enabled on all 12 tables.

## Not yet built

Stage 2 and beyond, per the architecture document: Stripe Connect payments and
payouts, Twilio and Resend notification fabric, FMCSA authority verification,
live tracking ingestion, and the HTTP layer implementing `contracts/openapi.yaml`.
The `payments` and `payouts` tables exist and are policy-protected, but no
integration writes to them yet.
