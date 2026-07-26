# Event catalogue

Append-only outbox in `carsenda.events`. The envelope is versioned so consumers
can be upgraded independently of producers.

| Field | Meaning |
|---|---|
| `aggregate` | Aggregate root, e.g. `shipment` |
| `aggregate_id` | UUID of the aggregate |
| `event_type` | Dotted name, e.g. `shipment.status_changed` |
| `version` | Envelope version, starts at 1 |
| `payload` | JSONB body, shape depends on `event_type` |
| `occurred_at` | Server timestamp |

## Emitted today

### `shipment.created` v1
Fired by trigger on insert.

```json
{ "status": "quoted", "shipper_id": "uuid" }
```

### `shipment.status_changed` v1
Fired by trigger on any status transition. Lifecycle state cannot change without
producing this event, because the trigger is on the table rather than in
application code.

```json
{ "from": "open_for_bids", "to": "assigned", "carrier_id": "uuid|null" }
```

## Planned, Stage 3

`bid.placed`, `bid.accepted`, `payment.authorized`, `payment.captured`,
`payout.released`, `condition_report.recorded`, `carrier.authority_changed`.

## Consumer rules

1. Consumers are idempotent; events may be delivered more than once.
2. An unknown `event_type` is ignored, not an error.
3. A new required payload field requires a `version` bump.
4. Read access is scoped by RLS: a caller sees only events for aggregates it can
   already access.
