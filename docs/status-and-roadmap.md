# Status and roadmap

[← Back to README](../README.md)

## Known limitations

Read each submodule's own current list rather than trusting a summary here, — start with
[`i-dolly-backend/README.md#known-limitations`](https://github.com/TranXuanAnh930/i-dolly-backend#known-limitations)
and its `docs/project_status.md`. In short: this is a portfolio project verified mostly through
static analysis and targeted live-DB sessions rather than continuous production traffic, in both
halves — treat it accordingly.

One specific gap worth naming directly rather than leaving buried in that list: **no sweep job for
expired unpaid lottery-won tickets.** A fan who wins and never pays before `payment_deadline_at`
should have that reserved seat released back to the pool — nothing does this today. The only place
`payment_deadline_at` is even checked is a lazy discovery inside PayPal payment finalization, which
only fires if someone happens to hit that exact path for that exact ticket; deliberately excluded
from this project's concurrency test suite too, since there's no sweep-job code yet to race. Full
detail: `i-dolly-backend/docs/project_status.md` §8.

## Future work

Flagged as planned, not started — named here rather than designed speculatively:

- **OLAP migration** — the ETL/analytics pipeline flagged as not-yet-started in
  `i-dolly-backend/docs/project_status.md` §5: an event-sourced outbox (`domain_events`: type,
  payload, occurred_at, processed) written in the same transaction as each business event (ticket
  purchases, lottery entries/draws, payment/shipment status changes), transformed downstream into
  analytics-friendly fact tables (`fact_sales_by_concert`, `fact_lottery_conversion`,
  `fact_fan_activity`) — either a separate schema in the same Postgres instance or a dedicated OLAP
  store, depending on scope once the OLTP shape settles further.
- **Go benchmarking** — a standalone Go load-testing tool against the FastAPI backend, to get real
  concurrent-throughput/latency numbers (checkout's stock-lock contention, the lottery draw, the
  rate limiter under burst traffic) rather than relying on `pytest`'s correctness-only coverage.
  Not started; which endpoints and load profile to target is still undecided.
