# Architecture and data flow

[← Back to README](../README.md)

## Architecture

```
┌────────────────────────┐   HTTP/REST   ┌──────────────────────────┐
│        Frontend          │ ───────────▶ │         Backend           │
│  Vue 3 + Vite + Pinia    │               │   FastAPI (Python 3.12)  │
│  (i-dolly-frontend)      │               │   (i-dolly-backend)      │
└────────────────────────┘               └──────────┬───┬───────────┘
                                                       │   │
                                      ┌────────────────┘   └────────────────┐
                                      ▼                                     ▼
                             ┌────────────────┐                   ┌──────────────────┐
                             │   PostgreSQL    │                   │      Redis        │
                             │   (Supabase)    │                   │ cache / rate      │
                             └────────────────┘                   │ limiter / Celery  │
                                                                    │ broker+backend    │
                                                                    └─────────┬─────────┘
                                                                              ▼
                                                                     Celery worker
                                                                   (lottery draw job)

  External services: Resend (email) · PayPal Sandbox (checkout) · S3-compatible storage (images)
```

## Data flow

Two request shapes cover most of what this system does — a plain cached read, and the async
payment flow every checkout goes through.

**A cached, rate-limited read** (e.g. `GET /products/store-page`):

```
Frontend → FastAPI router
             │
             ├─ rate_limit() dependency: atomic Redis INCR on a route+identity key, 429 past the
             │  limit, fails OPEN (request proceeds) if Redis itself errors
             │
             ├─ cache hit  → msgpack-decode the cached payload, return it — no DB query at all
             │
             └─ cache miss → service layer builds the response, Pydantic-validates it against the
                real response schema, msgpack-encodes + SETEXs it with a TTL, returns it
```

**Ticket checkout with PayPal** — the flow that actually exercises concurrency, webhook handling,
and cache invalidation together, end to end:

1. Fan hits `POST /tickets/checkout` (rate-limited 3/60s per user — inventory/money, not a free
   read). The service takes a row lock on the `ticket_type` (`SELECT ... FOR UPDATE`), checks
   remaining stock *under that lock*, creates a `pending_payment` Ticket row, asks PayPal to create
   an order, and commits once — no stock is decremented yet, deliberately.
2. The frontend redirects the fan to PayPal's hosted approval page; PayPal redirects back with a
   token once they approve.
3. The frontend calls `POST /payment/paypal/capture/{pg_order_id}`. Independently, on no fixed
   schedule, PayPal also calls `POST /payment/paypal/webhook` to reconcile the same payment — not a
   bug in either path, just how PayPal's async model works — and both endpoints funnel into the
   exact same `finalize_paypal_payment()` function rather than duplicating the logic twice.
4. Whichever of the two calls arrives first re-acquires the row lock, checks the payment is still
   `pending` (that check *is* the idempotency guard — no separate "have I seen this event before"
   table needed), decrements stock, captures the payment with PayPal, marks everything paid, and
   commits once. The call that loses that race sees a non-pending payment and quietly no-ops
   instead of double-charging or double-issuing a ticket.

The lottery side follows the same "lock, check under the lock, write, commit once" shape but with
an extra actor: a manager's `PUT /concerts/lottery-draw/{id}` only validates RBAC and enqueues a
Celery task (`app.tasks.lottery.draw_lottery`) rather than running the rank-cascade draw inline —
the algorithm itself locks every affected `ticket_types`/`lottery_campaigns`/`lottery_entries` row
for that concert before touching any of them. Full sequence diagram:
[`database-design.md` §5.2](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/database-design.md).
