# Domain model

12 tables. Money is `bigint` cents. Geography is SRID 4326, so PostGIS distance
returns metres.

## Aggregates

**profiles** - platform user, mirrors `auth.users.id`. Role: shipper, carrier,
dispatcher, admin.

**carriers** - carrier company. Holds DOT and MC numbers, `authority_status`
mirrored from FMCSA, insurance expiry, rating and acceptance rate. Dispatchable
only when authority is `active` and insurance outlasts the pickup window.

**carrier_members** - user to carrier membership. Drives every carrier-side RLS
policy via `carsenda.my_carrier_ids()`.

**carrier_routes** - declared haul corridors: origin, destination, a
`corridor_m` deviation tolerance, an availability window, equipment type and
capacity. This is the table the matching engine searches.

**vehicles** - owned by a shipper. Class drives the quote multiplier;
operability drives the winch fee.

**shipments** - the central aggregate. Lifecycle: `quoted` to `open_for_bids` to
`assigned` to `picked_up` to `in_transit` to `delivered`, or `cancelled`. A check
constraint forbids an assigned-or-later shipment without a carrier.

**bids** - one live bid per carrier per shipment, enforced by a unique index.

**condition_reports** - digital bill of lading. Exactly one per phase, at least
one photo required by constraint.

**payments and payouts** - milestone money. Card data never lands here; Stripe
holds it and this schema stores only references, keeping PCI scope at SAQ-A.

**reviews** - two-sided, one per author per shipment.

**events** - append-only outbox.

## The matching query

The hot path, run on every quote:

1. Filter routes by equipment and availability window (composite index).
2. Intersect both endpoints against the corridor with `ST_DWithin` (GIST index).
3. Apply the hard eligibility gates on the carrier.
4. Exclude carriers already at route capacity.
5. Rank: 0.45 origin fit + 0.25 destination fit + 0.20 rating + 0.10 acceptance.

Steps 1 through 4 are absolute. Step 5 only orders what survives them.
